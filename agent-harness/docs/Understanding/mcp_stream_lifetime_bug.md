# The memory-stream lifetime bug in `mcp_client/client.py`

**Question asked:** What are `MemoryObjectReceiveStream`/`MemoryObjectSendStream`,
why does `mcp_client/client.py` mention them, and what was actually wrong
with the original `connect()` before it got fixed?

This traces a real bug found and fixed in this repo — not a hypothetical.

---

## 1. What the streams actually are

> **ELI5:** Picture two rooms in the same house connected by a pneumatic
> tube — the kind you put a canister in, and it whooshes through and pops
> out the other end. One room can only *drop things in*, the other room
> can only *take things out*. `MemoryObjectSendStream` is the "drop things
> in" end, `MemoryObjectReceiveStream` is the "take things out" end. It's
> not the internet, it's not a subprocess — it's just a tube connecting
> two parts of the *same* running program.

They aren't part of MCP at all — they're from `anyio`, the async
concurrency library MCP is built on. Straight from `anyio/streams/memory.py`:

```python
class MemoryObjectReceiveStream(Generic[T_co], ObjectReceiveStream[T_co]):
    ...
class MemoryObjectSendStream(Generic[T_contra], ObjectSendStream[T_contra]):
    ...
```

You create them together, as a linked pair:

```python
send_stream, receive_stream = anyio.create_memory_object_stream(0)
```

One coroutine calls `.send(item)` on the send end; another coroutine calls
`.receive()` on the receive end and gets that same item. Think
`asyncio.Queue`, split into two ends. Nothing about them knows or cares
about JSON-RPC, subprocesses, or HTTP — they're a generic in-process
"pass an object from task A to task B" channel.

## 2. Why MCP uses them

> **ELI5:** The real tool (a subprocess, or a website out on the internet)
> doesn't talk in neat little messages — it talks in raw squiggly bytes
> coming down a wire. Somebody has to sit there, listen to the squiggles,
> translate each one into a tidy message, and drop the tidy message into
> the tube. `ClientSession` — the part of the code that actually asks
> "what tools do you have?" — never listens to the squiggles itself. It
> just stands at the other end of the tube and picks up tidy messages as
> they pop out.

From `mcp/client/stdio/__init__.py` (the actual SDK source):

```python
read_stream_writer, read_stream = anyio.create_memory_object_stream(0)
write_stream, write_stream_reader = anyio.create_memory_object_stream(0)
```

`stdio_client` spawns a background task that reads raw bytes off a
subprocess's stdout, parses each line into a `SessionMessage`, and pushes
it into `read_stream_writer` — which `ClientSession` drains from the other
end (`read_stream`) whenever it calls `.receive()`. Same idea in reverse
for writes. `streamablehttp_client` does the analogous thing for an HTTP
connection instead of a subprocess pipe — different background plumbing,
but it hands `ClientSession` the *same two stream types* on the way out.

> **ELI5:** The clever bit: it doesn't matter *who's* dropping messages
> into the tube. For a subprocess, one kind of listener translates
> squiggles-from-a-pipe into tube-messages. For a website, a totally
> different listener translates squiggles-from-the-internet into
> tube-messages. But `ClientSession` only ever sees "a tube with messages
> coming out of it" — so the exact same `ClientSession` works no matter
> which kind of listener is feeding it.

That uniformity is *why* `connect_stdio()` and `connect_http()` in this
project's `mcp_client/client.py` can both hand off to the same shared
`_register()` method — by the time the tube shows up, it looks identical
either way, regardless of which transport built it.

## 3. Why they show up in `_register()`'s signature

Before the refactor, `read_stream`/`write_stream` were just local
variables inside one big `connect()` — Python never needed an explicit
type for them. Once the shared logic got pulled out into its own method
(`_register(self, name, read_stream, write_stream)`), that became a real
function boundary between two callers (`connect_stdio`, `connect_http`)
and a callee — so the parameters got typed, to make the boundary
self-documenting and let the type checker confirm both callers actually
pass what `ClientSession(...)` downstream expects.

## 4. The original problem — what the code actually had before

The tube itself was never broken. The original `connect()` *did* build a
working tube and put a listener (`ClientSession`) at the end of it. The
problem was **how long the tube stayed connected.**

```python
# ORIGINAL — before the fix
async def connect(self, name: str, command: str, args: list[str] = []):
    server_params = StdioServerParameters(command=command, args=args)
    async with stdio_client(server_params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            _ = await session.initialize()
            self.sessions[name] = session          # <- saved here...
            tools = await session.list_tools()
            for tool in tools.tools:
                self._tools.append({...})
    # ...but both `async with` blocks close right here, when connect() returns.
```

> **ELI5:** Here's what the code originally did, in order:
> 1. `connect()` gets called.
> 2. It builds the tube (`stdio_client`) and puts a listener at the end of
>    it (`ClientSession`) — but it does this using Python's `async with`,
>    which is like saying **"set this up, but the moment I'm done with
>    this paragraph of code, tear it back down automatically."**
> 3. While still inside that same paragraph, it writes the listener's name
>    on a sticky note and puts the sticky note in a drawer
>    (`self.sessions[name] = session`) — "so I can find them again later."
> 4. `connect()` finishes. The paragraph ends. Python keeps its promise
>    from step 2: it rips the tube out of the wall and tells the listener
>    to go home.
> 5. Later, something opens the drawer, finds the sticky note, and tries
>    to send a message through "that listener." But the listener isn't
>    there anymore — the tube got ripped out three steps ago. The sticky
>    note still has a name on it, but it's a phone number for a line
>    that's already been disconnected.
>
> That's the whole bug: **you kept the name, but not the connection.**
> Writing something in a dictionary doesn't keep it alive — it just keeps
> you from forgetting its name.

Concretely, exiting `ClientSession`'s `async with` block calls its
`__aexit__`, which (per `mcp/shared/session.py`) cancels the task group
running its background receive loop:

```python
# mcp/shared/session.py
async def __aexit__(self, exc_type, exc_val, exc_tb) -> bool | None:
    self._task_group.cancel_scope.cancel()
    return await self._task_group.__aexit__(exc_type, exc_val, exc_tb)
```

And exiting `stdio_client`'s block tears down the subprocess and closes
its pipes. So by the time anything later called `self.sessions[name]`,
that session's receive loop was already cancelled and its transport
already closed — any `call()` against it would hang or fail.

## 5. The fix — change who decides when the tube closes

> **ELI5:** The fix (`AsyncExitStack`) changes step 2's promise. Instead
> of "tear this down the moment this paragraph ends," it's "keep this tube
> nailed to the wall until someone *specifically* tells you to take it
> down" — and that "someone" is now `disconnect_all()`, called only when
> you're genuinely done with the whole `MCPClient`, not just done with one
> `connect()` call. Same tube, same listener — the only thing that
> changed is *who decides when it gets torn down.*

```python
# FIXED — current version
def __init__(self):
    self.sessions: dict[str, ClientSession] = {}
    self._tools: list[dict[str, Any]] = []
    self._exit_stack = AsyncExitStack()

async def connect_stdio(self, name, command, args=None):
    server_params = StdioServerParameters(command=command, args=args or [])
    read_stream, write_stream = await self._exit_stack.enter_async_context(
        stdio_client(server_params)
    )
    await self._register(name, read_stream, write_stream)

async def disconnect_all(self):
    await self._exit_stack.aclose()   # tears everything down, in order, on purpose
    self.sessions.clear()
```

`enter_async_context(...)` does the same setup work `async with` would
have done, but instead of tying the teardown to the end of a code block,
it registers the teardown on `self._exit_stack` — which lives as long as
the `MCPClient` object does. Nothing closes until `disconnect_all()`
explicitly calls `self._exit_stack.aclose()`, which unwinds every
transport + session it was ever handed, in reverse order, in one place.

## 6. A smaller, separate mistake made during the same fix

Unrelated to the lifetime bug above, but worth recording since it came up
in the same pass: when adding type hints for `_register()`'s stream
parameters, the import was first guessed as `mcp.shared.memory` — reasoning
(wrongly) that since MCP's session code lives in `mcp/shared/session.py`,
the stream types might live in a matching `mcp.shared` location. That
module doesn't exist; Pyright caught it immediately
(`Import "mcp.shared.memory" could not be resolved`). The fix was checking
where the SDK's own `stdio.py` imports these from —
`from anyio.streams.memory import MemoryObjectReceiveStream, MemoryObjectSendStream`
— and matching that.

> **ELI5:** Like guessing the scissors are in the junk drawer when they're
> actually in the desk drawer. Nothing was broken, just mislabeled — the
> real toolbox's own code was checked to see which shelf *it* keeps them
> on, and the label was fixed to match.
