# Known Issues / Planned Fixes

Tracked implementation work that's been discussed and decided on, but not
yet applied to the code. Check items off here as they land.

## `providers/local.py` — `stream()` bugs

Background/full rationale: `docs/Understanding/streaming_chat_completions.md`.
Safety checkpoint of the pre-fix state: commit `b1cd074`
("Checkpoint agent-harness scaffold before streaming fixes").

**Decision: go with Option A** (policy fix, no interface redesign) — see
below for what Option B would have looked like, kept here in case
streaming-while-tools-are-in-play becomes a real requirement later.

- [x] **Fix crash risk: empty `choices` list.** `chunk.choices[0]` is
      indexed unconditionally. The SDK's own docs say `choices` can be
      empty (e.g. the trailing usage-only chunk when
      `stream_options={"include_usage": True}` is set, or provider/proxy
      metadata chunks) — this throws `IndexError` the moment it happens.
      Fix: `if not chunk.choices: continue` before indexing. **Done** —
      guard added in `providers/local.py`'s `stream()`.

- [x] **Fix silent tool-call loss.** `stream()` only reads
      `delta.content`. When the model calls a tool mid-stream, the request
      arrives via `delta.tool_calls` instead, which is never read — the
      method just yields nothing and finishes normally, with no signal
      anything happened. Fix (Option A): raise a clear
      `NotImplementedError` the moment `delta.tool_calls` is seen,
      instructing the caller to use `complete()` instead. This is a guard
      rail, not full support — see the policy decision below. **Done** —
      `stream()` now raises `NotImplementedError` on `delta.tool_calls`.

- [x] **Adopt the policy this implies for the agent loop (once it's
      built):** never call `stream()` for a turn where tools are
      available to the model. Use `complete()` (non-streaming) for any
      turn where a tool call is possible; reserve `stream()` for
      tool-free turns (e.g. a final natural-language answer after all
      tool calls are already resolved, or a no-tools chat). The raise
      above is the safety net if this policy is ever violated by mistake.
      **Done** — `core/loop.py` exists now and only ever calls
      `provider.complete()`; nothing in the codebase calls `stream()` at
      all yet, so the policy holds by construction. Revisit if a
      streaming-final-answer feature is ever added on top.

### Option B (not chosen now — revisit only if a real need shows up)

Full fix: widen `BaseProvider.stream()`'s return type from
`AsyncIterator[str]` to a small tagged union (e.g.
`AsyncIterator[TextDelta | ToolCallEvent]`), and in `local.py` accumulate
`delta.tool_calls[i]` fragments by `.index` across chunks into a complete
`ToolCall` once `finish_reason == "tool_calls"`. This lets streaming work
even on turns where the model ends up calling a tool (e.g. for a UI that
needs to show "calling get_weather..." live). Not implemented because
nothing in the codebase calls `stream()` yet (`main.py` is still a stub) —
revisit once an actual caller needs live token output during a
tool-enabled turn.

## Testing against a real Composio MCP server — remaining gaps

Found while reviewing `mcp_client/client.py` and scoping out what an actual
end-to-end test (this harness ↔ a live Composio MCP server) would need.
Nothing here is started yet.

- [x] **1. `MCPClient` had no transport for remote MCP servers.**
      `connect()` only called `stdio_client` — it spawns a local subprocess
      and talks to it over stdin/stdout. Composio's *tool execution* is
      always backend-hosted (no self-hosted/on-prem deployment found in
      their docs), and reaching it from a plain `mcp` SDK client like this
      one means a remote HTTPS endpoint
      (`https://backend.composio.dev/v3/mcp/{server_id}?user_id={user_id}`),
      authenticated via an `x-api-key` header, speaking streamable-HTTP —
      not stdio.

      *Caveat:* Composio does offer a genuinely local option, but only
      through Anthropic's Claude Agent SDK — `create_sdk_mcp_server()`
      wraps their fetched tools into an MCP server object that lives
      in-process (no subprocess, no MCP-layer network hop). That's a
      different SDK's tool-calling mechanism, not the generic
      `mcp.ClientSession`/`stdio_client` this project is built on, and the
      tool *execution* underneath still calls Composio's cloud regardless
      — so it doesn't change what this project needs.

      **Done** — split `connect()` into `connect_stdio()` (the old
      behavior, renamed) and `connect_http(name, url, headers)` (new, uses
      `mcp.client.streamable_http.streamablehttp_client()`). Both are thin
      wrappers that build a transport-specific `(read_stream, write_stream)`
      pair and hand off to a shared `_register()` for the session handshake
      + tool-list bookkeeping, so that logic isn't duplicated per
      transport. A third transport (SSE, websocket) later is one more thin
      `connect_*()` wrapper, not a change to `_register()`.

      > **ELI5:** Right now `MCPClient` only knew how to talk to a tool
      > that lives *on the same computer* — it starts up the tool itself,
      > like launching a program from a shortcut on your desktop, then
      > chats with it through a pipe between the two programs. Composio's
      > tools don't live on your computer at all — they live on Composio's
      > servers, out on the internet. Talking to them is more like making
      > a phone call to a business than starting a program on your own
      > machine: you need their phone number (the URL) and you have to say
      > a password when they pick up (the `x-api-key` header) before
      > they'll do anything for you. `MCPClient` used to only know how to
      > "launch a local program" — now it also knows how to "make a phone
      > call," and both share the same "once someone picks up, have the
      > same conversation" logic underneath.

- [x] **2. Composio-side setup isn't something code can do.** Need a
      Composio account, an API key, and an actual MCP server instance
      provisioned for whichever toolkit (Gmail, etc.) is being tested —
      that's what supplies the real `server_id`/`user_id` for the URL
      above.

      **Done, with a wrinkle found along the way:** the Composio dashboard
      has no "create session" button — its Sessions page literally says
      "Start using the SDK to see sessions here." A session (and the MCP
      URL that comes with it) only exists once created in code via
      `composio.create(user_id=...)`. Worked around with a one-off script
      (not part of this repo, run via `uv run --with composio`) that calls
      that once and prints `session.mcp.url` / `session.mcp.headers`. The
      real URL shape turned out to be
      `https://backend.composio.dev/tool_router/{session_id}/mcp` — no
      `?user_id=` query param, different from what the docs snippets
      implied — and the headers were exactly `{"x-api-key": <key>}`,
      matching what `connect_http()` already assumed.

- [x] **3. No env/secret handling exists yet.** Nothing in this repo reads
      `.env` or has a `config.py` (still a north-star item in
      `docs/AGENT_ARCHITECTURE.md`). At minimum, `COMPOSIO_API_KEY` needs
      to be read from `os.environ` before it reaches `connect_http`'s
      headers. Naming precedent already exists in the sibling
      `../composio-service/` project (a separate integration, using
      Composio's own SDK rather than raw MCP).

      **Done** — added `python-dotenv` as a real dependency, `.env` added
      to `.gitignore` (never commit it), and `main.py` calls `load_dotenv()`
      before reading `COMPOSIO_API_KEY`/`COMPOSIO_MCP_URL`/`AGENT_MODEL`
      from `os.environ`. No `config.py` yet — still not needed for this
      scope.

- [x] **4. There is no loop to run any of this through.** `core/loop.py`
      is currently just `# hello`. `archive/agent.py` can't be reused
      either — it predates `providers/local.py` and `mcp_client/client.py`,
      uses a synchronous `OpenAI` client directly, and never touches
      `BaseProvider` or `MCPClient`. `LocalProvider` and `MCPClient` are
      both `async` and already working; the loop needs to be written
      fresh against them, per `docs/AGENT_ARCHITECTURE.md`'s design
      (`provider.complete()` → dispatch tool calls via `mcp.call()` →
      `provider.format_tool_result()` → repeat).

      **Done** — `core/loop.py` implemented, grounded against two real
      references rather than written from memory: LangGraph's own
      `react-agent` template (confirms the modern tool-calling-API loop
      shape — call model, route on `tool_calls` presence, execute, loop
      back) and `marcosf63/react-agent-framework`'s docs (confirms the
      underlying Thought/Action/Observation framing). Diverges from
      `AGENT_ARCHITECTURE.md`'s pseudocode in two places where the real
      code differs from the sketch: `format_tool_result()` takes 2 args,
      not 3, and dispatch goes through this project's own `MCPClient`
      (already flattens results to strings), not a raw `ClientSession`.
      Building this surfaced two real, separate bugs that would have
      silently broken the first tool-calling turn — both fixed:
        - `providers/local.py`'s `_format_messages()` had no handling for
          `Message.content` being a `list[ToolCall]` (the
          assistant-requests-a-tool-call case) — fixed to build the
          `tool_calls` array the wire format actually needs.
        - `providers/local.py` imported `override` from `typing`, which
          doesn't exist there until Python 3.12 — this project pins 3.11.
          The module couldn't be imported at all before this fix. Switched
          to the `typing_extensions` backport, added as an explicit
          dependency.

- [x] **5. `main.py` is still `raise NotImplementedError`.** Its TODO
      comments describe a plain synchronous `input()`/`print()` loop,
      which is stale now that everything downstream is `async`. Needs
      `asyncio.run(...)`, plus `await mcp.disconnect_all()` on exit/Ctrl+C
      so the Composio session and any local subprocesses get torn down
      cleanly.

      **Done** — implemented and verified live: connects to configured MCP
      servers via env vars (currently just Composio; more `if
      os.environ.get(...)` blocks would follow the same pattern), runs
      fine with zero tools configured if Composio's env vars aren't set,
      and `finally: await mcp.disconnect_all()` covers normal exit,
      `exit`/Ctrl+D, and Ctrl+C alike. Confirmed against the real,
      live Composio session from item 2 — connected and listed the real
      6 available tools, not a mock.

- [x] **6. Environment prerequisite, not code:** confirm Ollama is running
      a model that actually supports tool calls (`ollama show <model>`,
      look for "tools" under Capabilities) before debugging anything else
      — a model that silently doesn't support tool calls looks identical
      to a broken loop from the outside.

      **Done** — Ollama confirmed running (v0.31.1). `qwen3:14b`
      (~9.3GB, fits comfortably in 24GB unified memory on the test
      machine) pulled and confirmed via `ollama show qwen3:14b`:
      `tools` (and `thinking`) both listed under Capabilities.

- [ ] **7. The model reliably makes a real tool call on turn 1, then
      reliably stops acting on turn 2.** Observed twice in a row, same
      shape both times: turn 1 correctly calls `COMPOSIO_SEARCH_TOOLS`
      with sensible arguments and gets back real tool schemas + an
      execution plan. Turn 2, instead of calling
      `COMPOSIO_MULTI_EXECUTE_TOOL` to actually complete the task, the
      model just **describes** what it received instead of acting on it:
        - Test 1 (`"what tools do you have"` — a vague meta-question):
          the model latched onto an *example value* inside
          `SEAT_GEEK_SEARCH_EVENTS`'s own schema (`"examples":["Taylor
          Swift", ...]`) and wrote out fake, JSON-shaped call parameters
          as plain text, with a garbled `session_id` (`"year"` — the real
          one Composio returned was `"push"`).
        - Test 2 (`"access my google drive. what is the most recent
          file."` — a concrete, real task): the model wrote a full
          API-documentation-style writeup summarizing the Google Drive
          tool schemas it received, instead of calling
          `GOOGLEDRIVE_LIST_FILES`.

      In both cases `response.tool_calls` was empty on turn 2, so
      `core/loop.py` correctly treated the text as the final answer —
      this is a model *behavior* gap, not a loop bug; the dispatch/format
      mechanics worked correctly both times on turn 1.

      **Suspected cause:** the system prompt (`main.py`'s `SYSTEM_PROMPT`)
      is too passive — *"You are a helpful assistant with access to
      tools. Use them when they help answer the user's request"* — and
      doesn't say anything about *continuing* to act once a tool result
      comes back. Once the model has "used a tool" once (the search), it
      seems to treat that as task-complete and switches into
      explain-what-I-found mode, especially with a wall of dense JSON
      sitting in context that reads like something to summarize for a
      human rather than data to act on.

      **Proposed fix, not yet applied — now backed by real evidence, not a
      guess.** Checked how Hermes Agent (NousResearch) handles this exact
      class of failure — full writeup in
      `docs/research/learning_agent_architecture.md`'s new "Part 0". Short
      version: Hermes ships a `TOOL_USE_ENFORCEMENT_GUIDANCE` system-prompt
      block gated to specific model families
      (`TOOL_USE_ENFORCEMENT_MODELS = ("gpt", "codex", "gemini", "gemma",
      "grok", "glm", "qwen", "deepseek")`) — **`"qwen"` is on that list**,
      matched by plain substring against the model name, so `qwen3:14b`
      would trigger it under Hermes's own logic. This is production
      evidence, not speculation: a real system, tested across real users
      and many model families, specifically flags Qwen as needing this
      exact steering. Plan: adapt Hermes's actual guidance text (quoted in
      the research notes) into `main.py`'s `SYSTEM_PROMPT`, then re-run the
      same Google Drive test to confirm it changes turn 2's behavior. If it
      doesn't fully fix it, `TASK_COMPLETION_GUIDANCE` (Hermes's second,
      universal block, also quoted there) targets the closely related
      "stops after a stub" failure and is worth adding too.

### What Composio's "6 tools" actually turned out to be

Worth recording since it changes what a real test looks like: the 6 tools
`main.py` lists aren't individual app actions (no "send an email" tool
directly) — they're Composio's meta-tool router:
`COMPOSIO_SEARCH_TOOLS` (discover relevant tools across 500+ apps),
`COMPOSIO_GET_TOOL_SCHEMAS`, `COMPOSIO_MANAGE_CONNECTIONS` (check/create
OAuth for a toolkit), `COMPOSIO_MULTI_EXECUTE_TOOL` (actually run
discovered tools), plus `COMPOSIO_REMOTE_BASH_TOOL`/`COMPOSIO_REMOTE_WORKBENCH`
for sandboxed bulk processing. A real test needs the model to chain
through search → (maybe) connect → execute across multiple turns, not
just call one tool directly. This also explains why Composio's own
Sessions/Users dashboard pages stayed empty after our connection test —
we only called MCP's `list_tools()` (protocol-level discovery), never one
of the 6 meta-tools themselves, and Composio's dashboard specifically
tracks "tool calls," not raw MCP listing.

Not required for a Composio-only test, called out so it's a deliberate
choice rather than a default: `tool.py`'s `Tool.to_schema()` and
`tools/example_tools.py` are still stubs. `core/loop.py` was in fact built
MCP-only (dispatch goes entirely through `MCPClient`, no local
`dict[str, Tool]` path) — that decision is now enacted, not just
theoretical. Revisit only if a real need for local, in-process tools
alongside MCP ones shows up.
