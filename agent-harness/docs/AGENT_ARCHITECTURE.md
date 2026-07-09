# Hermes-Style Agent — Project Architecture Reference

> **Purpose of this document:** Personal reference and project context file.
> If you are an AI model reading this to understand the project — this document
> captures every architectural decision made so far, why each decision was made,
> how it compares to how Hermes Agent (NousResearch) solved the same problem,
> and the full implementation code with comments. Read it top to bottom before
> suggesting changes or additions.

---

## Table of Contents

1. [Project Goal](#1-project-goal)
2. [What This Is Not](#2-what-this-is-not)
3. [High-Level Mental Model](#3-high-level-mental-model)
4. [Project File Hierarchy](#4-project-file-hierarchy)
5. [Technology Decisions](#5-technology-decisions)
6. [Architecture: The Agent Loop](#6-architecture-the-agent-loop)
7. [Architecture: Provider Layer](#7-architecture-provider-layer)
8. [Architecture: History Management](#8-architecture-history-management)
9. [Architecture: Tool Layer via MCP](#9-architecture-tool-layer-via-mcp)
10. [Architecture: Interrupt Handling](#10-architecture-interrupt-handling)
11. [Full Implementation Code](#11-full-implementation-code)
12. [Build Roadmap](#12-build-roadmap)
13. [Key Concepts Glossary](#13-key-concepts-glossary)

---

## 1. Project Goal

Build a **hermes-style autonomous agent harness** — similar to
[NousResearch/hermes-agent](https://github.com/nousresearch/hermes-agent) —
that:

- Runs a ReAct (Reasoning + Acting) loop
- Uses MCP (Model Context Protocol) as the tool layer
- Works with local models via Ollama (no cloud dependency for inference)
- Is eventually deployable on **mobile/edge devices** (iOS/Android)
- Is built from scratch without LangChain or LangGraph

The inspiration project is Hermes Agent by Nous Research. It is a
self-improving agent with persistent memory, skill creation, cross-platform
gateways (Telegram, Discord, etc.), and support for 300+ models. This project
aims to build a similar harness, starting from the foundation and adding
features in phases.

---

## 2. What This Is Not

- **Not a LangChain wrapper.** LangChain was explicitly rejected because it
  assumes a server-side Python runtime, has a massive dependency tree, and
  cannot be ported to mobile. The agent loop here is hand-rolled.

- **Not a LangGraph project.** LangGraph is a graph execution runtime with a
  specific node/edge mental model. If your harness has different orchestration
  logic, you fight the framework rather than use it.

- **Not cloud-dependent.** All inference runs locally via Ollama. The
  architecture is model-agnostic so cloud providers can be added later without
  changing the loop.

---

## 3. High-Level Mental Model

The entire system is this loop:

```
User says something
    → History stores it
    → Loop sends history to Model
    → Model either:
        A) Replies with text → done, return to user
        B) Requests a tool → MCP runs it → result appended to history → repeat
```

Every file in the project handles exactly one part of that sentence.
Nothing more.

```
User types
    ↓
main.py              ← entry point, wires everything together
    ↓
core/loop.py         ← runs the Thought → Action → Observation cycle
    ├── core/history.py       ← the running list of messages
    ├── providers/local.py    ← translates to/from Ollama's API format
    ├── core/interrupts.py    ← handles Ctrl+C and mid-task redirects
    └── mcp/client.py         ← connects to MCP servers, dispatches tool calls
```

---

## 4. Project File Hierarchy

```
agent/
│
├── AGENT_ARCHITECTURE.md     ← this file
│
├── core/
│   ├── __init__.py
│   ├── loop.py               ← ReAct agent loop (the heart of the system)
│   ├── history.py            ← in-memory conversation history management
│   └── interrupts.py         ← Ctrl+C and mid-task redirect handling
│
├── providers/
│   ├── __init__.py
│   ├── base.py               ← Message/ToolCall/ModelResponse dataclasses
│   └── local.py              ← Ollama provider (OpenAI-compatible format)
│
├── mcp/
│   ├── __init__.py
│   └── client.py             ← MCP client: connects to servers, calls tools
│
├── config.py                 ← all runtime configuration in one place
└── main.py                   ← entry point: wires provider + MCP + loop
```

### Future directories (added in later phases)

```
agent/
├── memory/
│   ├── history_db.py         ← Phase 4: SQLite-backed persistent history
│   ├── memory.py             ← Phase 4: MEMORY.md persistent facts
│   └── search.py             ← Phase 4: FTS5 full-text session search
│
├── skills/
│   ├── creator.py            ← Phase 5: autonomous skill creation
│   └── improver.py           ← Phase 5: skill self-improvement
│
└── gateways/
    └── email.py              ← Phase 6: email gateway
```

---

## 5. Technology Decisions

### Local Model: Qwen3:14b or Gemma4:12b via Ollama

**Why Ollama:** Ollama wraps any local model and serves it via an
OpenAI-compatible REST API (`/v1/chat/completions`). This means Qwen, Gemma,
Llama, and any other Ollama-supported model all speak the same format to your
code. You never talk to the model directly — you talk to Ollama, and Ollama
handles the model's native format internally.

```
You (OpenAI format) → Ollama → Qwen   (Ollama handles internally)
You (OpenAI format) → Ollama → Gemma  (Ollama handles internally)
You (OpenAI format) → Ollama → Llama  (Ollama handles internally)
```

Switching from Qwen to Gemma is **one line change** — just the model name.
No code changes needed because Ollama normalizes the format.

**Why NOT LangChain/LangGraph for a local/mobile target:**
- Both are Python-heavy with massive dependency trees
- Neither has React Native, Swift, or Kotlin ports
- Both assume a server-side runtime — incompatible with mobile constraints
- The agent loop is ~50 lines of plain Python, simpler than any framework

**Recommended models (as of July 2026):**

| Model | Size on disk | RAM needed | Tool calling |
|-------|-------------|------------|--------------|
| `qwen3:14b` | ~9GB | ~12GB | Native, most stable per benchmarks |
| `gemma4:12b` | ~8GB | ~10GB | Native, dedicated special tokens |
| `gemma4:e4b` | ~3GB | ~4GB | Native, built for mobile/edge |

Before using any model, verify native tool calling support:
```bash
ollama show qwen3:14b    # look for "tools" in Capabilities
ollama show gemma4:12b   # look for "tools" in Capabilities
```

**Why NOT Qwen2.5 (original recommendation):** That was a mid-2025
recommendation made from training data. Qwen3 and Gemma4 both released in
early 2026 with significantly better tool calling reliability. Always search
current benchmarks rather than relying on cached model knowledge.

### Tool Layer: MCP (Model Context Protocol)

MCP standardizes how your app talks to tool servers. You write the MCP client
once. Any MCP server — filesystem, browser, database, git — just works without
custom integration code per tool.

**What MCP does and does not standardize:**

```
MCP standardizes:   how your app talks to tool servers
                    (transport, discovery, execution protocol)

MCP does NOT standardize: how you present tools to a model
                          (each model has its own JSON schema format)
```

This means you still need `_format_tools()` to translate MCP's `input_schema`
into whatever format the model expects (OpenAI's `parameters` field for Ollama).

**Hermes comparison:** Hermes uses MCP integration as a Phase 5 feature on top
of its own internal tool dispatch system. This project uses MCP as the tool
layer from day one, which is cleaner for a greenfield build.

---

## 6. Architecture: The Agent Loop

### What it is

The ReAct loop (Reasoning + Acting) is the pattern from a 2022 paper. The
cycle is: **Thought → Action → Observation → repeat until done.**

```
Turn 1:  Model thinks → decides to call a tool
Turn 2:  Tool runs → result appended to history → model thinks again
Turn N:  Model produces final answer → loop exits
```

### Our implementation vs. Hermes

**Our loop (`core/loop.py`):**
- ~50 lines of plain Python
- Calls `provider.complete()` each turn
- Dispatches tool calls via `mcp.call()`
- Appends results to history
- Checks for interrupts between turns
- Exits when `stop_reason == "end_turn"` or no tool calls

**Hermes loop (`run_agent.py` → refactored to `agent/` modules):**
- Was 16,083 lines, refactored to 3,821 lines across 14 modules
- Parallel tool execution via `ThreadPoolExecutor` (up to 8 workers)
- Automatic provider fallback on errors
- Context compression at 50% token usage
- Grace call when iteration budget (90 turns) is exhausted
- Promptware defense against injection attacks
- Streaming with `_interruptible_streaming_api_call()`

**Key difference:** Hermes runs tool calls in parallel when they target
independent paths. Our loop runs them sequentially. Parallel execution is
a Phase 3+ optimization.

### Why no LangChain/LangGraph

The loop is genuinely simple enough to write in any language. The framework
adds middleware (retries, rate limits, observability) but also adds:
- A specific mental model (graph nodes/edges) that may not match your use case
- Python-only runtime — incompatible with mobile
- Large dependency tree

A hand-rolled loop is naturally thin and portable. It's ~20 lines of logic
that can be translated to Swift or Kotlin when targeting mobile.

---

## 7. Architecture: Provider Layer

### The problem

Every model API has a different JSON shape for tool schemas and responses:

```python
# Anthropic format
{
    "name": "read_file",
    "description": "...",
    "input_schema": { ... }    # ← "input_schema"
}

# OpenAI / Ollama format
{
    "type": "function",
    "function": {
        "name": "read_file",
        "description": "...",
        "parameters": { ... }  # ← "parameters"
    }
}
```

Your loop must not know about these differences. It should only ever call
`provider.complete()` and get back a normalized `ModelResponse`.

### Our implementation: dataclasses + LocalProvider

`providers/base.py` defines three dataclasses — your internal language:

```python
Message       # one turn in the conversation (role + content)
ToolCall      # a model's request to run a tool (name + arguments)
ModelResponse # what comes back from the model (text + tool calls + stop reason)
```

`providers/local.py` is a single class that translates between your internal
format and Ollama's OpenAI-compatible format in both directions:

```
MCP tool schemas → _format_tools() → Ollama understands
Ollama response  → ModelResponse   → loop understands
```

### Hermes implementation: ProviderProfile + Transport layer

Hermes separates the problem into two concerns:

```
ProviderProfile (dataclass)     ← just config data, not behavior
    name, base_url, auth_type, api_mode
    loaded from plugins/model-providers/<name>/config files

ProviderTransport (ABC)         ← owns the actual API call behavior
    ├── ChatCompletionsTransport   ← OpenAI format (most providers)
    ├── AnthropicTransport         ← Anthropic Messages format
    ├── ResponsesApiTransport      ← OpenAI Responses API (GPT-5+)
    └── BedrockTransport           ← AWS Bedrock
```

**Why this is smarter at scale:** Most providers speak OpenAI format. So 300+
providers map to one transport (`ChatCompletionsTransport`) via config files.
Adding a new provider means writing a config card — not new Python code.

**Why we don't need it yet:** We have one provider (Ollama). One class is
enough. The Hermes pattern becomes worth adopting when you have multiple
providers with different API formats and don't want a new class per provider.

### Switching models in our system

Because Ollama normalizes all models to OpenAI format, switching is one line:

```python
# in main.py — this is the ONLY change needed to switch models
provider = LocalProvider(model="qwen3:14b", ...)   # Qwen
provider = LocalProvider(model="gemma4:12b", ...)  # Gemma
provider = LocalProvider(model="llama3.2", ...)    # Llama
```

Ollama is the translator. All three models natively speak different formats
internally, but Ollama wraps them all in OpenAI format before handing to you.

### ABC (Abstract Base Class) explained

ABC is a Python concept that forces any class inheriting from it to implement
specific methods. If a method is missing, Python refuses to instantiate the
class — catching the error at startup rather than mid-run.

```python
from abc import ABC, abstractmethod

class ProviderTransport(ABC):
    @abstractmethod
    async def complete(self, messages, tools, system):
        ...  # subclasses MUST implement this

class LocalProvider(ProviderTransport):
    # if you forget complete(), Python raises TypeError immediately
    async def complete(self, ...):
        ...
```

**For your current stage:** You don't need ABC. It's a guard rail for when you
have multiple providers and want Python to enforce they all implement the same
interface. A plain class for `LocalProvider` is fine until then.

---

## 8. Architecture: History Management

### What it does

History keeps the running list of messages that gets sent to the model on
every turn. This is what gives the model context — without it, every turn
would look like the first message.

### Our implementation: in-memory list

Simple, thin, intentionally minimal for Phase 1:

```python
class History:
    def __init__(self):
        self.messages: list[Message] = []  # plain Python list

    def append(self, msg: Message):
        self.messages.append(msg)          # called after every turn

    def clear(self):
        self.messages = []
```

Every time the loop calls `provider.complete()`, it passes `history.messages`
as the full conversation. That's the only job of history in Phase 1.

**What this means:** When the process exits, all history is gone. There is no
persistence, no search, no resume. This is intentional — persistence comes in
Phase 4.

### Hermes implementation: SQLite-backed session store

`hermes_state.py` is a 4,800-line SQLite database. Every message is
immediately written to disk. This is how Hermes supports:

- `/resume` — reload a past session
- Cross-platform continuity — start on CLI, continue on Telegram
- Session search — FTS5 full-text search across all past conversations
- Session branching — fork a conversation at any point

**Schema (simplified):**
```sql
sessions   -- one row per conversation (model, start time, token counts)
messages   -- every message, linked to a session by session_id
-- plus two FTS5 virtual tables for full-text search
```

**WAL mode** is enabled for concurrent readers. The implementation also
handles NFS filesystem fallbacks, malformed schema auto-repair, and write
retry with jitter.

**Migration path from our simple History:** Our `History` class stores
messages in a list. In Phase 4, you replace the list with SQLite reads/writes.
The loop itself doesn't change — it still calls `history.append()` and reads
`history.messages`. Only the storage backend changes.

---

## 9. Architecture: Tool Layer via MCP

### What MCP is

MCP (Model Context Protocol) is a protocol by Anthropic that standardizes how
applications talk to tool servers. Think of it as USB for tools — one standard
plug, any device.

```
Your app → [MCP protocol] → filesystem server
Your app → [MCP protocol] → browser server
Your app → [MCP protocol] → database server
```

Write the MCP client once. Every MCP server just works.

### What MCP does NOT do

MCP does not standardize how tools are presented to the model. That's still
per-provider. Your `_format_tools()` function translates MCP's `input_schema`
into Ollama's `parameters` — that translation always exists.

### Our implementation vs. dispatch.py

Our original plan had `core/dispatch.py` — a Python dictionary mapping tool
names to functions. MCP replaces this entirely:

```
Without MCP:  loop.py → dispatch.py → your Python functions
With MCP:     loop.py → mcp/client.py → MCP server → tools live there
```

`mcp/client.py` does three things:
1. Connect to MCP servers
2. Get the list of available tools from each server
3. Route tool calls to the right server and return results

Adding tools later requires zero code changes — just connect another MCP server:

```python
await mcp.connect("filesystem", "npx", ["-y", "@modelcontextprotocol/server-filesystem", "."])
await mcp.connect("brave-search", "npx", ["-y", "@modelcontextprotocol/server-brave-search"])
await mcp.connect("puppeteer",   "npx", ["-y", "@modelcontextprotocol/server-puppeteer"])
```

### The full data flow

```
1. main.py connects to MCP server
2. mcp/client.py calls mcp.list_tools() → gets tool schemas
3. schemas passed to provider.complete() so model knows what tools exist
4. Model responds: "I want to call list_directory with path='.'"
5. loop.py calls mcp.call("list_directory", {"path": "."})
6. mcp/client.py routes to filesystem server → gets result
7. Result appended to history → model called again
8. Model produces final answer
```

### Hermes comparison

Hermes has its own internal tool dispatch system and adds MCP as a Phase 5
extension on top. This project uses MCP from day one, which eliminates the
need for a separate dispatch layer entirely.

---

## 10. Architecture: Interrupt Handling

### What it does

Lets the user stop a running task (Ctrl+C) or redirect it mid-run (new message
while agent is working). Without this, a long-running task is uncontrollable.

### Our implementation

Hooks into Python's `SIGINT` signal. Sets a flag instead of crashing. The loop
checks the flag between tool calls.

```python
# two behaviors:
interrupt.check() → (True, None)       # Ctrl+C → stop cleanly
interrupt.check() → (True, "new task") # redirect → pivot to new task
```

### Hermes comparison

Hermes implements `_interruptible_streaming_api_call()` which handles
interrupts during streaming — mid-token, not just between tool calls. Also
handles graceful fallback to non-streaming on any error. More robust than our
implementation, but also more complex. Ours is sufficient for Phase 1.

---

## 11. Full Implementation Code

### `providers/base.py`

```python
from dataclasses import dataclass, field

# Message: one turn in the conversation
# role is "user", "assistant", or "tool"
@dataclass
class Message:
    role: str
    content: str | list
    tool_call_id: str | None = None   # only set for tool result messages
    tool_name: str | None = None      # only set for tool result messages

# ToolCall: the model's request to run a specific tool
@dataclass
class ToolCall:
    id: str           # unique ID assigned by the model, used to match results
    name: str         # which tool to call
    arguments: dict   # the arguments to pass

# ModelResponse: normalized response from any model provider
@dataclass
class ModelResponse:
    content: str                                    # text response (may be empty if tool calls)
    tool_calls: list[ToolCall] = field(default_factory=list)  # tool calls (may be empty)
    stop_reason: str = "end_turn"                  # "end_turn" | "tool_use" | "stop"
```

### `providers/local.py`

```python
import json
from openai import AsyncOpenAI
from providers.base import Message, ModelResponse, ToolCall

class LocalProvider:
    """
    Talks to any Ollama-served model using the OpenAI-compatible API.
    Translates between our internal Message/ModelResponse format and
    Ollama's JSON format in both directions.

    Switching models = changing the model name string. Nothing else.
    All Ollama models speak the same OpenAI format regardless of their
    native internal format (Qwen, Gemma, Llama, etc.).
    """

    def __init__(self, model: str = "qwen3:14b", base_url: str = "http://localhost:11434/v1"):
        # OpenAI client pointed at Ollama's local server
        # api_key is required by the client library but ignored by Ollama
        self.client = AsyncOpenAI(base_url=base_url, api_key="ollama")
        self.model = model

    async def complete(self, messages: list[Message], tools: list[dict], system: str) -> ModelResponse:
        """
        Send a full conversation to the model and get a response.
        tools is a list of MCP tool schemas, already formatted for OpenAI.
        """
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=self._format_messages(messages, system),
            tools=self._format_tools(tools) if tools else None,
        )

        msg = response.choices[0].message
        tool_calls = []

        # Parse tool calls from Ollama's response format into our ToolCall dataclass
        if msg.tool_calls:
            tool_calls = [
                ToolCall(
                    id=tc.id,
                    name=tc.function.name,
                    # Ollama sends arguments as a JSON string, not a dict — parse it
                    arguments=json.loads(tc.function.arguments)
                )
                for tc in msg.tool_calls
            ]

        return ModelResponse(
            content=msg.content or "",
            tool_calls=tool_calls,
            stop_reason=response.choices[0].finish_reason,
        )

    def format_tool_result(self, tool_call_id: str, tool_name: str, result: str) -> Message:
        """
        Wrap a tool's output in a Message so it can be appended to history.
        The tool_call_id links this result back to the model's original request.
        """
        return Message(
            role="tool",
            content=result,
            tool_call_id=tool_call_id,
            tool_name=tool_name,
        )

    def _format_messages(self, messages: list[Message], system: str) -> list[dict]:
        """
        Convert our internal Message objects to Ollama's expected JSON format.
        System prompt goes first as a system role message.
        """
        out = [{"role": "system", "content": system}]
        for m in messages:
            if m.role == "tool":
                # Tool results need tool_call_id to link back to the model's request
                out.append({
                    "role": "tool",
                    "content": m.content,
                    "tool_call_id": m.tool_call_id,
                })
            else:
                out.append({"role": m.role, "content": m.content})
        return out

    def _format_tools(self, tools: list[dict]) -> list[dict]:
        """
        Translate MCP tool schemas into OpenAI tool format.
        MCP uses "input_schema", OpenAI/Ollama uses "parameters" — that's the
        only real difference. Everything else is restructuring.
        """
        return [
            {
                "type": "function",
                "function": {
                    "name": t["name"],
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {}),  # ← the key translation
                }
            }
            for t in tools
        ]
```

### `core/history.py`

```python
from providers.base import Message

class History:
    """
    Keeps the running list of messages for the current session.
    In-memory only — Phase 1. No persistence across restarts.

    Phase 4 upgrade path: replace self.messages (a list) with SQLite
    reads/writes. The loop calls the same append() and reads the same
    self.messages — only the storage backend changes.

    Hermes equivalent: hermes_state.py (4,800 lines of SQLite with FTS5
    full-text search, WAL mode, session branching, write retry with jitter).
    """

    def __init__(self):
        self.messages: list[Message] = []

    def append(self, msg: Message):
        """Called by the loop after every turn — user message, assistant
        response, and tool results all go through here."""
        self.messages.append(msg)

    def clear(self):
        """Reset for a new conversation (/new command in Phase 2)."""
        self.messages = []
```

### `core/interrupts.py`

```python
import signal

class InterruptHandler:
    """
    Lets the user stop a running task (Ctrl+C) or redirect it mid-run.
    Hooks into Python's SIGINT signal — sets a flag instead of crashing.
    The loop checks this flag between tool calls.

    Hermes equivalent: _interruptible_streaming_api_call() which handles
    interrupts during streaming (mid-token). Ours only interrupts between
    tool calls, which is sufficient for Phase 1.
    """

    def __init__(self):
        self._interrupted = False
        self._redirect: str | None = None

    def setup(self):
        """Call once at startup to hook Ctrl+C."""
        signal.signal(signal.SIGINT, self._handle_signal)

    def _handle_signal(self, *_):
        """Called by the OS when user presses Ctrl+C."""
        self._interrupted = True

    def check(self) -> tuple[bool, str | None]:
        """
        Called by the loop between tool calls.
        Returns (was_interrupted, redirect_message).
        Resets flags after reading so the loop only handles it once.
        """
        was = self._interrupted
        redirect = self._redirect
        self._interrupted = False
        self._redirect = None
        return was, redirect

    def redirect(self, new_task: str):
        """
        Called when user sends a new message mid-run.
        Sets interrupted=True AND stores the new task so the loop
        pivots rather than just stopping.
        """
        self._redirect = new_task
        self._interrupted = True

# Singleton — imported everywhere as `from core.interrupts import interrupt`
interrupt = InterruptHandler()
```

### `core/loop.py`

```python
from providers.local import LocalProvider
from providers.base import Message
from core.history import History
from core.interrupts import interrupt
from mcp import ClientSession

# Maximum tool call turns before giving up
# Hermes default is 90. We use 20 for now — increase as tasks get more complex.
MAX_TURNS = 20

async def run(
    user_input: str,
    provider: LocalProvider,
    mcp: ClientSession,         # the active MCP session
    mcp_tools: list[dict],      # tool schemas from MCP, already fetched
    history: History,
    system: str,
) -> str:
    """
    The ReAct loop. Runs until:
    - Model produces a final text response (no tool calls)
    - User interrupts with Ctrl+C
    - MAX_TURNS is reached

    Flow per turn:
    1. Check for interrupt
    2. Call the model with full history + tool schemas
    3. If no tool calls → return the text response
    4. If tool calls → dispatch via MCP → append results → repeat
    """

    # Add the user's message to history before the first model call
    history.append(Message(role="user", content=user_input))

    for turn in range(MAX_TURNS):
        print(f"\n[turn {turn + 1}]")

        # Check for Ctrl+C or redirect before each model call
        # This is the interrupt window — the only point where the user
        # can safely stop or redirect without corrupting history
        interrupted, redirect = interrupt.check()
        if interrupted:
            if redirect:
                # User sent a new task — pivot to it instead of stopping
                history.append(Message(role="user", content=redirect))
                # Don't return — continue the loop with the new direction
            else:
                # Plain Ctrl+C — stop cleanly
                return "[Interrupted]"

        # Call the model with the full conversation history
        response = await provider.complete(
            messages=history.messages,
            tools=mcp_tools,
            system=system,
        )

        # No tool calls — model is done, return its text response
        if not response.tool_calls:
            history.append(Message(role="assistant", content=response.content))
            return response.content

        # Model wants to call tools — show thinking if any
        if response.content:
            print(f"Thinking: {response.content}")

        # Append assistant's intent to history before dispatching tools
        # This is required by the OpenAI message format — the assistant
        # turn must appear before the tool results that follow it
        history.append(Message(role="assistant", content=response.content))

        # Dispatch each tool call via MCP
        for tc in response.tool_calls:
            print(f"→ calling: {tc.name}({tc.arguments})")

            try:
                # MCP handles finding the right server and running the tool
                result = await mcp.call_tool(tc.name, tc.arguments)
                tool_output = result.content[0].text if result.content else ""
            except Exception as e:
                # Tool errors go back to the model as results, not crashes
                tool_output = f"Error: {e}"

            # Show a preview of the result for debugging
            print(f"← result: {tool_output[:200]}")

            # Append tool result to history so model sees it next turn
            history.append(
                provider.format_tool_result(tc.id, tc.name, tool_output)
            )

    # Should rarely hit this — means the task is genuinely complex
    # Hermes handles this with a grace call asking the model to wrap up
    return "Reached max turns without finishing."
```

### `mcp/client.py`

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

class MCPClient:
    """
    Manages connections to MCP servers.
    Does three things:
    1. Connect to servers (each server is a separate process)
    2. Collect tool schemas from all connected servers
    3. Route tool calls to the right server

    Adding a new tool capability = connecting a new MCP server.
    No changes to loop.py, history.py, or providers/local.py required.

    Hermes equivalent: Hermes has its own internal dispatch system and adds
    MCP as a Phase 5 extension. We use MCP from day one, eliminating the
    need for a separate dispatch layer.
    """

    def __init__(self):
        self.sessions: dict[str, ClientSession] = {}  # server_name → session
        self._tools: list[dict] = []                  # all tools from all servers

    async def connect(self, name: str, command: str, args: list[str] = []):
        """
        Connect to one MCP server and register its tools.
        name is just a label — used internally to route calls.
        command + args is how to start the server process.
        """
        params = StdioServerParameters(command=command, args=args)
        read, write = await stdio_client(params)
        session = ClientSession(read, write)
        await session.initialize()
        self.sessions[name] = session

        # Get this server's tools and add to master list
        tools = await session.list_tools()
        for tool in tools.tools:
            self._tools.append({
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
                "_server": name,    # remember which server owns this tool
            })

    def schemas(self) -> list[dict]:
        """
        Return all tool schemas to pass to the model.
        Strips the internal _server key — the model doesn't need to know
        which server a tool lives on.
        """
        return [
            {k: v for k, v in t.items() if k != "_server"}
            for t in self._tools
        ]

    async def call(self, tool_name: str, arguments: dict) -> str:
        """
        Find which server owns this tool and call it.
        The loop calls this — it doesn't need to know which server to use.
        """
        # Look up which server registered this tool
        server_name = next(
            (t["_server"] for t in self._tools if t["name"] == tool_name),
            None
        )
        if not server_name:
            return f"Error: tool '{tool_name}' not found in any connected MCP server"

        session = self.sessions[server_name]

        try:
            result = await session.call_tool(tool_name, arguments)
            return result.content[0].text if result.content else ""
        except Exception as e:
            return f"Error calling {tool_name}: {e}"

    async def disconnect_all(self):
        """Clean up all server connections on exit."""
        for session in self.sessions.values():
            await session.__aexit__(None, None, None)
```

### `config.py`

```python
import os
from dataclasses import dataclass

@dataclass
class Config:
    """
    All runtime configuration in one place.
    Change the model by changing local_model.
    Change the provider by changing provider (future — when adding cloud).
    """

    # Model settings
    provider: str = "local"                              # "local" | "anthropic" | "openai"
    local_model: str = "qwen3:14b"                       # any ollama model name
    local_base_url: str = "http://localhost:11434/v1"    # ollama default

    # Future cloud provider keys (unused in Phase 1)
    anthropic_api_key: str = os.getenv("ANTHROPIC_API_KEY", "")
    openai_api_key: str = os.getenv("OPENAI_API_KEY", "")

    # Agent behavior
    system_prompt: str = "You are a helpful agent. Use tools when needed."
    max_turns: int = 20
```

### `main.py`

```python
import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from providers.local import LocalProvider
from core.history import History
from core.interrupts import interrupt
from core.loop import run
from config import Config

async def main():
    cfg = Config()

    # Build the provider — swap cfg.local_model to switch models
    provider = LocalProvider(
        model=cfg.local_model,
        base_url=cfg.local_base_url,
    )

    history = History()
    interrupt.setup()   # hook Ctrl+C

    # Connect to MCP servers
    # Add more servers here as you add capabilities in Phase 2+
    server_params = StdioServerParameters(
        command="npx",
        args=["-y", "@modelcontextprotocol/server-filesystem", "."],
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as mcp:
            await mcp.initialize()

            # Fetch tool schemas once at startup
            # These get passed to the model on every turn
            tools_response = await mcp.list_tools()
            mcp_tools = [
                {
                    "name": t.name,
                    "description": t.description,
                    "input_schema": t.inputSchema,
                }
                for t in tools_response.tools
            ]

            print(f"Agent ready [{cfg.local_model}]")
            print(f"{len(mcp_tools)} tools available: {[t['name'] for t in mcp_tools]}")
            print("Ctrl+C to interrupt\n")

            # Main chat loop
            while True:
                try:
                    user_input = input("You: ").strip()
                except (EOFError, KeyboardInterrupt):
                    print("\nBye.")
                    break

                if not user_input:
                    continue

                response = await run(
                    user_input=user_input,
                    provider=provider,
                    mcp=mcp,
                    mcp_tools=mcp_tools,
                    history=history,
                    system=cfg.system_prompt,
                )

                print(f"\nAgent: {response}\n")

if __name__ == "__main__":
    asyncio.run(main())
```

---

## 12. Build Roadmap

Features selected from the Hermes Agent feature set, ordered by dependency.

### Phase 1 — Foundation (Weeks 1–3) ✓ CURRENT PHASE
Everything else depends on this. Get it solid before adding anything.

- Logging system
- Model-agnostic harness (provider abstraction)
- Agent loop (ReAct cycle)
- Context/history management
- Tool dispatch via MCP
- Streaming output
- Interrupt & redirect
- Provider switching (model name only for now)

### Phase 2 — Core Tools (Weeks 4–6)
First real capabilities. Add in order of complexity.

- Shell execution
- File read/write
- Web search
- Local terminal backend
- Toolset system (group tools into named sets)
- Slash commands (/new, /retry, /undo)
- Personalities (named system prompt presets)

### Phase 3 — Execution Backends + Rich Tools (Weeks 7–10)
Sandboxing and media. Docker before SSH before Modal.

- Docker backend (sandboxed execution)
- SSH backend (remote execution)
- Modal backend (serverless — most relevant for mobile)
- Web browser via cloud
- Image generation
- Text-to-speech
- Voice memo transcription

### Phase 4 — Memory Layer (Weeks 11–14)
The agent gets to know you. Build in listed order — each feeds the next.

- Context compression (required before sessions get long)
- Persistent memory (MEMORY.md — facts across sessions)
- Context files (project-level CONTEXT.md)
- Memory nudges
- Session search (FTS5 full-text)
- User modeling (USER.md — deeper profile)

### Phase 5 — Skills & Intelligence (Weeks 15–19)
The agent gets smarter over time. Skills depend on memory.

- Skill creation (agent creates reusable skills)
- Skill self-improvement (skills refine during use)
- Skills Hub (community skill sharing)
- MCP integration (expand to more MCP servers)

### Phase 6 — Distribution (Weeks 20–24)
Ship it. Locks in interfaces — do last.

- Email gateway
- Self-update command
- Homebrew packaging

---

## 13. Key Concepts Glossary

**ReAct** — Reasoning + Acting. A 2022 prompting pattern where the model
alternates between thinking (Thought), deciding on an action (Action), and
observing the result (Observation) until the task is done.

**MCP (Model Context Protocol)** — A protocol by Anthropic that standardizes
how applications talk to tool servers. Your app writes one MCP client; any MCP
server just works. Does not standardize how tools are presented to models —
that translation is still per-provider.

**Ollama** — A local model server that wraps any supported model (Qwen, Gemma,
Llama, etc.) and serves it via an OpenAI-compatible REST API. All models speak
the same format through Ollama regardless of their native internal format.

**OpenAI format** — The JSON schema format used by OpenAI's API for tool
definitions and tool call responses. Most local model servers (Ollama, vLLM,
llama.cpp) adopted this as a de facto standard.

**ABC (Abstract Base Class)** — A Python concept that forces subclasses to
implement specific methods or Python refuses to instantiate them. Guards
against missing implementations at startup rather than mid-run. Not needed
until you have multiple provider classes.

**ProviderProfile** — Hermes's pattern for separating provider config (what a
provider is — URL, auth, format) from provider behavior (how to talk to it).
Allows adding new providers via config files instead of new code.

**Transport** — Hermes's term for a class that owns the actual API call to a
model. One transport handles many providers if they share the same API format.
`ChatCompletionsTransport` handles 300+ providers because most speak OpenAI
format.

**FTS5** — SQLite's Full-Text Search extension (version 5). Used by Hermes
for fast session search across all past conversations. Relevant in Phase 4.

**WAL mode** — Write-Ahead Logging. A SQLite setting that allows concurrent
readers while a write is in progress. Used by Hermes's `hermes_state.py` for
reliability. Relevant in Phase 4.

**Modal** — A serverless compute platform. Relevant for mobile architecture
because it hibernates when idle and wakes on demand — no always-on server
needed. The most mobile-compatible backend in Phase 3.

**GGUF** — A file format for quantized model weights. Used by llama.cpp and
Ollama. Quantized models (Q4, Q5) trade small quality losses for dramatically
smaller file sizes and memory usage — critical for on-device inference.

---

*Last updated: July 2026. Generated from a full architecture discussion
covering the ReAct pattern, MCP integration, local model selection,
provider abstraction, history management, and comparison to Hermes Agent
by NousResearch.*
