# AgentHub

SwiftUI · MVVM · shared Swift package across macOS + iOS · SwiftData + CloudKit sync.

The **Mac is the executor** (local LLM inference + local tools + the Composio API
key). The **iPhone is a monitor + remote control** — it never runs agents and
never holds secrets; it enqueues `AgentIntent`s that the Mac applies.

Third-party SaaS access (Gmail, Slack, Notion, GitHub) goes through **Composio**,
which owns the OAuth tokens. Local capabilities (files, calendar, git, web) run
on the Mac as first-party tools.

## Layout

```
AgentHub/
├─ Packages/AgentKit/     # shared: Models, ViewModels, Store, Intents (both apps)
├─ AgentHubMac/           # executor: Views, Services (Inference/Runner/Composio/Tools), Connections
├─ AgentHubMobile/        # companion: read-only Views, Widget, Notifications
└─ AgentHubTests/         # app-target tests (AgentKit tests live in the package)
```

## What Composio changed vs. self-hosted OAuth

- **Deleted** the old `OAuth/` folder (`OAuthCoordinator`, `ProviderConfig`,
  `TokenStore`). Composio holds tokens and runs refresh.
- **Kept** one small survivor: `Connections/ConnectionCoordinator.swift` just
  opens Composio's connect URL in `ASWebAuthenticationSession`.
- **Split** `Services/Tools/`: SaaS tools (mail) delegate to `ComposioClient`;
  local tools (calendar/files/git/web) run on the Mac.
- **Added** `Services/Composio/` and a synced `ConnectedAccount` model so the
  iPhone can show "Gmail connected ✓" without ever holding the key.

## Xcode setup (this scaffold is source-only)

This generates the folders and Swift files. You still create the Xcode
workspace + targets, because `.xcworkspace`/`.xcodeproj` can't be hand-authored
reliably:

1. **New Workspace** → `AgentHub.xcworkspace` at this folder.
2. **Add the local package**: drag `Packages/AgentKit` into the workspace.
3. **Create two app targets**: a macOS app (`AgentHubMac`) and an iOS app
   (`AgentHubMobile`); point each at its source folder here.
4. **Link `AgentKit`** to both targets (General → Frameworks & Libraries).
5. **Add MCP SDK** to the Mac target if you wire `ComposioClient` over MCP
   (the same `swift-sdk` you already use in Promethius).
6. **Entitlements**: enable iCloud → CloudKit with the **same container id** on
   both targets, plus an App Group if the widget reads the store.
7. **Composio key**: store it in the Mac Keychain; never bundle it, never ship
   it in the iOS target.
8. **iOS widget**: add a Widget Extension target and move
   `AgentHubMobile/Widgets/AgentStatusWidget.swift` into it.

## CloudKit lag is designed-for, not assumed-away

Sync can trail by seconds to minutes and can duplicate/redeliver. The intent
pipeline handles this end-to-end:

- Producer (iPhone) **de-duplicates**: a second identical, un-applied command
  reuses the first (`IntentQueue.enqueue` → `pendingIntent`).
- UI shows an optimistic **"Requested…"** state (`isRequestInFlight`) so a
  lagging button isn't tapped repeatedly.
- Consumer (Mac) stamps `appliedAt` and **ignores** already-applied commands.
- Prefer a **CloudKit push** (silent notification) to wake the Mac/phone
  promptly rather than waiting on periodic sync.

Run the package tests that cover this:

```
cd Packages/AgentKit && swift test
```
