"""Entry point — wire the pieces together into a simple chat loop.

Everything downstream (LocalProvider, MCPClient) is async, so this runs
under asyncio.run() rather than the plain input()/print() loop the old
TODOs here described — that sketch predates providers/local.py and
mcp_client/client.py.

MCP server connections are driven entirely by environment variables so
this runs today with zero tools configured (plain chat against Ollama),
and picks up Composio the moment its two env vars are set — no code
changes needed either way:

    COMPOSIO_MCP_URL=https://backend.composio.dev/v3/mcp/{server_id}?user_id={id}
    COMPOSIO_API_KEY=...

Both are read from a local .env file (gitignored — never commit it) via
python-dotenv, so they only need to be set once rather than exported in
every shell session.
"""

import asyncio
import os

from dotenv import load_dotenv

from core.loop import run
from mcp_client.client import MCPClient
from providers.base import Message
from providers.local import LocalProvider

load_dotenv()

# The base instruction alone (just "use tools when they help") let
# qwen3:14b call a real tool on turn 1, then on turn 2 just *describe* the
# result in plain text instead of continuing to act on it — see
# docs/ISSUES.md item 7. Both blocks below are adapted verbatim from
# Hermes Agent's agent/prompt_builder.py (TOOL_USE_ENFORCEMENT_GUIDANCE,
# TASK_COMPLETION_GUIDANCE — see docs/research/learning_agent_architecture.md's
# "Part 0" for the full writeup and why "qwen" specifically is one of the
# model families Hermes gates this guidance to). Applied unconditionally
# here rather than gated by model name substring, since this project
# currently only targets one model family at a time via AGENT_MODEL —
# revisit with Hermes's substring-gating approach if a model that doesn't
# need this steering is ever added.
SYSTEM_PROMPT = """You are a helpful assistant with access to tools. Use them when they help answer the user's request.

# Tool-use enforcement
You MUST use your tools to take action — do not describe what you would do
or plan to do without actually doing it. When you say you will perform an
action (e.g. 'I will run the tests', 'Let me check the file', 'I will create
the project'), you MUST immediately make the corresponding tool call in the same
response. Never end your turn with a promise of future action — execute it now.
Keep working until the task is actually complete. Do not stop with a summary of
what you plan to do next time. If you have tools available that can accomplish
the task, use them instead of telling the user what you would do.
Every response should either (a) contain tool calls that make progress, or
(b) deliver a final result to the user. Responses that only describe intentions
without acting are not acceptable.

# Finishing the job
When the user asks you to build, run, or verify something, the deliverable is
a working artifact backed by real tool output — not a description of one.
Do not stop after writing a stub, a plan, or a single command. Keep working
until you have actually exercised the code or produced the requested result,
then report what real execution returned.
If a tool, install, or network call fails and blocks the real path, say so
directly and try an alternative (different package manager, different
approach, ask the user). NEVER substitute plausible-looking fabricated
output (made-up data, invented file contents, synthesised API responses)
for results you couldn't actually produce. Reporting a blocker honestly
is always better than inventing a result."""


async def connect_configured_servers(mcp: MCPClient) -> None:
    """Connect whatever MCP servers are configured via env vars.

    Currently just Composio, since that's the one this project is being
    tested against — add more `if os.environ.get(...)` blocks here as
    other servers come into play, same pattern each time.
    """
    composio_url = os.environ.get("COMPOSIO_MCP_URL")
    composio_key = os.environ.get("COMPOSIO_API_KEY")

    if composio_url and composio_key:
        print(f"Connecting to Composio MCP server...")
        await mcp.connect_http(
            "composio", composio_url, headers={"x-api-key": composio_key}
        )
        print(f"Connected — {len(mcp.schemas())} tool(s) available.")
    else:
        print(
            "COMPOSIO_MCP_URL / COMPOSIO_API_KEY not set — running with no "
            "tools. Set both env vars and restart to connect Composio."
        )


async def print_events(
    user_input: str, provider: LocalProvider, mcp: MCPClient, messages: list[Message]
) -> None:
    """Drive core.loop.run() for one user turn, printing a line per event.

    core/loop.py no longer prints anything itself — it only yields event
    dicts, so both this CLI and server.py's SSE endpoint can turn the same
    events into their own output format. See core/loop.py's run() docstring
    (and docs/Understanding/loop_events_for_a_frontend.md) for the full
    event shape reference and what a "turn" means.
    """
    async for event in run(user_input, provider, mcp, messages, SYSTEM_PROMPT):
        match event["type"]:
            case "turn_start":
                # One turn = one model call, plus dispatching any tools it
                # requests that call. Not one turn per tool.
                print(f"\n[turn {event['turn']}: asking the model for a response]")
            case "status":
                if event["state"] == "thinking":
                    print("  ...waiting on the model (no response yet)")
                elif event["state"] == "tool_running":
                    print(f"  ...running tool '{event['name']}'")
            case "thinking":
                print(f"Thinking: {event['text']}")
            case "tool_call":
                print(f"-> calling: {event['name']}({event['arguments']})")
            case "tool_result":
                print(f"<- result: {event['result'][:200]}")
            case "final":
                print(f"\n{event['text']}")
            case "max_turns":
                print("\nReached max turns without finishing.")


async def main() -> None:
    # LLM_BASE_URL/LLM_API_KEY let this point at any OpenAI-compatible local
    # server, not just Ollama — e.g. LM Studio's server is at
    # http://localhost:1234/v1 with api_key="lm-studio" (still just a
    # throwaway placeholder, same as Ollama's "ollama" — neither server
    # actually validates it). See docs/README.md's "Switching inference
    # engines" section.
    provider = LocalProvider(
        model=os.environ.get("AGENT_MODEL", "qwen3:14b"),
        base_url=os.environ.get("LLM_BASE_URL", "http://localhost:11434/v1"),
        api_key=os.environ.get("LLM_API_KEY", "ollama"),
    )
    mcp = MCPClient()
    messages: list[Message] = []

    try:
        await connect_configured_servers(mcp)

        print("\nType a message ('exit' to quit, Ctrl+C to interrupt).")
        while True:
            try:
                user_input = input("\n> ").strip()
            except EOFError:
                break

            if not user_input:
                continue
            if user_input.lower() in ("exit", "quit"):
                break

            await print_events(user_input, provider, mcp, messages)

    except KeyboardInterrupt:
        print("\n[Interrupted]")

    finally:
        # Always tear down connected servers — the Composio session and
        # any subprocess-backed servers — even if the loop above raised.
        await mcp.disconnect_all()


if __name__ == "__main__":
    asyncio.run(main())
