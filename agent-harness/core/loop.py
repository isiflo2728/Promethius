"""The ReAct loop: Thought -> Action -> Observation, repeat until done.

Grounded against two real reference implementations, not just the paper:
- LangGraph's own ReAct agent template (github.com/langchain-ai/react-agent)
  confirms the modern, tool-calling-API shape of this loop: call the model,
  route on whether it returned tool_calls, execute tools if so, loop back —
  no text-parsed "Thought:"/"Action:" lines, since that's what structured
  tool-calling replaced. Its `route_model_output` is exactly the `if not
  response.tool_calls` branch below.
- marcosf63/react-agent-framework's docs restate the underlying cycle in
  plain terms: Thought (reasoning) -> Action (tool call) -> Observation
  (tool result) -> repeat until there's enough to answer. That's the
  concept; the LangGraph reference is what the *mechanics* look like once
  "Action" is a structured tool_calls entry instead of parsed text.

This implementation follows docs/AGENT_ARCHITECTURE.md section 6's design
(`core/loop.py` dispatching via MCP) but is written against the code that
actually exists today, not the pseudocode there — two real differences:
  - `BaseProvider.format_tool_result(tool_call_id, result)` only takes two
    arguments (see providers/base.py); the doc's pseudocode passed a third
    `tc.name` that the real method doesn't accept.
  - Tool dispatch goes through this project's own `MCPClient` (which
    already flattens a CallToolResult into a plain string and routes to
    whichever server owns the tool), not a raw `mcp.ClientSession` per the
    doc's sketch — so there's no `result.content[0].text` unpacking here.

core/history.py and core/interrupts.py (also sketched in that doc) don't
exist yet, so this takes a plain `list[Message]` instead of a `History`
object and has no interrupt-checking — per CLAUDE.md, that's a deliberate
"don't build until there's a concrete need" call, not an oversight.
"""

from typing import Any
from collections.abc import AsyncIterator

from providers.base import BaseProvider, Message
from mcp_client.client import MCPClient

# Hermes' default is 90 turns; docs/AGENT_ARCHITECTURE.md's north star
# picks 20 for this project "for now — increase as tasks get more complex."
MAX_TURNS = 20


async def run(
    user_input: str,
    provider: BaseProvider,
    mcp: MCPClient,
    messages: list[Message],
    system: str,
    max_turns: int = MAX_TURNS,
) -> AsyncIterator[dict[str, Any]]:
    """Run one user turn through the ReAct loop, yielding one event dict per
    step instead of printing directly — both consumers of this generator
    (main.py's CLI, server.py's SSE endpoint) turn these into their own
    output (print lines vs. JSON-over-SSE) instead of loop.py picking one
    format for everyone. See docs/Understanding/loop_events_for_a_frontend.md
    for the full design discussion and a worked example.

    A "turn" = one full trip through the for-loop below: one
    `provider.complete()` call, plus — if the model requested tools that
    turn — dispatching all of them and appending their results. It is NOT
    one turn per tool call; a single turn can dispatch several tools if the
    model requested several at once. `turn_start` fires once per model
    call, matching `for turn in range(max_turns)` exactly.

    Event shapes, in the order they can occur within a turn:
        {"type": "turn_start", "turn": int}
        {"type": "status", "state": "thinking"}
            -- yielded right before provider.complete(); the model is
            generating and has produced nothing observable yet. A consumer
            should show a "thinking" indicator from this point until it
            sees the next event.
        {"type": "thinking", "text": str}
            -- the model returned text *alongside* a tool-call request
            (e.g. "Let me check that for you") — this is content the
            model actually said, distinct from the "status" event above.
        {"type": "status", "state": "tool_running", "name": str}
            -- yielded right before dispatching one specific tool call.
        {"type": "tool_call", "id": str, "name": str, "arguments": dict}
        {"type": "tool_result", "tool_call_id": str, "name": str, "result": str}
        {"type": "final", "text": str}
            -- the model is done; this is its final answer for the turn.
        {"type": "max_turns"}
            -- max_turns was reached without a "final" event.

    `messages` is mutated in place (each turn's messages are appended to
    it) so the caller's conversation history keeps growing across
    successive calls to `run()` — the same shape `Agent.run()` was always
    meant to have, just against the provider/MCP stack instead of a raw
    OpenAI client.
    """
    messages.append(Message(role="user", content=user_input))

    for turn in range(max_turns):
        yield {"type": "turn_start", "turn": turn + 1}
        yield {"type": "status", "state": "thinking"}

        response = await provider.complete(
            messages=messages,
            tools=mcp.schemas(),
            system=system,
        )

        # No tool calls — model is done, this is the final answer.
        if not response.tool_calls:
            messages.append(Message(role="assistant", content=response.content))
            yield {"type": "final", "text": response.content}
            return

        if response.content:
            yield {"type": "thinking", "text": response.content}

        # The assistant's tool-call request has to be appended as its own
        # message *before* the tool results that answer it — the model's
        # tool_call ids are what the following "tool" messages reference.
        # content is the ToolCall list itself (Message.content: str |
        # list[ToolCall]), not response.content's text — the two are
        # different fields on ModelResponse for exactly this reason.
        messages.append(Message(role="assistant", content=response.tool_calls))

        for tc in response.tool_calls:
            yield {"type": "status", "state": "tool_running", "name": tc.name}
            yield {
                "type": "tool_call",
                "id": tc.id,
                "name": tc.name,
                "arguments": tc.arguments,
            }

            try:
                # MCPClient finds whichever connected server owns this
                # tool and dispatches to it; always returns a string
                # (never raises) per its own contract, but this loop
                # still guards the call — a broken tool must not crash
                # the loop, same rule CLAUDE.md states for local dispatch.
                result = await mcp.call(tc.name, tc.arguments)
            except Exception as e:
                result = f"Error: {e}"

            yield {
                "type": "tool_result",
                "tool_call_id": tc.id,
                "name": tc.name,
                "result": result,
            }

            messages.append(provider.format_tool_result(tc.id, result))

    # Hermes handles this with a grace call asking the model to wrap up;
    # not built here yet — rare enough in practice to defer until a real
    # task actually hits it.
    yield {"type": "max_turns"}
