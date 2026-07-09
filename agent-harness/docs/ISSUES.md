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

- [ ] **Adopt the policy this implies for the agent loop (once it's
      built):** never call `stream()` for a turn where tools are
      available to the model. Use `complete()` (non-streaming) for any
      turn where a tool call is possible; reserve `stream()` for
      tool-free turns (e.g. a final natural-language answer after all
      tool calls are already resolved, or a no-tools chat). The raise
      above is the safety net if this policy is ever violated by mistake.
      **Still open** — there's no agent loop yet (`main.py` is a stub) to
      apply this policy to; revisit when the loop is built.

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
