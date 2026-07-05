# Promethius

A macOS app built with SwiftUI.

## Requirements

- macOS 27.0 or later
- Xcode (latest version recommended)

## Getting Started

1. Clone the repository
   ```bash
   git clone https://github.com/isiflo2728/Promethius.git
   ```
2. Open the project in Xcode
   ```bash
   cd Promethius
   open Promethius.xcodeproj
   ```
3. In Xcode, select the `Promethius` scheme and a macOS run destination.
4. Build and run with `Cmd + R`.

## Running Tests

In Xcode, press `Cmd + U`, or run from the command line:
```bash
xcodebuild test -project Promethius.xcodeproj -scheme Promethius -destination 'platform=macOS'
```

---

# AgentHub — Building with Python (for the backend/Composio work)

The `AgentHub/` folder holds a multiplatform Swift app (macOS + iOS, SwiftData +
CloudKit). The app is Swift, but there's **one clean place for Python**: the
Composio / remote-tools service. This section is for whoever's building that part.
Full architecture notes are in [`AgentHub/README.md`](AgentHub/README.md).

## What SHOULD be Python — the Composio service

Composio's first-class SDK is Python (there is no official Swift SDK). So the job
for Python is a small **FastAPI service that owns the Composio API key** and wraps
its SDK. The Swift app stops calling Composio directly and calls this service.

```
┌─────────────┐   HTTP    ┌──────────────────┐   Composio SDK   ┌──────────┐
│ Mac app     │ ────────► │ Python (FastAPI) │ ───────────────► │ Composio │ ──► Gmail/Slack/…
│ Swift       │ ◄──────── │ owns COMPOSIO_KEY│                  └──────────┘
└─────────────┘   JSON    └──────────────────┘
```

Endpoints to build (the whole surface):

- `POST /connections` — start an OAuth connect flow, return Composio's connect URL
- `GET  /connections/{provider}/status` — has the user finished connecting?
- `POST /actions/execute` — run an action (e.g. `GMAIL_CREATE_EMAIL_DRAFT`) with `{slug, connection_id, arguments}`
- `GET  /tools?provider=gmail` — list real action slugs

The Swift side barely changes: `ComposioClient` keeps its signature and just points
its base URL at this service (e.g. `http://localhost:8000`) instead of Composio.

**Boundaries the Python side must respect:**
- Python **executes** actions; it does **not** decide policy. The "sending email needs
  approval" guardrail stays in Swift, tied to the cross-device CloudKit flow.
- The Composio API key lives **only** in the Python service — never in the app, never
  on the iPhone.

## What can NOT easily move to Python

- **Device-to-device sync** (agents, approvals, intents) is **CloudKit**, driven by the
  apps. Replacing it means building your own server + DB + auth — out of scope.
- **Local tools** — files, calendar, git — touch the user's Mac, so they run in the Mac
  app, not a remote service.
- **On-device inference** runs on the Mac; a cloud service can't reach it.

## Where should the Python service run? (the real trade-off)

| | **Local sidecar** (`localhost`) | **Cloud** (Fly.io / Railway / Render) |
|---|---|---|
| Composio key | on the user's Mac | one key, on your server |
| Multi-user | one user | needs per-user Composio entities + app↔service auth |
| Distribution | ship/launch a Python runtime with the Mac app (fiddly) | app just needs a URL |
| Best for | personal use, development | a real multi-user product |

**Recommended path:** start as a **local sidecar** — run `uvicorn` on `localhost:8000`,
point the Mac app at it, and get **one Gmail draft working end-to-end**. If it later
becomes multi-user, lift the same FastAPI app to the cloud and add an auth token the app
sends. The code barely changes — only *where it runs* and *how the app authenticates*.

## Could Python do the whole agent engine too?

Possible, but it changes the app's premise. The Mac is the executor **because** local
tools + on-device inference only work there. Move the loop to **cloud** Python and you
lose that rationale (it becomes a different, cloud-agent app). Run it **locally** on the
Mac and it works but you pay the "ship a Python runtime with a Mac app" cost. For now,
keep the engine in Swift and let Python own **just the Composio service** — highest value,
lowest friction.

See issue **#4 (Composio integration)** for the concrete first task.
