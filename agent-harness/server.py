"""FastAPI SSE endpoint — the HTTP front door onto core/loop.py's ReAct
loop, for a native frontend (this project's target: a macOS/Swift app) to
consume instead of the terminal chat loop in main.py.

Per docs/research/MOBILE_EDGE_NOTES.md's "Path 1": nothing about the loop
changes for this. On macOS there's no cloud hop needed either — Ollama is
already local, so this server runs on the same machine as the Swift app and
talks to it over localhost.

Run with:
    uv run uvicorn server:app --reload

Data contract: POST /chat with {"session_id": str, "message": str} returns
a text/event-stream response. Each SSE "data:" line is one JSON event dict
in the exact shape core/loop.py's run() yields (turn_start, status,
thinking, tool_call, tool_result, final, max_turns) — see that function's
docstring, and docs/Understanding/loop_events_for_a_frontend.md, for the
full reference. The frontend should treat any "status" event as "still
working, no answer yet" until it sees the next event.
"""

import json
import os
from contextlib import asynccontextmanager
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from core.loop import run
from main import SYSTEM_PROMPT, connect_configured_servers
from mcp_client.client import MCPClient
from providers.base import Message
from providers.local import LocalProvider

load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # One provider + one MCPClient for the process lifetime, shared across
    # every session — same reason main.py's CLI only builds these once:
    # reconnecting MCP servers per request would be slow and pointless.
    app.state.provider = LocalProvider(model=os.environ.get("AGENT_MODEL", "qwen3:14b"))
    app.state.mcp = MCPClient()
    # session_id -> that conversation's growing message history. In-memory
    # only (lost on restart) — fine for a local desktop app; swap for a
    # real store later if conversations need to survive a server restart.
    sessions: dict[str, list[Message]] = {}
    app.state.sessions = sessions

    await connect_configured_servers(app.state.mcp)
    yield
    await app.state.mcp.disconnect_all()


app = FastAPI(lifespan=lifespan)


class ChatRequest(BaseModel):
    session_id: str
    message: str


def _sse(event: dict[str, Any]) -> str:
    return f"data: {json.dumps(event)}\n\n"


@app.post("/chat")
async def chat(req: ChatRequest) -> StreamingResponse:
    messages = app.state.sessions.setdefault(req.session_id, [])

    async def event_stream():
        async for event in run(
            req.message, app.state.provider, app.state.mcp, messages, SYSTEM_PROMPT
        ):
            yield _sse(event)

    return StreamingResponse(event_stream(), media_type="text/event-stream")
