# cerebras-version — changes compared to `develop`

33 files changed, ~3,600 insertions. The theme of the branch: the Today view
became a real, harness-backed home tab; inference became swappable between a
local model and Cerebras's cloud API; and the briefing pipeline was rebuilt
for speed and reliability. Everything below is relative to `develop`
(`5815c56`).

---

## 1. Cerebras (cloud) inference support

*Files: `agent-harness/.env.example` (new), `agent-harness/server.py`, docs*

The provider layer already spoke the OpenAI-compatible API; this branch makes
the cloud path a first-class, documented option:

- **`.env` chooses the engine** — LM Studio (local, private) or Cerebras
  (`https://api.cerebras.ai/v1`, `gpt-oss-120b`). No code changes to switch.
- **New `agent-harness/.env.example`** documents every variable with safe
  placeholder values (no real keys committed anywhere on this branch).
- Why Cerebras: measured briefing latency dropped from ~176–260s (local
  gpt-oss-20b) to ~18s once no source hangs; larger model produces more
  reliable JSON. Trade-offs documented in the README (data leaves the
  machine; free tier's 5 req/min is too tight for agent loops — the
  pay-as-you-go tier is required for real use).

## 2. Tool-call timeout: moved into the MCP client (crash fix)

*Files: `agent-harness/core/loop.py`, `agent-harness/mcp_client/client.py`*

`develop` had no per-tool timeout; a hung Composio call (observed: a
`MULTI_EXECUTE` fetching a full recursive repo tree) stalled runs silently.
The first fix attempt (`asyncio.wait_for` around the MCP call) crashed whole
runs: cancelling `call_tool` from outside violates the MCP session's anyio
cancel-scope hierarchy, escaping as an uncatchable `CancelledError` and
leaving the session broken for every subsequent call.

This branch does it correctly:

- `MCPClient.call()` gains a `timeout_seconds` parameter, passed to the MCP
  SDK's own `read_timeout_seconds` so the timeout fires *inside* the
  session's scopes and surfaces as a catchable `McpError`.
- A timed-out call returns a guidance string telling the model not to retry
  the identical call (a hung tool would just burn another window).
- A timeout deliberately does **not** trigger the stale-session
  reconnect-and-retry path — that would rerun the exact call that just hung.
- The policy constant (`TOOL_TIMEOUT_SECONDS = 240`) stays in `core/loop.py`;
  both files carry comments explaining why this must not be "simplified"
  back to `wait_for`.

## 3. `/briefing`: parallel per-source fan-out with live source discovery

*File: `agent-harness/server.py` (+378 lines)*

`develop` had a single monolithic briefing agent that swept every source
sequentially (total time = sum of all tool calls, one bad source sank the
whole run, and its one big context overflowed local models). Rebuilt:

- **One small agent per source, run concurrently** (`asyncio.gather`). Wall
  time ≈ the slowest source instead of the sum. Each sub-agent gets a
  source-scoped prompt, a 10-turn cap, a 6,000-char tool-result cap, and one
  retry.
- **Live connected-app discovery** — the server asks Composio's REST API
  which apps the user actually has ACTIVE connections for (cached 10
  minutes, filtered by `COMPOSIO_USER_ID`), normalizes toolkit slugs
  (`discordbot`→`discord`, `googlecalendar`→`calendar`), and appends them to
  the `BRIEFING_SOURCES` baseline. Connecting a new app in Composio puts it
  on the plate automatically; storage apps (docs/sheets/drive) are excluded
  by default via `BRIEFING_EXCLUDE`. Discovery failure falls back to the
  baseline — it can never block a briefing.
- **Merge in code, not in a model** — items concatenate, stable-sort by
  urgency (`now`/`today`/`this_week`), cap at 6; the headline is composed
  deterministically. No aggregator agent (that would reintroduce the latency
  the fan-out removed).
- **Failure isolation** — a failed source costs only its own items and is
  named in the headline ("Couldn't check discord."). Only if *every* source
  fails does the endpoint return 502, so the app's cached plate is never
  overwritten by a false "all clear". The per-source runner distinguishes
  "genuinely empty" (`[]`) from "run failed" (`None`) for exactly this.

Because Composio's tool router only exposes meta-tools
(`COMPOSIO_SEARCH_TOOLS` / `MULTI_EXECUTE` / …), sources are scoped by
prompt, not by filtering tool schemas — that constraint is documented in the
code.

## 4. Today view — new home tab (Mac app)

*Files: `Views/TodayView.swift` (new, 705 lines),
`ViewModels/TodayViewModel.swift` (new), `ViewModels/ChatViewModel.swift`
(new), `Harness/HarnessClient.swift` + `HarnessEvent.swift` +
`HarnessBriefing.swift` (new), `AgentHubMacApp.swift`,
`Services/CalendarService.swift` (new), `AgentHubMac.entitlements` (new)*

- **"On your plate"** — the agent-built briefing. Stale-while-revalidate
  caching (memory + UserDefaults, 30-minute max age): the cached plate shows
  instantly, a fresh agent run swaps in behind it. `warmBriefing()` fires at
  app launch so the run is underway before the user looks; a shared
  in-flight task dedupes concurrent refreshes; a failed refresh keeps the
  stale plate. Has a ↻ force-refresh button. Items decode tolerantly
  (`HarnessBriefing`) — only `title` is required, everything else degrades
  gracefully when a model garbles a field.
- **Ask-anything bar** — streams questions through `POST /chat` (SSE) via the
  new `HarnessClient`/`HarnessEvent`; live status line ("Running
  GMAIL_FETCH_EMAILS…"), stop button, clear/new-session support.
  **The `ChatViewModel` is owned by `RootView`, not the Today tab** — the
  detail pane's `switch` destroys the tab's views on every navigation, and
  view-local state was silently discarding the transcript and minting a new
  server session per tab switch (fixed on this branch).
- **"What's next"** — real calendar events via the new EventKit-backed
  `CalendarService` (7-day window; needs the new calendars entitlement +
  usage description). Has its own ↻ refresh that re-reads the local EventKit
  store.
- **Needs you** — pending approvals with editable drafts, stalled-agent
  surfacing.

## 5. Harness-driven agent runs + scheduling (Mac app)

*Files: `Services/AgentRunner.swift` (+177), `Services/AgentScheduler.swift`
(new), `Views/ScheduleAgentView.swift` (new), `Services/SystemStats.swift`
(new), `Views/AgentDetailView.swift` (+368), `Views/SidebarView.swift`,
`Views/MissionControlView.swift`, `Components/ApprovalCard.swift`, models*

- **`AgentRunner`** now executes runs by driving the harness backend and
  streaming loop events into persisted `RunLogEntry` rows and status
  transitions — runs are watchable live in the detail view. (Pre-execution
  approval gating for harness tool calls still needs a backend interrupt
  point; local-tool dispatch keeps its approval gate.)
- **`AgentScheduler`** (new) — the first observer for `.schedule` triggers:
  RootView ticks it once a minute; due agents start; a schedule missed while
  the app was closed fires on the next tick after launch.
- **`ScheduleAgentView`** (new) — UI for creating schedule triggers.
- **`AgentDetailView`** — live activity sidebar (thermal state, memory via
  new `SystemStats`), run timeline, permissions toggles.
- **`PendingApproval`** gained `draftBody` (the editable outgoing content)
  and related plumbing through `ApprovalCard`/`AgentRepository`/view models.

## 6. Docs & hygiene

- **Root `README.md` rewritten** to match reality: what the app does, an
  accurate architecture diagram, full setup (Composio → harness → Xcode),
  config reference, LM Studio ↔ Cerebras trade-offs. The old "keep the agent
  engine in Swift, Python is just a Composio wrapper" plan it described was
  overtaken by the harness actually becoming the engine.
- **`agent-harness/.env.example`** added; `.env` remains gitignored. No API
  keys, tool-router session IDs, or user IDs are committed on this branch
  (verified by scan before each commit).
- `DevSeed`/`PreviewData` expanded so previews exercise the new Today view.

## Known gaps carried forward

- Approval gating for harness tool calls (needs a loop interrupt point).
- One hung source still holds a briefing to the full 240s tool timeout —
  a shorter per-caller timeout for briefing runs is the next planned fix.
- `Orchestrator` sub-agent chaining and `InferenceService` on-device
  inference remain stubs.
- Chat sessions live in server memory; nothing survives a server restart.
