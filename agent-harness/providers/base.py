"""
Provider-agnostic shapes for talking to a model.

Every LLM API (Ollama, OpenAI, Anthropic, ...) returns JSON in a slightly
different shape. If the rest of the codebase (the agent loop) spoke each
provider's raw JSON directly, swapping providers would mean rewriting the
loop. Instead, every provider implementation translates its own JSON into
these three dataclasses on the way in, and back out again on the way out.
The loop only ever touches Message/ToolCall/ModelResponse — it never knows
or cares which provider is behind them.
"""

from dataclasses import dataclass
from abc import ABC, abstractmethod
from typing import Any
from collections.abc import AsyncIterator


@dataclass
class ToolCall:
    """One request from the model to run a specific tool.

    The model doesn't actually execute anything itself — it just outputs
    "call this tool with these arguments" and your code is responsible for
    running it and feeding the result back. This dataclass is that request,
    normalized into a shape that doesn't depend on which provider sent it.
    """

    id: str  # unique per call; used later to match this call to its result
    name: str  # which tool to run, e.g. "read_file"
    arguments: dict[str, object]  # the parsed arguments to call it with


@dataclass
class Message:
    """One entry in the conversation history sent to the model.

    LLM APIs are stateless — the entire conversation has to be resent on
    every turn. `Message` is the one shape used for every kind of turn
    (user text, assistant text, assistant tool-call request, tool result),
    so the growing history is just `list[Message]` regardless of what
    each message actually contains.
    """

    role: str  # "user" | "assistant" | "tool" — who this message is from
    content: (
        str | list[ToolCall]
    )  # plain text, or tool calls the assistant is requesting
    # The next two fields only apply to role="tool" messages — a tool's
    # result has to say which prior ToolCall it's answering, since a model
    # can request multiple tools in one turn and results may return
    # out of order.
    tool_call_id: str | None = None
    tool_name: str | None = None


@dataclass
class ModelResponse:
    """The normalized result of one call to `complete()`.

    Whatever a provider's raw API response looks like, it gets unpacked
    into this shape before the loop ever sees it — text, any tool calls
    requested, why the model stopped generating, and token usage.
    """

    content: str  # the model's text reply (empty if it only requested tool calls)
    tool_calls: list[ToolCall]  # tools the model wants to run this turn (may be empty)
    stop_reason: str  # e.g. "end_turn" (done) vs "tool_use" (wants to call a tool)
    usage: dict[str, object]  # token counts etc., for cost/budget tracking


class BaseProvider(ABC):
    """Interface every model provider (Ollama, OpenAI, Anthropic, ...) must implement.

    Subclassing ABC means Python refuses to instantiate a subclass that's
    missing any of these methods — you find out at startup, not mid-run.
    The agent loop is written entirely against this interface, so adding a
    new provider later never requires touching the loop itself.
    """

    @abstractmethod
    async def complete(
        self,
        messages: list[Message],
        tools: list[dict[str, Any]],
        system: str,
    ) -> ModelResponse:
        """Send the full conversation + available tool schemas, get one response back."""
        ...

    @abstractmethod
    async def stream(
        self,
        messages: list[Message],
        tools: list[dict[str, Any]],
        system: str,
    ) -> AsyncIterator[str]:
        """Like `complete()`, but yields text chunks as they're generated instead of waiting for the full reply."""
        # The `yield` below never runs (this method is always overridden) — it
        # only exists so type checkers infer this as an async generator, not
        # a coroutine that returns one. Without it, `stream()` implementations
        # that use `yield` (like `LocalProvider.stream`) mismatch this
        # signature under strict type checking.
        yield ""

    @abstractmethod
    def format_tool_result(self, tool_call_id: str, result: str) -> Message:
        """Wrap a tool's output string into a Message the model can be sent next turn."""
        ...
