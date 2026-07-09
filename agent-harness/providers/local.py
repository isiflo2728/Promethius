# providers/local.py
#
# The concrete BaseProvider implementation that talks to a model served by
# Ollama. This is the ONE file in the whole codebase that's allowed to know
# what OpenAI/Ollama's raw JSON looks like — everything it returns has
# already been translated into the provider-agnostic shapes from
# providers/base.py (Message, ToolCall, ModelResponse). See
# docs/Understanding/openai_sdk_and_response_shapes.md for the full
# field-by-field mapping this file implements.

import json
from openai import AsyncOpenAI
from providers.base import BaseProvider, Message, ToolCall, ModelResponse
from typing import Any, override
from collections.abc import AsyncIterator


class LocalProvider(BaseProvider):
    def __init__(
        self, model: str = "qwen3:14b", base_url: str = "http://localhost:11434/v1"
    ):
        # AsyncOpenAI is the OpenAI SDK's client — but pointed at Ollama's
        # own server instead of OpenAI's. Ollama deliberately serves an
        # OpenAI-compatible endpoint, so the same SDK works unmodified.
        # api_key="ollama" is a throwaway value: the SDK requires *some*
        # non-empty string here, but Ollama doesn't check it (no real auth,
        # no billing — it's your own laptop).
        self.client = AsyncOpenAI(base_url=base_url, api_key="ollama")
        self.model = model

    @override
    async def complete(
        self,
        messages: list[Message],
        tools: list[dict[str, Any]],
        system: str,
    ) -> ModelResponse:
        """Send one full conversation to the model, get one full reply back.

        This is the method the agent loop calls each turn. Its whole job is:
        translate our shapes -> call the SDK -> translate the SDK's response
        back into our shapes. Nothing else in the codebase should ever touch
        `response.choices[0]...` directly.
        """
        response = await self.client.chat.completions.create(
            model=self.model,
            # We build these as plain JSON-Schema-shaped dicts rather than the
            # SDK's TypedDicts (ChatCompletionMessageParam etc.) — that's the
            # whole point of keeping our own Message/Tool shapes provider-agnostic.
            messages=self._format_messages(messages, system),  # pyright: ignore[reportArgumentType]
            tools=self._format_tools(tools) if tools else None,  # pyright: ignore[reportArgumentType]
        )

        # response.choices is a list because the API supports asking for
        # multiple candidate replies at once (the `n` parameter). We never
        # set `n`, so there's always exactly one — choices[0] is "the reply."
        msg = response.choices[0].message

        tool_calls = []
        if msg.tool_calls:
            for tc in msg.tool_calls:
                # We only ever send `type: "function"` tools (see
                # _format_tools), so a "custom" tool call should never come
                # back — but the SDK's type is a union, so narrow on it
                # rather than assuming .function exists.
                if tc.type != "function":
                    continue
                tool_calls.append(
                    ToolCall(
                        id=tc.id,
                        name=tc.function.name,
                        # tc.function.arguments is a JSON-encoded STRING (the
                        # model generated raw text, not a real object) — this
                        # is the one place that string has to become a real
                        # dict before it's usable.
                        arguments=json.loads(tc.function.arguments),
                    )
                )

        # response.usage is Optional in the SDK's own types (a provider could
        # theoretically omit it) — guard against None rather than assume it's
        # always there.
        usage = response.usage

        return ModelResponse(
            # msg.content is None when the model only requested tool calls
            # and said nothing else — normalize that to "" so callers don't
            # have to handle None on top of empty string.
            content=msg.content or "",
            tool_calls=tool_calls,
            # e.g. "stop" (done) vs "tool_calls" (wants to run something) —
            # see Choice.finish_reason in the SDK for the full fixed set of
            # values this can be.
            stop_reason=response.choices[0].finish_reason,
            usage={
                "input_tokens": usage.prompt_tokens if usage else 0,
                "output_tokens": usage.completion_tokens if usage else 0,
            },
        )

    @override
    async def stream(
        self,
        messages: list[Message],
        tools: list[dict[str, Any]],
        system: str,
    ) -> AsyncIterator[str]:
        """Like `complete()`, but yields text as it's generated instead of
        waiting for the whole reply.

        Streaming mode returns a *different* SDK type per chunk
        (ChatCompletionChunk, not ChatCompletion) — each chunk carries a
        small piece of new text under `.delta.content` instead of a full
        `.message`. That's why this reads `chunk.choices[0].delta.content`
        rather than `.message.content`.
        """
        response = await self.client.chat.completions.create(  # pyright: ignore[reportCallIssue]
            model=self.model,
            messages=self._format_messages(messages, system),  # pyright: ignore[reportArgumentType]
            tools=self._format_tools(tools) if tools else None,  # pyright: ignore[reportArgumentType]
            stream=True,
        )
        async for chunk in response:
            delta = chunk.choices[0].delta.content
            if delta:  # delta can be None between content chunks (e.g. on a tool-call-only chunk)
                yield delta

    @override
    def format_tool_result(
        self,
        tool_call_id: str,
        result: str,
    ) -> Message:
        """Wrap a tool's string output in a Message so the loop can append
        it to history and send it back to the model next turn.

        tool_call_id must match the id on the ToolCall this is answering —
        it's how the model lines up "here's the result" with "which request
        was this for," since a single turn can request multiple tools at once.
        """
        return Message(
            role="tool",
            content=result,
            tool_call_id=tool_call_id,
        )

    def _format_messages(
        self, messages: list[Message], system: str
    ) -> list[dict[str, Any]]:
        """Convert our internal `list[Message]` into the plain dicts the
        OpenAI-compatible API expects.

        The system prompt is injected here, as the first message, rather
        than being stored in `messages` itself — callers of this provider
        never have to think about where the system prompt goes in the wire
        format, only that a `system: str` gets passed in alongside the
        conversation.
        """
        out: list[dict[str, Any]] = [{"role": "system", "content": system}]
        for m in messages:
            if m.role == "tool":
                # Tool-result messages need tool_call_id so the model can
                # match this result back to the ToolCall it made — a plain
                # {"role": ..., "content": ...} pair isn't enough on its own.
                out.append(
                    {
                        "role": "tool",
                        "content": m.content,
                        "tool_call_id": m.tool_call_id,
                    }
                )
            else:
                # user / assistant messages: just role + content, no extra
                # bookkeeping fields needed.
                out.append({"role": m.role, "content": m.content})
        return out

    def _format_tools(self, tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Translate our Tool schemas (MCP/JSON-Schema-shaped: name,
        description, input_schema) into OpenAI's expected tool-call format.

        The only real translation is `input_schema` -> `parameters` — the
        rest is just nesting the same data one level deeper under
        `{"type": "function", "function": {...}}`, which is the shape every
        OpenAI-compatible API expects a tool definition in.
        """
        return [
            {
                "type": "function",
                "function": {
                    "name": t["name"],
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {}),
                },
            }
            for t in tools
        ]
