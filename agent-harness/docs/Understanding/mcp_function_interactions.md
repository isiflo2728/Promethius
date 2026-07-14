# How the MCP functions interact

Companion to `jsonrpc_and_mcp_protocol.md` — that doc explains what each
piece *is*; this one traces who calls whom, in what order, and what
actually crosses the process boundary at each step.

> **ELI5:** Think of it like ordering food through a food-delivery app. You
> (the agent loop) never talk to the kitchen (the tool) directly. You tap
> a button in the app (`call_tool`), the app writes up your order with an
> order number (`ClientSession` building a `JSONRPCRequest`), a delivery
> driver carries it over (stdio pipe), the kitchen cooks it (the
> `@server.tool()` function actually running), and the same driver brings
> the finished order back matched to your order number. Every layer below
> only ever talks to the layer directly next to it — you never have to
> know how the kitchen made the food, and the kitchen never has to know who
> you are.

## Two processes, not one

The single most important fact about this interaction map: **the client
side and the server side are two separate OS processes**, not two Python
modules calling each other directly. Nothing on the client side ever holds
a reference to the actual tool function — every arrow that crosses the
dashed line below is bytes over a pipe, not a Python function call.

```
┌─────────────────────────────┐        stdio pipe        ┌──────────────────────────────┐
│  CLIENT PROCESS              │◄────────────────────────►│  SERVER PROCESS               │
│  (this project)               │   JSON-RPC over          │  (e.g. filesystem server)      │
│                               │   stdin/stdout           │                                │
│  main.py                      │                          │  FastMCP instance              │
│    └─ mcp_client/client.py           │                          │    └─ @server.tool() functions │
│         └─ ClientSession      │                          │         (read_file, etc.)      │
│              └─ stdio_client  │                          │                                │
└─────────────────────────────┘                            └──────────────────────────────┘
```

## Call graph, function by function

| # | Caller | Calls | What happens | Crosses the pipe? |
|---|---|---|---|---|
| 1 | `main.py` | `mcp.client.stdio.stdio_client(StdioServerParameters(...))` | Spawns the server as a subprocess, opens its stdin/stdout as anyio streams | No — this *creates* the pipe |
| 2 | `main.py` | `ClientSession(read_stream, write_stream)` | Wraps the raw streams; no I/O yet | No |
| 3 | `main.py` | `session.initialize()` | Builds an `initialize` `JSONRPCRequest`, sends it, awaits the matching `JSONRPCResponse` | **Yes** |
| 4 | (server, automatically) | `FastMCP`'s internal request router | Receives the `initialize` request off stdin, replies with `InitializeResult` | **Yes** (reply) |
| 5 | `mcp_client/client.py` | `session.list_tools()` | Builds `JSONRPCRequest{method:"tools/list"}`, sends, awaits `ListToolsResult` | **Yes** |
| 6 | (server, automatically) | looks up every `@server.tool()`-registered function | Builds a `Tool` entry per function (name, docstring → description, type hints → `inputSchema`) | **Yes** (reply) |
| 7 | `mcp_client/client.py` | (local, no call) | Translates each MCP `Tool.inputSchema` into an OpenAI `{"type":"function",...}` shape — same job as `tool.py`'s `Tool.to_schema()` | No — pure local transform |
| 8 | `providers/local.py` | Ollama's `/v1/chat/completions` | Sends the translated tool schemas + conversation so far; model may respond with a tool call | No — separate HTTP call, not MCP |
| 9 | `agent.py`'s loop (`_dispatch`-equivalent) | `session.call_tool(name, arguments)` | Builds `JSONRPCRequest{method:"tools/call", params:{name, arguments}, id:N}`, sends, awaits `JSONRPCResponse` with matching `id` | **Yes** |
| 10 | (server, automatically) | the actual Python function decorated with `@server.tool()` | Runs it with the deserialized `arguments`, wraps the return value into `CallToolResult` | (runs entirely server-side) |
| 11 | (server, automatically) | replies over stdout | Sends `JSONRPCResponse{id:N, result: CallToolResult}` | **Yes** (reply) |
| 12 | `mcp_client/client.py` | (local, no call) | Matches the reply's `id` back to the pending call, returns `CallToolResult` to whoever awaited `call_tool(...)` | No |
| 13 | `agent.py`'s loop | appends `CallToolResult.content` to conversation history | Same shape the loop always uses — the MCP origin is invisible from here on | No |

Rows 1–2 happen once per server connection. Rows 3, 5–7 happen once per
session (or whenever the server sends a
`notifications/tools/list_changed`, in which case 5–7 repeat). Rows 8–13
repeat every time the model decides to call a tool — this is the part that
loops for the lifetime of the conversation.

## Why the split matters (the thing to actually remember)

Every row marked "crosses the pipe" is doing real work that a plain Python
function call wouldn't need: serialize the arguments to JSON, write bytes,
block until a reply with the matching `id` shows up, deserialize the
reply. Compare that to this project's in-process tools
(`tools/example_tools.py` dispatched via `Agent._dispatch`'s
`dict[str, Tool]`), where "calling a tool" is just `tool.fn(**arguments)` —
one Python stack frame, no serialization, no `id` matching, no subprocess.

MCP is the right tool exactly when you need row 1's subprocess boundary —
a tool implemented in another language, sandboxed for safety, or shared
across multiple client programs. It is deliberately more machinery than an
in-process `dict` dispatch, and that machinery is the price of the
tool no longer having to live in your process.

## Arguments in, values out — function by function

> **ELI5:** This is the "what do I hand it, what do I get back" cheat
> sheet — like a vending machine label that tells you exactly which coin
> slot to use and exactly what drops out the bottom.

### `stdio_client(server, errlog=sys.stderr)`

```python
# mcp/client/stdio/__init__.py:72,106
class StdioServerParameters(BaseModel):
    command: str                       # required — the executable to run
    args: list[str] = []               # command-line args
    env: dict[str, str] | None = None  # defaults to a filtered copy of your env
    cwd: str | Path | None = None      # working directory for the subprocess

async def stdio_client(server: StdioServerParameters, errlog: TextIO = sys.stderr):
    ...
```
- **Takes:** one `StdioServerParameters` (only `command` is required — everything
  else has a default), plus an optional file-like `errlog` the subprocess's
  stderr gets piped to (defaults to your own process's stderr).
- **Returns:** an async context manager yielding a `(read_stream, write_stream)`
  pair of anyio memory streams — raw plumbing, not yet usable for RPC calls.
  You almost never touch these directly; they go straight into `ClientSession`.

### `ClientSession(read_stream, write_stream, ...)`

```python
# mcp/client/session.py:122
def __init__(
    self,
    read_stream: MemoryObjectReceiveStream[SessionMessage | Exception],
    write_stream: MemoryObjectSendStream[SessionMessage],
    read_timeout_seconds: timedelta | None = None,   # per-request timeout
    sampling_callback: SamplingFnT | None = None,     # server asks client to run an LLM completion
    elicitation_callback: ElicitationFnT | None = None,  # server asks client for user input
    list_roots_callback: ListRootsFnT | None = None,  # server asks what dirs it can access
    logging_callback: LoggingFnT | None = None,       # server pushes log lines to you
    message_handler: MessageHandlerFnT | None = None, # catch-all for unmatched messages
    client_info: types.Implementation | None = None,  # your app's name/version
) -> None: ...
```
- **Takes:** the two streams from `stdio_client` (required) plus a pile of
  *optional* callbacks for server-initiated requests. For this project's
  basic use case (client calls tools, server just answers) every optional
  argument can be left at its default — they only matter for advanced
  features (server-side sampling, elicitation, logging) that
  `docs/AGENT_ARCHITECTURE.md`'s roadmap hasn't reached yet.
- **Returns:** nothing (it's a constructor) — use as `async with ClientSession(...) as session:`.

### `session.initialize()`

```python
async def initialize(self) -> types.InitializeResult
```
- **Takes:** nothing — reads capabilities from the `ClientSession` you already
  constructed.
- **Returns:** `InitializeResult`:
  ```python
  # mcp/types.py:691
  class InitializeResult(Result):
      protocolVersion: str | int         # MCP version the server wants to use
      capabilities: ServerCapabilities   # what the server supports (tools/resources/prompts/...)
      serverInfo: Implementation         # server's own name + version
      instructions: str | None = None    # free-text usage notes from the server
  ```
  Must be called (and the handshake completed) before `list_tools`/`call_tool`
  will work — this is the one required call in the whole session lifecycle.

### `session.list_tools(cursor=None)`

```python
async def list_tools(self, cursor: str | None = None, *, params=None) -> types.ListToolsResult
```
- **Takes:** an optional pagination `cursor` (a string an earlier response
  handed you, if the server has more tools than fit in one reply) — pass
  nothing to get the first page.
- **Returns:** `ListToolsResult`:
  ```python
  # mcp/types.py:144, 1342
  class ListToolsResult(PaginatedResult):   # PaginatedResult adds:
      tools: list[Tool]                     #   nextCursor: str | None
  ```
  `nextCursor is None` means you have every tool the server offers; a
  non-`None` value means call `list_tools(cursor=that_value)` again for
  more.

### `session.call_tool(name, arguments=None, ...)`

```python
async def call_tool(
    self,
    name: str,                                        # must match a Tool.name from list_tools
    arguments: dict[str, Any] | None = None,           # must satisfy that Tool's inputSchema
    read_timeout_seconds: timedelta | None = None,
    progress_callback: ProgressFnT | None = None,      # called with incremental progress updates
    *,
    meta: dict[str, Any] | None = None,
) -> types.CallToolResult
```
- **Takes:** the tool's `name` (required, a plain string), its `arguments`
  as a plain `dict` (required whenever the tool's `inputSchema` has required
  fields — same "model's raw JSON must satisfy this schema" contract as
  this project's own `Tool.parameters`), and optional timeout/progress/meta
  knobs you can ignore for a first implementation.
- **Returns:** `CallToolResult`:
  ```python
  # mcp/types.py:1379
  class CallToolResult(Result):
      content: list[ContentBlock]              # usually [TextContent(type="text", text=...)]
      structuredContent: dict[str, Any] | None = None
      isError: bool = False                    # True = tool-level failure, not protocol-level
  ```
  In practice, for a text-returning tool you read
  `result.content[0].text` — same "flatten it to a string" step this
  project's own tools already do by returning `str` from `fn`.

### `@server.tool(...)` (server side)

```python
# mcp/server/fastmcp/server.py:446
def tool(
    self,
    name: str | None = None,          # defaults to the function's own name
    title: str | None = None,
    description: str | None = None,   # defaults to the function's docstring
    annotations: ToolAnnotations | None = None,
    icons: list[Icon] | None = None,
    meta: dict[str, Any] | None = None,
    structured_output: bool | None = None,
) -> Callable[[AnyFunction], AnyFunction]
```
- **Takes:** all-optional metadata about how the tool should present itself;
  called as `@server.tool()` (parentheses required — the SDK explicitly
  raises `TypeError` if you write bare `@server.tool` and forget them).
  The wrapped function's own parameters and type hints are what actually
  generate the client-visible `inputSchema` — there's no separate schema to
  write by hand, unlike this project's `tool.py`, where `parameters` is
  written out manually.
- **Returns:** the original function, unchanged, so it still works as a
  normal Python function — the decorator's real effect is a side effect
  (registering the function on `self`, the `FastMCP` instance), not its
  return value.

### `server.run(transport="stdio")`

```python
# mcp/server/fastmcp/server.py:279
def run(self, transport: Literal["stdio", "sse", "streamable-http"] = "stdio", mount_path: str | None = None) -> None
```
- **Takes:** which transport to listen on (`"stdio"` for the subprocess case
  this project uses; `"sse"`/`"streamable-http"` for a remotely-hosted
  server, with `mount_path` only meaningful for `"sse"`).
- **Returns:** nothing — it's synchronous and blocks, running the server's
  event loop until the process is killed or the transport closes.
