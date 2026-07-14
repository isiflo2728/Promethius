# Turning the Loop's `print()`s Into Events a Frontend Can Consume

A discussion thread about how to get `core/loop.py`'s output in front of a
native macOS/SwiftUI app, without losing the terminal output `main.py`
already has. Nothing here is implemented yet — `core/loop.py` still prints
directly, exactly as shown below. This documents the design that was
worked out, for whenever it's built.

---

## Q1: What does the loop actually output today?

Straight from the current `core/loop.py`:

```python
for turn in range(max_turns):
    print(f"\n[turn {turn + 1}]")                          # loop.py:67
    response = await provider.complete(...)
    if not response.tool_calls:
        return response.content                             # loop.py:78
    if response.content:
        print(f"Thinking: {response.content}")              # loop.py:81
    for tc in response.tool_calls:
        print(f"-> calling: {tc.name}({tc.arguments})")      # loop.py:92
        result = await mcp.call(tc.name, tc.arguments)
        print(f"<- result: {result[:200]}")                  # loop.py:104
```

Every `print()` here writes straight to *this process's* stdout. That's
fine when the only consumer is `main.py`'s terminal loop reading its own
process's output. It breaks the moment a second consumer shows up — a
SwiftUI app is a **separate process**, possibly talking over HTTP from a
different machine entirely. It has no way to read another process's
stdout. It needs the same information delivered as data it can parse.

## Q2: What's an "event," concretely?

A small piece of data describing one thing that happened — e.g.

```python
{"type": "tool_call", "name": "read_file", "arguments": {"path": "x.txt"}}
```

It's the exact same information already in each `print(f"...")` call
above, just packaged as a dict instead of baked into a formatted sentence.
A `print()` call *is* text, aimed at exactly one destination (the
terminal). An event is *data*, aimed at nothing in particular — whoever
receives it decides what to do with it: print it, forward it over a
network connection, both.

## Q3: What does `yield` have to do with this?

`yield` turns a function into a generator: instead of computing one value
and `return`ing it once, the function pauses at each `yield`, hands a value
to whoever's iterating over it, and resumes right where it left off next
time a value is requested. Nothing runs until something asks for the next
value via `async for`.

Applied here: instead of `run()` calling `print()` seven times and then
`return`ing one final string, `run()` would `yield` each of those seven
moments as a dict, pausing after each one. Whoever calls `run()` does
`async for event in run(...):` and gets each dict as it happens — deciding
for themselves whether to print it, ship it over SSE, or both. That's the
whole mechanism: `print()` can only ever have one destination; `yield`ing a
dict can have as many destinations as there are consumers reading it.

## Q4: Why wasn't this the design from the start?

Because the loop only ever had one consumer: `main.py`'s terminal chat
loop. `print()` is the right tool when there's exactly one place output
needs to go — building an event/generator layer before a second consumer
existed would have been exactly the kind of premature abstraction
`CLAUDE.md` warns against ("don't build memory/skills/delegation until
there's a concrete need for them" — same principle applies here). The
concrete need only exists now that a SwiftUI app needs the same
information over a channel that isn't stdout.

## Q5: Worked example — what would actually travel over the wire?

User asks "What's the weather in Paris?", the model has a `get_weather`
tool available.

**What `run()` would yield, in order** (built from data already sitting in
`core/loop.py`'s variables — `turn`, `response.content`, `tc.id`/`tc.name`/
`tc.arguments` from `ToolCall` in `providers/base.py:20`, and `result` from
`mcp.call()`):

```python
{"type": "turn_start", "turn": 1}
{"type": "status", "state": "thinking"}
{"type": "tool_call", "id": "call_abc123", "name": "get_weather", "arguments": {"city": "Paris"}}
{"type": "tool_result", "tool_call_id": "call_abc123", "name": "get_weather", "result": "62°F, cloudy"}
{"type": "turn_start", "turn": 2}
{"type": "status", "state": "thinking"}
{"type": "final", "text": "It's 62°F and cloudy in Paris right now."}
```

Seven dicts. A "turn" here means one full trip through the loop's
`for turn in range(max_turns)` — one `provider.complete()` call, plus
dispatching every tool it requested that call. Not one turn per tool call.
`status: thinking` exists because there's a real gap — while
`provider.complete()` is awaited, nothing observable has happened yet, and
a consumer needs *some* signal that the loop hasn't stalled.

**What a FastAPI consumer does with each dict:** nothing interpretive — it
just serializes each one to JSON and writes it as one SSE frame
(`data: <payload>\n\n`, blank line terminates the frame; this is the wire
format `text/event-stream` requires):

```
data: {"type": "turn_start", "turn": 1}

data: {"type": "status", "state": "thinking"}

data: {"type": "tool_call", "id": "call_abc123", "name": "get_weather", "arguments": {"city": "Paris"}}

data: {"type": "tool_result", "tool_call_id": "call_abc123", "name": "get_weather", "result": "62°F, cloudy"}

data: {"type": "turn_start", "turn": 2}

data: {"type": "status", "state": "thinking"}

data: {"type": "final", "text": "It's 62°F and cloudy in Paris right now."}

```

That text is literally what goes out over the socket, one frame at a time
as `run()` yields each dict — not all at once at the end.

**What Swift does with it:** `URLSession`'s byte stream hands the same raw
text over, line by line. The Swift side buffers until a `data: ` line,
strips the prefix, `JSONDecoder().decode()`s it into a Swift type, and
`switch`es on `type` to update UI state:

- `turn_start` / `status: thinking` → show a spinner/typing indicator
- `tool_call` → show a "calling get_weather..." chip
- `tool_result` → replace that chip with a checkmark or the result
- `final` → append a chat bubble, stop the spinner

JSON is the only contract between the two languages here — no shared
library, no shared types, just field names both sides agree on.

## Q6: Why not stream token-by-token instead (like Claude/Gemini's "thinking")?

Considered and deliberately deferred — see
`docs/Understanding/streaming_chat_completions.md` and `docs/ISSUES.md`'s
"Option B." `providers/local.py`'s `stream()`
actively raises `NotImplementedError` the moment the model tries to call a
tool mid-stream; it was never built to handle that case. Making real
token-level streaming work *while tools are in play* means accumulating
`delta.tool_calls[i]` fragments by `.index` across many chunks before
they're valid JSON — genuinely more work than turning existing `print()`
call sites into `yield`ed dicts. The event-per-step design above is
event-level streaming (progress), not token-level streaming (text
appearing word by word); it's the smaller, already-compatible step, not a
replacement for token streaming if that's wanted later.

## Q7: How does a Swift client actually consume this?

Both processes run on the same Mac, so this is plain local HTTP — no
special format beyond what's described above. `server.py` binds to
`127.0.0.1:8000` by default (`uv run uvicorn server:app --reload`); no CORS
setup is needed since CORS is a browser-only restriction, not something
`URLSession` enforces.

The one non-obvious part: `POST /chat`'s response body arrives in pieces
over time, not all at once, so it needs `URLSession.bytes(for:)` (an
`AsyncSequence`) rather than a normal `data(for:)` call that waits for the
whole response:

```swift
var request = URLRequest(url: URL(string: "http://localhost:8000/chat")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try JSONEncoder().encode(["session_id": "conv-1", "message": "hello"])

let (bytes, _) = try await URLSession.shared.bytes(for: request)

for try await line in bytes.lines {
    guard line.hasPrefix("data: ") else { continue }   // SSE frames look like "data: {...}"
    let json = line.dropFirst("data: ".count)
    let event = try JSONDecoder().decode(LoopEvent.self, from: Data(json.utf8))
    // switch on event.type, update UI
}
```

`bytes.lines` is what makes this streaming rather than blocking — it yields
one line at a time *as it arrives on the wire*, matching how `server.py`
writes one SSE frame per event as `core/loop.py`'s `run()` yields it, not
after the whole conversation turn finishes.

`LoopEvent` needs to decode whichever fields are present for a given
`"type"` — since the shape varies by event type, an all-optional
`Decodable` struct (or an enum with a custom `init(from:)` switching on
`type`) both work:

```swift
struct LoopEvent: Decodable {
    let type: String
    let turn: Int?
    let text: String?
    let state: String?
    let name: String?
    let id: String?
    let toolCallId: String?
    let result: String?

    enum CodingKeys: String, CodingKey {
        case type, turn, text, state, name, id, result
        case toolCallId = "tool_call_id"
    }
}
```

`session_id` is entirely the frontend's choice — generate a UUID once per
chat window and reuse it on every `POST /chat` for that conversation.
`server.py`'s `sessions` dict (`server.py:47`) only uses it as a lookup key
for that conversation's growing `messages` history; there's no handshake
beyond sending the same string every time.

## Status

Implemented: `core/loop.py`'s `run()` is an async generator yielding the
event dicts above instead of calling `print()`; `main.py` has
`print_events()` turning those same events into the terminal output it had
before; `server.py` drives the identical generator and streams the
identical dicts as SSE for a SwiftUI client to consume, per Q7 above.
