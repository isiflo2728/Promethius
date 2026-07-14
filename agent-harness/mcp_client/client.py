"""
- mcp developed my anthropic
- open sources
- 3 main functinos needed to make a client
- The blue print
    - how to start the server
    - example, using the command 'npx'
- The transport
- The communicator

#connect
"""

# Changes (2026-07-13, verification pass):
# 1. connect() used to open stdio_client/ClientSession as `async with` blocks
#    scoped to the connect() call itself — both were torn down (subprocess
#    killed, session's receive loop cancelled) the moment connect() returned,
#    so every session stored in self.sessions was already dead before call()
#    could ever use it. Fixed by entering both context managers into a
#    single AsyncExitStack kept on self, so they stay open for the client's
#    whole lifetime and are only closed in disconnect_all().
# 2. call() fell through to an implicit `return None` when result.content
#    was an empty list, breaking its declared `-> str` contract. Added an
#    explicit fallback return.
# 3. disconnect_all() manually called session.__aexit__() only, which never
#    closed the underlying stdio transport/subprocess. Now just closes the
#    shared AsyncExitStack, which unwinds every entered context in order.
# 4. connect()'s `args: list[str] = []` was a mutable default argument
#    (unused as a footgun today, but a standard one to avoid). Changed to
#    `None` with `args = args or []` inside.
# 5. tool.description can be None per the SDK (Tool.description: str | None).
#    That was stored as-is and would've reached providers/local.py's
#    _format_tools() as a literal None (dict.get's default only applies to
#    *missing* keys, not None values) — now defaulted to "" at the source.
#
# Changes (2026-07-13, transport split for remote servers e.g. Composio):
# 6. connect() only supported stdio (local subprocess servers) — no way to
#    reach a remote MCP server like Composio's, which speaks streamable-HTTP
#    over a URL with an `x-api-key` header, not stdin/stdout. Split into
#    connect_stdio() (the old connect(), renamed) and a new connect_http()
#    using mcp.client.streamable_http.streamablehttp_client(). Both are thin
#    wrappers that build a transport-specific (read_stream, write_stream)
#    pair and then hand off to a shared _register() for the session
#    handshake + tool-list bookkeeping — that half of connect() never cared
#    which transport produced the streams, so it isn't duplicated per
#    transport. Adding a third transport later (SSE, websocket) means one
#    more thin connect_*() wrapper, not touching _register() at all.

# ClientSession : the communicator
# gives asy
from contextlib import AsyncExitStack
from typing import Any
import httpx
from anyio.streams.memory import MemoryObjectReceiveStream, MemoryObjectSendStream
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamable_http_client
from mcp.shared.message import SessionMessage
from mcp.types import CallToolResult


class MCPClient:
    def __init__(self):
        self.sessions: dict[str, ClientSession] = {}
        self._tools: list[dict[str, Any]] = []
        # Holds every context manager we enter (per-server transport +
        # ClientSession, regardless of which connect_*() opened it) so they
        # stay open until disconnect_all() explicitly closes them, instead
        # of closing themselves when the connect_*() call returns.
        self._exit_stack = AsyncExitStack()

    async def connect_stdio(
        self, name: str, command: str, args: list[str] | None = None
    ):
        """Connect to a local MCP server, spawned as a subprocess and
        talked to over its stdin/stdout (e.g. `npx @modelcontextprotocol/server-filesystem`).
        """

        # how to connect to the server / starting the server
        # just defining how to launcch a srver
        # i.e. command = npx  args = server_name
        server_params = StdioServerParameters(command=command, args=args or [])

        # launch the server and grab the raw communication pipes
        # entered on the shared exit stack (not a local `async with`) so the
        # subprocess/pipes outlive this function call
        read_stream, write_stream = await self._exit_stack.enter_async_context(
            stdio_client(server_params)
        )
        await self._register(name, read_stream, write_stream)

    async def connect_http(
        self, name: str, url: str, headers: dict[str, str] | None = None
    ):
        """Connect to a remote MCP server over streamable HTTP — e.g.
        Composio, whose servers live at a URL like
        `https://backend.composio.dev/v3/mcp/{server_id}?user_id={id}` and
        are authenticated via an `x-api-key` header rather than a spawned
        subprocess.
        """
        # streamable_http_client doesn't take headers directly — it expects
        # a pre-configured httpx.AsyncClient (that's how auth/headers are
        # set now; the old headers= kwarg lived on the now-deprecated
        # streamablehttp_client). Since we're supplying our own client,
        # streamable_http_client won't manage its lifecycle for us (see its
        # docstring: "Only manage client lifecycle if we created it") — so
        # it goes on the shared exit stack too, same as everything else.
        http_client = await self._exit_stack.enter_async_context(
            httpx.AsyncClient(headers=headers)
        )
        # streamable_http_client yields a 3-tuple (unlike stdio_client's
        # 2-tuple) — the third item lets you read back the server-assigned
        # session id, which we don't need here since ClientSession tracks
        # its own session state internally.
        read_stream, write_stream, _ = await self._exit_stack.enter_async_context(
            streamable_http_client(url, http_client=http_client)
        )
        await self._register(name, read_stream, write_stream)

    async def _register(
        self,
        name: str,
        # Type params match what stdio_client/streamablehttp_client actually
        # yield (see mcp/client/stdio/__init__.py, mcp/client/streamable_http.py):
        # the read side can carry either a message or a propagated Exception,
        # the write side only ever carries outgoing messages.
        read_stream: MemoryObjectReceiveStream[SessionMessage | Exception],
        write_stream: MemoryObjectSendStream[SessionMessage],
    ) -> None:
        """Shared by every connect_*() method: wrap a transport's raw
        streams in a ClientSession, handshake, and pull in that server's
        tools. Everything past the streams is transport-agnostic — this is
        the half of connecting that stdio and streamable-HTTP (and any
        future transport) have identically in common, so it only lives in
        one place.
        """
        # wrapping those raw pipes in a protocol translator (JRPC)
        # i.e. creating a sessio
        # session is a client session object — also entered on the shared
        # exit stack so it outlives the connect_*() call
        session = await self._exit_stack.enter_async_context(
            ClientSession(read_stream, write_stream)
        )

        # handshake with the server
        _ = await session.initialize()
        self.sessions[name] = session

        # ask the server what it can perform
        # list_tools() returns a ListToolsResult object
        # each object within that list is a Tool object
        # contains three pieces of data:
        # name , description, inputSchema (Dictionary: JSON Scheme_
        # input Scehema is just the arguments the tool reuqires (path String)
        tools = await session.list_tools()

        # pulling the servers tools and adding it to the master list
        for tool in tools.tools:
            self._tools.append(
                {
                    "name": tool.name,
                    # tool.description is str | None per the SDK — default
                    # to "" so a None never reaches the OpenAI-format schema.
                    "description": tool.description or "",
                    "input_schema": tool.inputSchema,
                    "_server": name,
                }
            )

    def schemas(self) -> list[dict[str, object]]:
        """
        Retun all tool schmes to pass to the model
        Before returning the schemas, we cannot have the _server field -> api info is strict so we need to remove it
        """
        return [
            {key: value for key, value in t.items() if key != "_server"}
            for t in self._tools
        ]

    async def call(self, tool_name: str, arguments: dict[str, Any]) -> str:
        """Find which server owns this tool and call it."""
        server_name = next(
            (t["_server"] for t in self._tools if t["name"] == tool_name), None
        )
        if not server_name:
            return f"Error: tool '{tool_name}' not found in any MCP server"

        session = self.sessions[server_name]

        try:
            # result : CallToolResult
            result: CallToolResult = await session.call_tool(tool_name, arguments)

            if not result.content:
                # Legal per CallToolResult.content: list[ContentBlock] — a
                # tool can return no content blocks at all. Must still
                # return a str here (not fall through to an implicit
                # None), since the caller always expects a string back.
                return ""

            final_output = []

            for item in result.content:
                # 1. Handle standard text
                if item.type == "text":
                    final_output.append(item.text)

                # 2. Handle images (Base64 data)
                elif item.type == "image":
                    # If your model supports vision, you can pass this base64 data to it.
                    # If not, you at least tell the model an image was generated.
                    final_output.append(f"[Tool generated an image: {item.mimeType}]")

                # 3. Handle resource links / embedded files
                elif item.type == "resource":
                    final_output.append(
                        f"[Tool referenced a resource at URI: {item.resource.uri}]"
                    )

                # Fallback for future protocol updates (e.g. AudioContent,
                # ResourceLink — not individually handled above)
                else:
                    final_output.append(f"[Unknown data type returned: {item.type}]")

            # Join everything together with newlines
            return "\n".join(final_output)

        except Exception as e:
            return f"error calling {tool_name}: {e}"

    async def disconnect_all(self):
        """Tear down every connection this client opened.

        Closes the shared AsyncExitStack, which unwinds every transport +
        ClientSession pair entered by connect_stdio()/connect_http() — in
        reverse order, same as nested `async with` blocks would have.
        """
        await self._exit_stack.aclose()
        self.sessions.clear()
