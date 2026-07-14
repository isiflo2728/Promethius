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

SYSTEM_PROMPT = "You are a helpful assistant with access to tools. Use them when they help answer the user's request."


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


async def main() -> None:
    provider = LocalProvider(model=os.environ.get("AGENT_MODEL", "qwen3:14b"))
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

            reply = await run(user_input, provider, mcp, messages, SYSTEM_PROMPT)
            print(f"\n{reply}")

    except KeyboardInterrupt:
        print("\n[Interrupted]")

    finally:
        # Always tear down connected servers — the Composio session and
        # any subprocess-backed servers — even if the loop above raised.
        await mcp.disconnect_all()


if __name__ == "__main__":
    asyncio.run(main())
