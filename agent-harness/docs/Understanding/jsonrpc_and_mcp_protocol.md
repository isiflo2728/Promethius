# JSON-RPC and MCP: what they are, how they're structured, how to build with them

**Question asked:** What is JSON-RPC, what does MCP add on top of it, and
concretely — how do I write an MCP client (`mcp_client/client.py`) and an MCP
server that exposes tools/functions? How do the two sides actually talk to
each other?

This project already depends on the real SDK (`"mcp>=1.28.1"` in
`pyproject.toml`), so everything below traces actual classes in
`.venv/lib/python3.11/site-packages/mcp/`, not paraphrased spec text.

---

## 1. JSON-RPC 2.0, just enough to read an MCP message

> **ELI5:** Imagine sending a letter that says "please do X" and puts a
> ticket number in the corner. The reply letter has to include that same
> ticket number, so when replies come back out of order you still know
> which question each answer belongs to. Some letters don't need a reply at
> all — you just drop them in the mailbox and walk away. That's the whole
> trick: request-with-ticket-number, reply-with-same-ticket-number, or
> reply-not-needed.

JSON-RPC is a tiny wire format for "call a named method with some
parameters, maybe get a result back." It has exactly three message shapes,
all defined in `mcp/types.py` (MCP uses JSON-RPC 2.0 verbatim as its
transport-level envelope):

```python
# mcp/types.py:152
class JSONRPCRequest(Request[dict[str, Any] | None, str]):
    """A request that expects a response."""
    jsonrpc: Literal["2.0"]
    id: RequestId
    method: str
    params: dict[str, Any] | None = None

# mcp/types.py:161
class JSONRPCNotification(Notification[dict[str, Any] | None, str]):
    """A notification which does not expect a response."""
    jsonrpc: Literal["2.0"]
    params: dict[str, Any] | None = None

# mcp/types.py:168
class JSONRPCResponse(BaseModel):
    """A successful (non-error) response to a request."""
    jsonrpc: Literal["2.0"]
    id: RequestId
    result: dict[str, Any]

# mcp/types.py:214
class JSONRPCError(BaseModel):
    """A response to a request that indicates an error occurred."""
    jsonrpc: Literal["2.0"]
    id: str | int
    error: ErrorData   # {code: int, message: str, data: Any | None}
```

That's the whole vocabulary:

| Shape | Has `id`? | Expects a reply? | Example use in MCP |
|---|---|---|---|
| `JSONRPCRequest` | yes | yes | client asks `tools/call` |
| `JSONRPCNotification` | no | no | server says `notifications/tools/list_changed` |
| `JSONRPCResponse` | yes (echoes request's `id`) | — | server returns tool output |
| `JSONRPCError` | yes (echoes request's `id`) | — | server says "unknown tool" |

The `id` is the entire correlation mechanism — over a single stdin/stdout
pipe (see §3), requests and responses can arrive out of order or
interleaved with unrelated notifications; the only way to match a response
back to "the call I made" is the `id` you sent in the request showing back
up in the response. Everything else — `method`, `params`, `result` — is
just an untyped `dict`/`str` as far as JSON-RPC itself is concerned. JSON-RPC
doesn't know or care what `"tools/call"` means; it's purely an envelope.

## 2. What MCP adds on top

> **ELI5:** JSON-RPC is just "how to write a letter." MCP is a specific set
> of *pre-agreed sentences* everyone writing these letters agrees to use —
> "what tools do you have?" and "please run this tool" always look exactly
> the same way, no matter who wrote the server. That's why one client can
> talk to a filesystem server, a browser server, and a database server
> without being taught anything new about each one.

MCP (Model Context Protocol, from Anthropic) is a fixed *vocabulary* of
JSON-RPC methods plus a session lifecycle, so that any client can talk to
any server without bespoke integration code per tool. Per
`docs/AGENT_ARCHITECTURE.md` §9:

```
Your app → [MCP protocol] → filesystem server
Your app → [MCP protocol] → browser server
Your app → [MCP protocol] → database server
```

Write the client once; every compliant server — filesystem, browser,
database, git — just works. The methods relevant to tools:

| JSON-RPC `method` | Direction | Params → Result |
|---|---|---|
| `initialize` | client → server | capabilities handshake → `InitializeResult` |
| `tools/list` | client → server | (optional `cursor` for pagination) → `ListToolsResult` (`tools: list[Tool]`) |
| `tools/call` | client → server | `{name, arguments}` → `CallToolResult` |
| `notifications/tools/list_changed` | server → client | none (a `Notification`, no reply) |

**What MCP standardizes:** how your app discovers and invokes tools that
live in a separate process, over a transport it also standardizes (stdio,
or HTTP/SSE for remote servers).

**What MCP does *not* standardize:** how you present those tools to an LLM.
A `Tool` from `tools/list` uses `inputSchema` — see below — while
OpenAI-compatible chat APIs (what `providers/local.py` talks to) expect
`parameters` inside a `{"type": "function", "function": {...}}` wrapper.
Translating between the two is still your job — this project's
`Tool.to_schema()` in `tool.py` and the reference `_format_tools()` in
`docs/AGENT_ARCHITECTURE.md` §9 both exist for exactly this reason.

### The `Tool` shape (what `tools/list` returns)

```python
# mcp/types.py:1315
class Tool(BaseMetadata):        # BaseMetadata gives it `name`, `title`
    """Definition for a tool the client can call."""
    description: str | None = None
    inputSchema: dict[str, Any]   # JSON Schema for the tool's parameters
    outputSchema: dict[str, Any] | None = None
    annotations: ToolAnnotations | None = None
```

Compare this to this project's own `Tool` dataclass in `tool.py`
(name/description/JSON-Schema `parameters`/Python `fn`) — same idea, but
MCP's version has no `fn`. That's the core architectural split: **an MCP
`Tool` is a description of something that lives on the *server* side**; the
client never holds a callable, only a schema plus a name to call later
over the wire via `tools/call`.

### The `CallToolResult` shape (what `tools/call` returns)

```python
# mcp/types.py:1379
class CallToolResult(Result):
    """The server's response to a tool call."""
    content: list[ContentBlock]              # text/image/etc. blocks
    structuredContent: dict[str, Any] | None = None
    isError: bool = False
```

Note `isError: bool` rather than a JSON-RPC-level error — a tool that fails
*at the application level* (e.g. "file not found") still comes back as a
normal `JSONRPCResponse`/`CallToolResult` with `isError=True`, not a
`JSONRPCError`. `JSONRPCError` is reserved for protocol-level failures
(unknown method, malformed params). This mirrors the design note in
CLAUDE.md that tool dispatch must "catch all exceptions and return a JSON
error string — a broken tool must not crash the loop": MCP servers are
expected to do the same thing at the protocol level.

## 3. Transport: how the bytes actually move

> **ELI5:** The letters need a mailbox to travel through. For a tool that
> lives on your own computer, the "mailbox" is just two ends of a pipe: your
> program starts up the tool as a separate little program, and they pass
> letters back and forth through its input/output, like two kids talking
> through a tin-can telephone.

MCP doesn't send bytes itself — JSON-RPC messages ride on top of a
transport, and for local tool servers (the case this project cares about)
that's **stdio**: the client spawns the server as a subprocess and
exchanges newline-delimited JSON-RPC messages over its stdin/stdout.

```python
# mcp/client/stdio/__init__.py:72
class StdioServerParameters(BaseModel):
    command: str                      # the executable to run
    args: list[str] = Field(default_factory=list)
    env: dict[str, str] | None = None
    cwd: str | Path | None = None

# mcp/client/stdio/__init__.py:106
async def stdio_client(server: StdioServerParameters, errlog: TextIO = sys.stderr):
    """Client transport for stdio: this will connect to a server by
    spawning a process and communicating with it over stdin/stdout."""
```

This is why `docs/AGENT_ARCHITECTURE.md`'s example servers are launched as
subprocesses:

```python
await mcp.connect("filesystem", "npx", ["-y", "@modelcontextprotocol/server-filesystem", "."])
```

`stdio_client` gives you back a pair of anyio memory streams
(`read_stream`, `write_stream`) — raw message plumbing, not yet a session.
That's the next layer.

## 4. `ClientSession` — the thing you actually call

> **ELI5:** You don't want to hand-write letters and watch the mailbox
> yourself every time. `ClientSession` is like a personal assistant: you
> say "ask them what tools they have" or "ask them to run this tool," and
> the assistant writes the letter, remembers the ticket number, watches for
> the matching reply, and hands you back just the answer.

`ClientSession` (in `mcp/client/session.py`) wraps the raw read/write
streams from `stdio_client` and gives you the actual RPC methods as
`async` functions, handling `id` bookkeeping for you:

```python
# mcp/client/session.py:160
async def initialize(self) -> types.InitializeResult: ...

# mcp/client/session.py:525
async def list_tools(self, cursor: str | None = None, ...) -> types.ListToolsResult: ...

# mcp/client/session.py:386
async def call_tool(
    self,
    name: str,
    arguments: dict[str, Any] | None = None,
    ...
) -> types.CallToolResult: ...
```

Putting §3 and §4 together is the entire shape of what `mcp_client/client.py` is
meant to become (currently an empty stub — see CLAUDE.md's "Known gaps"):

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

server_params = StdioServerParameters(
    command="npx",
    args=["-y", "@modelcontextprotocol/server-filesystem", "."],
)

async with stdio_client(server_params) as (read, write):
    async with ClientSession(read, write) as session:
        await session.initialize()                 # handshake
        tools = await session.list_tools()          # → ListToolsResult
        result = await session.call_tool(            # → CallToolResult
            "read_file", {"path": "requirements.txt"}
        )
```

Under the hood, `session.call_tool(...)` builds a `CallToolRequest`
(`method="tools/call"`, `params=CallToolRequestParams(name=..., arguments=...)`),
serializes it as a `JSONRPCRequest` with a fresh `id`, writes it to the
subprocess's stdin, and waits for a `JSONRPCResponse` with the matching
`id` to come back on stdout — parsed into a `CallToolResult`. None of that
bookkeeping is something you write yourself; it's the entire value the SDK
adds over raw JSON-RPC.

Multiple servers = multiple independent `ClientSession`s. `mcp_client/client.py`'s
job (per `docs/AGENT_ARCHITECTURE.md` §9) is to hold a
`dict[str, ClientSession]` keyed by server name, so `mcp.call_tool("read_file", ...)`
can be routed to whichever session actually owns that tool — the same
registry-pattern preference noted in
`docs/research/learning_agent_architecture.md` for the in-process `Tool`
dispatcher, just one layer further out.

## 5. The server side: how a tool gets exposed in the first place

> **ELI5:** Somewhere, someone has to actually *have* the tool and know how
> to answer "what tools do you have?" and "please run this one." `FastMCP`
> is like a magic sticker: you slap `@server.tool()` on a plain Python
> function, and it automatically writes the "here's what this tool needs"
> instruction card for you, and automatically knows to run that function
> whenever a request for it arrives.

Everything above is the client's view. Somewhere, a process has to
actually implement `tools/list` and `tools/call` and answer them — that's
an MCP *server*. Hand-rolling the JSON-RPC handling for this is exactly the
kind of boilerplate the SDK's `FastMCP` class exists to remove:

```python
# mcp/server/fastmcp/server.py:446
@server.tool()
def read_file(path: str) -> str:
    """Read a file and return its contents."""
    return open(path).read()
```

`@server.tool()` inspects the function's signature and docstring, builds
its `inputSchema` (JSON Schema) automatically, and registers it so that:

- an incoming `tools/list` request returns this function as a `Tool` entry
  (name defaults to the function name, description defaults to the
  docstring, `inputSchema` generated from the type hints);
- an incoming `tools/call` request for `"read_file"` invokes the actual
  Python function and wraps whatever it returns into a `CallToolResult`.

Running the server just means picking a transport:

```python
# mcp/server/fastmcp/server.py:279
def run(self, transport: Literal["stdio", "sse", "streamable-http"] = "stdio", ...) -> None: ...
```

`"stdio"` is the case this project uses (matches `stdio_client` on the
client side above); `"sse"`/`"streamable-http"` are for a server running
remotely over HTTP rather than as a local subprocess.

**The symmetry to notice:** this project already has an in-process version
of exactly this client/server split — `tool.py`'s `Tool` dataclass +
`Agent._dispatch`'s `dict[str, Tool]` lookup *is* a tiny single-process
"MCP server," just without the JSON-RPC envelope, because the "server"
(your own Python functions) lives in the same process as the "client"
(the agent loop). MCP is what you reach for the moment a tool needs to live
in a different process, language, or machine than the loop calling it —
the wire format above is the price of that separation.

## 6. Putting it together, end to end

> **ELI5:** Put all the pieces in a line and it's just: ask what tools
> exist → pick one → send a letter asking it to run → the tin-can phone
> carries the letter over → the tool's program runs the function → the
> answer travels back through the same phone → your assistant matches it
> to the right ticket number → hands you the answer.

```
1. main.py spawns/connects to an MCP server (subprocess over stdio,
   or a remote HTTP endpoint).
2. mcp_client/client.py's ClientSession.initialize() does the capability handshake.
3. ClientSession.list_tools() → JSONRPCRequest{method:"tools/list"}
                               → server replies JSONRPCResponse{result: ListToolsResult}
4. mcp_client/client.py (or a _format_tools()-style shim) translates each MCP
   Tool.inputSchema into the OpenAI {"type":"function", "function":{...}}
   shape the model actually sees — same translation job Tool.to_schema()
   does for in-process tools in tool.py.
5. Model responds with a tool call → loop.py calls
   ClientSession.call_tool(name, arguments)
6. → JSONRPCRequest{method:"tools/call", id:N} sent over stdin
   → server executes the @server.tool()-decorated function
   → JSONRPCResponse{id:N, result: CallToolResult} sent back over stdout
7. mcp_client/client.py hands the CallToolResult's content back to loop.py,
   which appends it to conversation history and continues the loop.
```

The `id` from step 6 is what makes step 7 possible even if the server is
mid-flight on other requests or emitting unrelated notifications on the
same pipe — that one integer is doing all the correlation work JSON-RPC
provides.
