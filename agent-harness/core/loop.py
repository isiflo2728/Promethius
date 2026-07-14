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
) -> str:
    """Run one user turn through the ReAct loop; return the model's final
    text reply.

    `messages` is mutated in place (each turn's messages are appended to
    it) so the caller's conversation history keeps growing across
    successive calls to `run()` — the same shape `Agent.run()` was always
    meant to have, just against the provider/MCP stack instead of a raw
    OpenAI client.

    Loop, per turn:
      1. Send the full history + MCP tool schemas to the model.
      2. No tool calls -> the model is done; return its text.
      3. Tool calls -> append the assistant's tool-call request, dispatch
         each call through MCP, append each result, go to 1.
    """
    messages.append(Message(role="user", content=user_input))

    for turn in range(max_turns):
        print(f"\n[turn {turn + 1}]")

        response = await provider.complete(
            messages=messages,
            tools=mcp.schemas(),
            system=system,
        )

        # No tool calls — model is done, this is the final answer.
        if not response.tool_calls:
            messages.append(Message(role="assistant", content=response.content))
            return response.content

        if response.content:
            print(f"Thinking: {response.content}")

        # The assistant's tool-call request has to be appended as its own
        # message *before* the tool results that answer it — the model's
        # tool_call ids are what the following "tool" messages reference.
        # content is the ToolCall list itself (Message.content: str |
        # list[ToolCall]), not response.content's text — the two are
        # different fields on ModelResponse for exactly this reason.
        messages.append(Message(role="assistant", content=response.tool_calls))

        for tc in response.tool_calls:
            print(f"-> calling: {tc.name}({tc.arguments})")

            try:
                # MCPClient finds whichever connected server owns this
                # tool and dispatches to it; always returns a string
                # (never raises) per its own contract, but this loop
                # still guards the call — a broken tool must not crash
                # the loop, same rule CLAUDE.md states for local dispatch.
                result = await mcp.call(tc.name, tc.arguments)
            except Exception as e:
                result = f"Error: {e}"

            print(f"<- result: {result[:200]}")

            messages.append(provider.format_tool_result(tc.id, result))

    # Hermes handles this with a grace call asking the model to wrap up;
    # not built here yet — rare enough in practice to defer until a real
    # task actually hits it.
    return "Reached max turns without finishing."
