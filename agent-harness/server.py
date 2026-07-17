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

This endpoint adds one event the loop itself never yields:
{"type": "error", "message": str} — emitted if the run raises (e.g. the
inference server is down), so a stream always ends with final, max_turns,
or error rather than just stopping. On any non-completed run the session's
history is rolled back to its pre-run state (see event_stream()).
"""

import asyncio
import json
import os
import re
import time
from contextlib import asynccontextmanager
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
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
    # See main.py's provider construction for why LLM_BASE_URL/LLM_API_KEY
    # exist — lets this point at Ollama or LM Studio without a code change.
    app.state.provider = LocalProvider(
        model=os.environ.get("AGENT_MODEL", "qwen3:14b"),
        base_url=os.environ.get("LLM_BASE_URL", "http://localhost:11434/v1"),
        api_key=os.environ.get("LLM_API_KEY", "ollama"),
    )
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


# The briefing fans out one small agent run per source instead of one big
# sweep: a ReAct loop is sequential (each tool call and model turn adds to
# the total), so a 4-source sweep pays the SUM of every source's calls,
# while parallel per-source runs pay roughly the SLOWEST one. Smaller runs
# also mean smaller contexts (better JSON, fewer retries) and failure
# isolation (one dead source costs its items, not the whole plate).
#
# Which sources to check. Composio's tool router only exposes meta-tools
# (SEARCH_TOOLS / MULTI_EXECUTE / ...), so a source can't be scoped by
# filtering tool schemas — it's scoped by prompt instead. Names here are
# plain words the model reads, not tool slugs.
#
# BRIEFING_SOURCES is the guaranteed baseline; on top of it, every app the
# user has actually connected in Composio is discovered live and appended
# (see _briefing_sources), so connecting e.g. Discord shows up on the plate
# without editing config or restarting.
BRIEFING_SOURCES = [
    s.strip()
    for s in os.environ.get("BRIEFING_SOURCES", "gmail,github,calendar").split(",")
    if s.strip()
]

# Connected toolkits that never make good briefing sources: storage apps
# hold files, not "needs your reply" items, and each source costs a full
# sub-agent run per refresh. Comma-separated env override.
BRIEFING_EXCLUDE = {
    s.strip()
    for s in os.environ.get(
        "BRIEFING_EXCLUDE", "googledocs,googlesheets,googledrive"
    ).split(",")
    if s.strip()
}

# Composio toolkit slug -> the word the briefing prompt uses. Also merges
# variants of one product ("discordbot" is how a Discord server connection
# is slugged, but the model should just be told "discord").
_SOURCE_ALIASES = {
    "discordbot": "discord",
    "googlecalendar": "calendar",
}

# How long a discovered source list stays good. Long enough that a briefing
# refresh doesn't pay the lookup every time, short enough that a newly
# connected app appears on the next plate refresh a few minutes later.
_SOURCES_TTL_SECONDS = 10 * 60
_sources_cache: tuple[float, list[str]] | None = None


async def _briefing_sources() -> list[str]:
    """BRIEFING_SOURCES plus whatever the user has connected in Composio.

    Asks Composio's REST API (same key as the MCP tool router) for ACTIVE
    connected accounts, normalizes the toolkit slugs, and appends anything
    not already in the baseline. Cached for _SOURCES_TTL_SECONDS. Any
    failure falls back to the baseline alone — discovery is an enhancement,
    never a reason a briefing can't run.
    """
    global _sources_cache
    if _sources_cache is not None and time.monotonic() - _sources_cache[0] < _SOURCES_TTL_SECONDS:
        return _sources_cache[1]

    sources = list(BRIEFING_SOURCES)
    api_key = os.environ.get("COMPOSIO_API_KEY")
    if api_key:
        try:
            params: dict[str, str] = {"statuses": "ACTIVE", "limit": "50"}
            # The tool router session serves one Composio user; without this
            # filter, accounts connected for *other* user ids in the same
            # Composio project would show up as sources the router can't
            # actually reach.
            if user_id := os.environ.get("COMPOSIO_USER_ID"):
                params["user_ids"] = user_id
            async with httpx.AsyncClient(
                base_url="https://backend.composio.dev/api/v3",
                headers={"x-api-key": api_key},
                timeout=15,
            ) as client:
                while True:
                    resp = await client.get("/connected_accounts", params=params)
                    resp.raise_for_status()
                    page = resp.json()
                    for account in page.get("items", []):
                        slug = account.get("toolkit", {}).get("slug", "")
                        source = _SOURCE_ALIASES.get(slug, slug)
                        # Excludable under either name (raw slug or alias).
                        if (
                            source
                            and slug not in BRIEFING_EXCLUDE
                            and source not in BRIEFING_EXCLUDE
                            and source not in sources
                        ):
                            sources.append(source)
                    cursor = page.get("next_cursor")
                    if not cursor:
                        break
                    params["cursor"] = cursor
        except Exception as e:
            print(f"[briefing] source discovery failed, using baseline only: "
                  f"{type(e).__name__}: {e}", flush=True)

    _sources_cache = (time.monotonic(), sources)
    return sources

# How many items the whole plate keeps after merging every source.
MAX_BRIEFING_ITEMS = 6
# Per-source item cap — keeps each sub-agent's answer (and the merge input)
# small; the plate-wide cap above does the final cut.
MAX_ITEMS_PER_SOURCE = 3

# The per-source prompt behind POST /briefing. Demands bare JSON (no fences,
# no prose) because the response is machine-parsed by _extract_json below —
# a model that wraps the object in commentary still parses, but the less
# it's tempted to, the better.
SOURCE_BRIEFING_PROMPT = """Check the user's {source} — and ONLY their \
{source}, no other app — for things the user needs to act on: unanswered \
messages, review requests, mentions, approaching deadlines. Request SMALL \
batches — e.g. the 10 most recent unread/open items — you are skimming for \
action items, not archiving.

Then reply with ONLY a JSON object — no prose before or after, no markdown \
code fences:

{{
  "items": [
    {{
      "title": "short imperative, e.g. 'Reply to Sam about the contract'",
      "source": "{source}",
      "detail": "one sentence of context",
      "urgency": "now | today | this_week"
    }}
  ]
}}

Order items most-urgent first and keep only the {max_items} most important. \
If {source} is not connected, errors, or genuinely has nothing needing \
attention, return {{"items": []}} — never invent items."""


class BriefingItem(BaseModel):
    title: str
    source: str = ""
    detail: str = ""
    urgency: str = "today"


class BriefingResponse(BaseModel):
    # False when no MCP servers are connected — the app shows a "connect your
    # accounts" state instead of pretending an empty plate is a clean one.
    connected: bool
    headline: str = ""
    items: list[BriefingItem] = []


def _extract_json(text: str) -> dict[str, Any]:
    """Pull the briefing object out of model output, tolerating reasoning
    preambles (<think> blocks), markdown fences, surrounding prose, and
    multiple JSON-ish blobs (observed with gpt-oss: it can emit intermediate
    objects before the real one). Scans every '{', keeps whatever actually
    parses, and prefers the object that looks like a briefing."""
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
    decoder = json.JSONDecoder()
    candidates: list[dict[str, Any]] = []
    idx = 0
    while (start := text.find("{", idx)) != -1:
        try:
            obj, consumed = decoder.raw_decode(text[start:])
        except json.JSONDecodeError:
            idx = start + 1
            continue
        if isinstance(obj, dict):
            candidates.append(obj)
        idx = start + consumed
    for obj in candidates:
        if "items" in obj or "headline" in obj:
            return obj
    if candidates:
        return candidates[-1]
    raise ValueError("no parseable JSON object in model output")


# Sort key for merging sources: most urgent first. Unknown urgency strings
# from a sloppy model sort with "today" rather than being dropped.
_URGENCY_ORDER = {"now": 0, "today": 1, "this_week": 2}


async def _run_briefing_source(
    source: str, provider: LocalProvider, mcp: MCPClient
) -> list[BriefingItem] | None:
    """One small agent run scoped to a single source.

    Returns the source's items, [] when the source genuinely has nothing
    (or isn't connected), or None when the run itself failed — the caller
    needs to tell "clean plate" apart from "couldn't look".

    Never raises: a broken source must cost its own items, not the plate.
    """
    prompt = SOURCE_BRIEFING_PROMPT.format(source=source, max_items=MAX_ITEMS_PER_SOURCE)

    # A single run isn't reliable on every model — gpt-oss occasionally
    # leaks raw harmony tokens ("<|channel|>...") instead of an answer, and
    # any model can return junk JSON once. Per-source runs are small and
    # cheap, so retry once before giving the source up.
    attempts = 2
    for attempt in range(1, attempts + 1):
        messages: list[Message] = []
        final_text: str | None = None
        try:
            async for event in run(
                prompt,
                provider,
                mcp,
                messages,
                SYSTEM_PROMPT,
                # One source needs few trips: discover tools, execute, answer.
                # Half the default keeps a wandering run from dragging the
                # whole (gathered) briefing out.
                max_turns=10,
                # Cap each tool result so one fat Gmail fetch can't overflow
                # the model's context window — the briefing only needs enough
                # of each item to name it, not full message bodies.
                max_result_chars=6_000,
            ):
                if event["type"] == "final":
                    final_text = event["text"]
        except Exception as e:
            print(f"[briefing:{source}] attempt {attempt} failed: "
                  f"{type(e).__name__}: {e}", flush=True)
            continue

        if final_text is None:
            print(f"[briefing:{source}] attempt {attempt} hit the turn limit",
                  flush=True)
            continue

        # Log the raw final text — the only way to tune the prompt against a
        # specific model's quirks is seeing what it actually said.
        print(f"[briefing:{source}] attempt {attempt} final text: {final_text!r}",
              flush=True)

        try:
            data = _extract_json(final_text)
        except (ValueError, json.JSONDecodeError):
            continue

        items: list[BriefingItem] = []
        for raw in data.get("items", []):
            if not isinstance(raw, dict):
                continue
            try:
                item = BriefingItem(**raw)
            except Exception:
                continue  # one malformed item shouldn't sink the source
            # The model sometimes omits/garbles the source field; it's
            # authoritative here anyway — this run only looked at `source`.
            item.source = source
            items.append(item)
        return items[:MAX_ITEMS_PER_SOURCE]

    return None


def _merge_briefing(
    sources: list[str],
    per_source: list[list[BriefingItem] | None],
) -> tuple[list[BriefingItem], list[str]]:
    """Merge per-source results (aligned with `sources`) into the final
    ranked plate, plus the names of sources whose runs failed."""
    items = [
        item
        for source_items in per_source
        if source_items is not None
        for item in source_items
    ]
    # sort() is stable, so within one urgency the per-source order (each
    # sub-agent already ranked its own items) is preserved.
    items.sort(key=lambda i: _URGENCY_ORDER.get(i.urgency, 1))
    failed = [
        source
        for source, source_items in zip(sources, per_source)
        if source_items is None
    ]
    return items[:MAX_BRIEFING_ITEMS], failed


def _headline(items: list[BriefingItem], failed_sources: list[str]) -> str:
    """One-sentence summary of the plate, built in code — a whole model call
    just to phrase a sentence would reintroduce latency the fan-out removed."""
    if not items:
        head = "All clear — nothing needs you right now."
    elif len(items) == 1:
        head = "One thing needs you."
    else:
        now_count = sum(1 for i in items if i.urgency == "now")
        head = f"{len(items)} things need you"
        head += f" — {now_count} right now." if now_count else "."
    if failed_sources:
        head += f" (Couldn't check {', '.join(failed_sources)}.)"
    return head


@app.post("/briefing")
async def briefing() -> BriefingResponse:
    """Return a structured to-do briefing for the Today view's "On your
    plate" section: one concurrent agent run per BRIEFING_SOURCES entry,
    merged and ranked in code (see the comment above BRIEFING_SOURCES for
    why fan-out, and why no aggregator agent).

    Unlike /chat this is a plain JSON response, not SSE: the app wants the
    finished list, not a play-by-play. Every run uses a throwaway history so
    briefings never pollute chat sessions (and vice versa).
    """
    if not app.state.mcp.schemas():
        return BriefingResponse(connected=False)

    sources = await _briefing_sources()
    per_source = await asyncio.gather(
        *(
            _run_briefing_source(source, app.state.provider, app.state.mcp)
            for source in sources
        )
    )
    items, failed = _merge_briefing(sources, per_source)

    # Every source failing is a server-side problem, not an empty plate —
    # a 200 here would overwrite the app's cached briefing with a false
    # "all clear" (the app keeps the stale plate on an error response).
    if failed and len(failed) == len(sources):
        raise HTTPException(502, f"Every briefing source failed: {', '.join(failed)}")

    return BriefingResponse(
        connected=True, headline=_headline(items, failed), items=items
    )


@app.post("/chat")
async def chat(req: ChatRequest) -> StreamingResponse:
    messages = app.state.sessions.setdefault(req.session_id, [])

    async def event_stream():
        # core/loop.py deliberately has no error handling of its own, so a
        # failure mid-run (model server down, provider exception) used to just
        # kill the SSE stream with no explanation — the client saw the
        # connection end and had to guess. Two guarantees added here:
        #
        # 1. The client always gets a terminal event: {"type": "error", ...}
        #    joins final/max_turns as the ways a stream can end.
        # 2. The session history can't be left mid-exchange. A failed or
        #    cancelled run could strand a trailing user message or an
        #    assistant tool-call with no tool results, which breaks the strict
        #    role alternation the model needs on the *next* request for this
        #    session_id. Rolling back to the pre-run length keeps the session
        #    usable (the failed turn is dropped entirely).
        history_len = len(messages)
        completed = False
        try:
            async for event in run(
                req.message, app.state.provider, app.state.mcp, messages, SYSTEM_PROMPT
            ):
                yield _sse(event)
            completed = True
        except Exception as e:
            yield _sse({"type": "error", "message": f"{type(e).__name__}: {e}"})
        finally:
            # Covers the except branch above AND client disconnects
            # (CancelledError/GeneratorExit unwind through here).
            if not completed:
                del messages[history_len:]

    return StreamingResponse(event_stream(), media_type="text/event-stream")
