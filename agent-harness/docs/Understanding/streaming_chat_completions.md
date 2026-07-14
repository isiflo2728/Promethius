# Streaming: What `stream=True` Actually Returns, and Two Bugs It Exposed in `local.py`

A discussion thread about `providers/local.py`'s `stream()` method — what
object types are involved in streaming mode, and two real bugs that
understanding those types uncovered.

---

## Q1: What is `response` when `stream=True`, and what gets created?

```python
response = await self.client.chat.completions.create(  # pyright: ignore[reportCallIssue]
    model=self.model,
    messages=self._format_messages(messages, system),  # pyright: ignore[reportArgumentType]
    tools=self._format_tools(tools) if tools else None,  # pyright: ignore[reportArgumentType]
    stream=True,
)
```

### Same method, two completely different return types

`.create()` is one method, but it's overloaded on the `stream` argument.
Confirmed directly from the SDK's own overload signatures in
`.venv/lib/python3.11/site-packages/openai/resources/chat/completions/completions.py`:

```python
# stream omitted / False:
) -> ChatCompletion

# stream: Literal[True]:
) -> AsyncStream[ChatCompletionChunk]
```

**In `complete()`** (no `stream=True`): `response` is a `ChatCompletion` —
one finished object, handed to you only after the model is completely done
generating.

**In `stream()`** (with `stream=True`): `response` is an
`AsyncStream[ChatCompletionChunk]` — **not the reply itself**. It's a live,
open connection to the model. The `await` on that line doesn't wait for the
model to finish — it just waits for the connection to be *established*.
Nothing has necessarily been generated yet at that point.

### Analogy: ordering a pizza

- **`complete()`** = you call the pizzeria, they don't say a word back until
  the whole pizza is baked, boxed, and handed to you at once.
- **`stream()`** = you call the pizzeria, and they immediately hand you a
  walkie-talkie (that's `response`). Nothing's cooked yet — the
  walkie-talkie is just the open channel. Then:

  ```python
  async for chunk in response:
  ```

  is you listening on that walkie-talkie. Every time the kitchen (the
  model) finishes generating a little more text, a `ChatCompletionChunk`
  comes through — one small piece (a `delta`), not the whole pizza. You
  keep looping, getting one chunk at a time, until the model signals it's
  done.

So: `response` on that line is the *pipe*, not the *answer*. The answer
arrives piece by piece through `async for chunk in response`.

---

## Q2: What object is returned to `response`, and what's inside each object you iterate?

### `response` itself: not an object with fields — a pipe

`response` is of type `AsyncStream[ChatCompletionChunk]`. It has no
`.content`, no `.choices` of its own — it's an **async-iterable
connection**, not a data object. The only thing you can meaningfully do
with it is loop over it.

Each time through that loop, you get back **one `ChatCompletionChunk`** —
a small, self-contained object representing "here's what's new since the
last chunk."

### The shape of each `chunk`

Straight from
`.venv/lib/python3.11/site-packages/openai/types/chat/chat_completion_chunk.py`:

```
ChatCompletionChunk
├── id: str                                    ← same for every chunk in this stream
├── object: Literal["chat.completion.chunk"]
├── created: int
├── model: str
├── choices: List[Choice]                      ← can be EMPTY (see Q3)
│   └── Choice
│       ├── index: int
│       ├── finish_reason: Optional[Literal["stop", "length", "tool_calls", ...]]
│       │                                       ← None on every chunk except the last
│       └── delta: ChoiceDelta                  ← the actual new piece of data
│           ├── role: Optional[Literal["assistant", ...]]
│           │                                   ← only set on the FIRST chunk
│           ├── content: Optional[str]           ← a few new characters of text, or None
│           ├── refusal: Optional[str]
│           └── tool_calls: Optional[List[ChoiceDeltaToolCall]]
│               └── ChoiceDeltaToolCall
│                   ├── index: int               ← which tool call this fragment belongs to
│                   ├── id: Optional[str]         ← only present on the first fragment of a call
│                   ├── type: Optional[Literal["function"]]
│                   └── function: Optional[ChoiceDeltaToolCallFunction]
│                       ├── name: Optional[str]   ← only on the first fragment
│                       └── arguments: Optional[str]  ← a few new characters of JSON
└── usage: Optional[CompletionUsage]             ← None on every chunk unless you passed
                                                     stream_options={"include_usage": True};
                                                     even then, None until the final chunk
```

### The key mental shift from `ChatCompletion`

| | `ChatCompletion` (non-streaming) | `ChatCompletionChunk` (one of many, streaming) |
|---|---|---|
| How many you get | One, complete | Many, each a fragment |
| Text field | `choices[0].message.content` — the whole reply | `choices[0].delta.content` — a few new characters |
| Tool call | `message.tool_calls[i].function.arguments` — complete JSON string | `delta.tool_calls[i].function.arguments` — a few new characters of JSON, needs `.index` to know which call it belongs to, and needs concatenating across many chunks before it's valid JSON |
| `usage` | Always present | `None` on nearly every chunk |

---

## Q3: Two bugs this exposed in `local.py`'s original `stream()`

The original implementation was:

```python
async for chunk in response:
    delta = chunk.choices[0].delta.content
    if delta:
        yield delta
```

### Bug 1 — Swallowed tool calls

`stream()` only ever reads `delta.content`. But per the `ChoiceDelta` shape
above, a streamed tool-call request arrives through a completely separate
field, `delta.tool_calls` — never through `.content`. Since this method
never looks at that field: the model streams a tool-call request in
pieces across several chunks, `delta.content` stays `None` for every one of
those chunks (there's no text to yield), the loop yields nothing, and the
method finishes having produced an empty string. Whatever's consuming
`stream()` has no way to know the model asked for anything — it just looks
like the model said nothing at all. A real, silent failure mode.

**Why this isn't a one-line fix in `local.py` alone:** `stream()`'s
declared return type, from `BaseProvider` in `providers/base.py`, is
`AsyncIterator[str]` — text only. There's no defined channel in the
interface for "here's a tool-call fragment." Making that work properly
means widening the interface itself (e.g. yielding a small tagged union of
text-delta vs. tool-call-delta events), which affects the abstract method
every future provider has to implement — bigger than a single-file fix.

**Proposed interim fix:** detect `delta.tool_calls` mid-stream and raise a
clear `NotImplementedError` ("use `complete()` for turns where the model
might call a tool") instead of silently discarding it. Converts a silent,
confusing failure into a loud, debuggable one, without redesigning the
interface yet.

### Bug 2 — `IndexError` crash on empty `choices`

Confirmed straight from the SDK's own docstring on
`ChatCompletionChunk.choices`:

> "Can also be empty for the last chunk if you set
> `stream_options: {"include_usage": true}`."

The original code does `chunk.choices[0].delta.content` with no check. The
moment a chunk arrives with `choices: []` — which the SDK itself says is
expected behavior in certain configurations, and which some
providers/proxies send unconditionally as a leading or trailing metadata
chunk — that line throws `IndexError: list index out of range` and kills
the whole streaming loop.

**Fix:** guard with `if not chunk.choices: continue` before indexing into
`choices[0]`.

### Status

These fixes were discussed and agreed on but **not yet applied** to
`providers/local.py` as of this writing — a safety commit
(`b1cd074`, "Checkpoint agent-harness scaffold before streaming fixes") was
made first so the current state can be reverted to if needed once the
`stream()` revision goes in.
