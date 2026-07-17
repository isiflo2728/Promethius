# Promethius — AgentHub (Composio version)

A macOS + iOS app for building and running autonomous AI agents, built with
SwiftUI, SwiftData, and CloudKit, backed by a hand-rolled Python agent
harness that connects to your real accounts (Gmail, GitHub, Calendar,
Discord, …) through [Composio](https://composio.dev).

## What it does

- **Today view** — the home tab. An agent-built **"On your plate"** briefing
  distills everything across your connected accounts into the handful of
  things that actually need you (one small agent runs per source, in
  parallel, and the results are merged and ranked). An **ask-anything bar**
  streams free-form questions through the same agent loop with live status
  ("Running GMAIL_FETCH_EMAILS…"), and **"What's next"** shows your real
  calendar (EventKit).
- **Agents** — create agents with a prompt, model, tools, and triggers
  (manual, schedule, Composio event, file change). A scheduler fires due
  agents while the app is open; runs stream into a persisted, watchable
  timeline.
- **Human-in-the-loop approvals** — actions like sending email pause on a
  `PendingApproval` with an editable draft before anything goes out.
- **iPhone companion** (scaffold) — read-only monitoring + approvals via
  CloudKit sync; the phone never runs agents and never holds secrets.

## Architecture at a glance

```
iPhone (companion) ── CloudKit ── Mac app (SwiftUI, the executor)
                                        │ HTTP localhost:8000
                                  agent-harness (Python/FastAPI)
                                  ReAct loop · /chat SSE · /briefing
                                   │                    │
                     OpenAI-compatible LLM        Composio MCP tool router
                     (LM Studio local or          (Gmail, GitHub, Calendar,
                      Cerebras cloud)              Discord, … via OAuth)
```

- **`agent-harness/`** — the brain. A hand-rolled ReAct loop (no LangChain),
  an OpenAI-compatible provider layer (swap LM Studio ↔ Cerebras with env
  vars only), and an MCP client that talks to Composio's hosted tool router.
  Composio owns all OAuth tokens; this repo never sees them.
- **`AgentHub/`** — the product. `AgentHubMac` (executor app),
  `AgentHubMobile` (companion scaffold), and `Packages/AgentKit` (shared
  models, view models, store, harness client).
- **`Promethius/`** — the original prototype, superseded by `AgentHub/`.

More architecture detail lives in [`agent-harness/docs/`](agent-harness/docs/).

## Setup

### 0. Requirements

- macOS 27+, Xcode (latest)
- [uv](https://docs.astral.sh/uv/) for the Python side
- A [Composio](https://app.composio.dev) account (free tier works)
- An inference engine: [LM Studio](https://lmstudio.ai) locally, **or** a
  [Cerebras](https://cloud.cerebras.ai) API key for fast cloud inference

### 1. Composio (the tool layer)

1. Create an account at [app.composio.dev](https://app.composio.dev) and get
   an **API key** (Settings → API Keys).
2. Create a **Tool Router session** for a user id of your choosing — this
   yields an MCP URL like
   `https://backend.composio.dev/tool_router/trs_XXXX/mcp`.
3. **Connect apps** (Gmail, GitHub, Google Calendar, Discord, …) for that
   same user. Connected apps are discovered automatically and appear in the
   briefing — no config change needed when you add one later.

### 2. The agent harness (Python backend)

```bash
cd agent-harness
uv sync                      # install deps into a managed venv
cp .env.example .env         # then fill in your keys — see the file's comments
uv run uvicorn server:app    # serves http://localhost:8000
```

`.env` chooses your inference engine — the code never changes:

- **LM Studio (local, private):** install it, download a tool-calling GGUF
  model (e.g. `openai/gpt-oss-20b`), and load it with a large context window
  (32k recommended — a single Composio tool result can be ~5k tokens). Full
  model-setup detail: [`agent-harness/docs/README.md`](agent-harness/docs/README.md).
- **Cerebras (cloud, fast):** paste an API key and use `gpt-oss-120b`.
  Much faster and more reliable JSON, but tool results (email bodies) leave
  your machine, and the free tier's rate limits are tight for agent loops —
  the pay-as-you-go tier costs cents per day at personal usage.

Smoke-test it:

```bash
curl -X POST http://localhost:8000/briefing        # structured to-do JSON
```

### 3. The Mac app

```bash
open AgentHub/AgentHubMac/AgentHubMac/AgentHubMac.xcodeproj
```

Select the `AgentHubMac` scheme, a macOS destination, and run (`Cmd + R`).
The app expects the harness on `localhost:8000`; the Today view's briefing
and chat light up once the server is running.

### Configuration reference (`agent-harness/.env`)

| Variable | Purpose |
|---|---|
| `COMPOSIO_API_KEY` / `COMPOSIO_MCP_URL` | Composio auth + the tool-router MCP session. Without both, the server runs toolless. |
| `COMPOSIO_USER_ID` | Which Composio user's connections count for briefing source discovery |
| `LLM_BASE_URL` / `LLM_API_KEY` / `AGENT_MODEL` | Any OpenAI-compatible engine + model |
| `BRIEFING_SOURCES` / `BRIEFING_EXCLUDE` | Baseline plate sources / connected apps to skip (optional) |

**Never commit `.env`** — it's gitignored; `.env.example` is the safe
template.

## Running tests

In Xcode press `Cmd + U`, or:

```bash
xcodebuild test -project AgentHub/AgentHubMac/AgentHubMac/AgentHubMac.xcodeproj \
  -scheme AgentHubMac -destination 'platform=macOS'
```

The Python side has no test suite yet.

---

## 🎯 North Star — the goal

**Build an app that feels genuinely, obsessively crafted — like a top-tier native Apple app, not an AI-generated shell.**

Every screen, every transition, every pixel of spacing should feel considered. When someone uses Promethius, it should feel *amazing and smooth* — the kind of app you keep open just because it's pleasant to touch. We are not shipping "good enough." We are shipping **polished**.

### Design non-negotiables

- **Feels native, not "AI-made."** Minimal generic AI-slop elements — no default-looking gradients-on-everything, no stock chatbot bubbles, no cookie-cutter card grids. It should look like Apple could have shipped it. Every component earns its place.
- **Obsess over every detail.** Spacing follows a consistent rhythm (4/8/12/16pt). Typography uses the system type scale with intent. Alignment is exact. Nothing is "roughly centered."
- **Motion is smooth and purposeful.** Spring animations, not linear fades. Every state change is animated with intent — appearing, selecting, loading, completing. Target buttery **ProMotion (120fps)** smoothness; no jank, no dropped frames on scroll.
- **Native materials & depth.** Use system materials (`.regularMaterial`, `.ultraThinMaterial`), vibrancy, and proper light/dark adaptation. Respect the platform (sidebar behavior, toolbar conventions, hover states on Mac).
- **SF Symbols, done right.** Consistent weights and rendering modes. Symbols animate (`.symbolEffect`) where it adds delight, not everywhere.
- **Restraint.** Fewer, better elements. Whitespace is a feature. If a screen feels busy, remove something.
- **Feedback everywhere.** Every tap has a response — press states, subtle haptics/sound where fitting, clear loading and empty states. The app never feels dead.
- **Accessible by default.** Full VoiceOver labels, Dynamic Type, Reduce Motion honored, sufficient contrast. Polish includes everyone.

> Rule of thumb: if a change makes the app feel even 5% smoother or more intentional, it's worth doing. Sweat the details relentlessly.

---

## Branching model

Company-style flow. **Never commit straight to `main`.** Full guide: [`docs/BRANCHING.md`](docs/BRANCHING.md).

```
feature/*  →  develop  →  staging  →  main
 your work    testing     pre-prod    PRODUCTION
```

| Branch | Role | Protected |
|--------|------|-----------|
| `main` | Production. Only proven, released code. | ✅ |
| `staging` | Final pre-prod mirror before a release. | ✅ |
| `develop` | Integration/testing. Default branch; features land here. | — |
| `feature/*` | Day-to-day work. One branch per feature/fix. | — |

Protected branches require a Pull Request (you can self-merge); no direct or force pushes.

## More docs

- [`agent-harness/docs/README.md`](agent-harness/docs/README.md) — harness setup detail + build order
- [`agent-harness/docs/ISSUES.md`](agent-harness/docs/ISSUES.md) — running log of real bugs and diagnoses
- [`agent-harness/docs/Understanding/`](agent-harness/docs/Understanding/) — deep dives (MCP protocol, SSE, LM Studio switch, …)
- [`AgentHub/README.md`](AgentHub/README.md) — app layout and Xcode workspace setup
