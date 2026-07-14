# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A hand-rolled agent harness (no LangChain/LangGraph) targeting a local Ollama
model first, with Hermes Agent (NousResearch) studied as a design reference —
not a dependency. The codebase is currently a scaffold: files have
signatures, docstrings, and `TODO`/`raise NotImplementedError` bodies, not
working implementations. Read `docs/README.md`'s "Build order" before writing
code — it defines the exact sequence this project is meant to be built in.

## Commands

```bash
uv sync              # install deps into the uv-managed venv
uv run main.py       # run the agent (once implemented)
uv add <package>     # add a new dependency
```

No test suite, linter, or formatter is configured yet.

Requires Ollama running locally with a tool-calling-capable model pulled
(e.g. `ollama pull llama3.1`, then `ollama serve`). Before relying on any
model for tool calls, verify it actually supports them: `ollama show <model>`
and look for "tools" under Capabilities — claiming support and reliably
returning tool calls are not the same thing.

## Architecture

There are two layers of truth here that do not currently match, and that gap
is intentional (docs are ahead of code):

- **`docs/README.md`** describes the actual minimal scaffold being built,
  build order: `tool.py` → `agent.py` → `tools/example_tools.py` → `main.py`.
- **`docs/AGENT_ARCHITECTURE.md`** is a north-star reference design (MCP-based
  tool layer, `core/loop.py`, `core/history.py`, `core/interrupts.py`,
  `mcp_client/client.py`, `config.py`, a 6-phase roadmap) that the project is
  growing toward but has not reached. Don't assume directories/files it
  describes exist — check first.
- **`docs/research/learning_agent_architecture.md`** — notes distilled from reading
  Hermes Agent's actual source. The load-bearing ideas to carry forward:
  the core loop itself is tiny (~15-30 lines); prefer a **registry pattern**
  (self-registering tools) over an if/elif dispatcher once there are more
  than a handful of tools; treat **prompt caching** as a hard constraint —
  never mutate past messages, never swap tool schemas mid-conversation, keep
  the system prompt byte-stable for a conversation's lifetime; maintain
  **strict message role alternation** (no two same-role messages in a row);
  don't build memory/skills/delegation until there's a concrete need for
  them.
- **`docs/research/MOBILE_EDGE_NOTES.md`** — mobile/edge porting research. Conclusion:
  the loop's *concepts* port to Swift/Kotlin, the Python code does not. The
  planned path is thin-client-to-a-server first (Modal-hosted), on-device
  inference later. Don't let this pull mobile concerns into the current
  desktop/Ollama scaffold prematurely.

### Core abstraction (as designed in `tool.py` / `providers/base.py`)

- `Tool` (`tool.py`) — name + description + JSON Schema `parameters` + a
  Python `fn` that must return a string. `Tool.to_schema()` converts it to
  OpenAI-format (`{"type": "function", "function": {...}}`) — this is the
  only shape the model ever sees. The agent should never know what a tool
  *does*, only how to describe and call it.
- `Message` / `ToolCall` / `ModelResponse` (`providers/base.py`) — the
  provider-agnostic internal representation of a conversation turn. The
  point of this layer: whatever provider is behind it (Ollama now, others
  later), the rest of the code only ever deals in these three shapes.
- `BaseProvider` (`providers/base.py`) — ABC with `complete()`, `stream()`,
  `format_tool_result()`. `providers/local.py` is meant to implement this
  against Ollama's OpenAI-compatible endpoint (`http://localhost:11434/v1`).
- `Agent` — currently in `archive/agent.py` (not wired up at the project
  root yet). Owns the loop: send messages + tool schemas to the model,
  check for tool calls, dispatch by name via a `dict[str, Tool]` lookup
  (never if/elif), append results, repeat until plain text or
  `max_iterations` is hit. Tool dispatch (`_dispatch`) must catch all
  exceptions and return a JSON error string — a broken tool must not crash
  the loop.

### Known gaps to be aware of

- `providers/local.py` is currently a truncated stub (an incomplete import
  line) — not yet a working `BaseProvider` implementation.
- `archive/agent.py` holds the `Agent` scaffold but isn't imported from
  `main.py` yet; `main.py` itself is just a `NotImplementedError` stub with
  TODO comments describing the wiring it still needs.
- `core/` exists as an empty directory — reserved for the future
  `core/loop.py` / `core/history.py` / `core/interrupts.py` split described
  in `docs/AGENT_ARCHITECTURE.md`, not yet populated.
