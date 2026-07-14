# Learning Agent Architecture — Notes from Studying Hermes Agent

Source: [github.com/NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), cloned and read directly (README.md, AGENTS.md, `tools/registry.py`, `model_tools.py`, `run_agent.py`, `toolsets.py`) on 2026-07-07.

---

## Part 1 — What Hermes Agent actually is

It's not a small "agent harness" — it's a full product built around one. `run_agent.py` (the core loop) is ~6-12k LOC, `cli.py` is ~11-16k LOC, and there are ~900 test files. Most of the repo is *product surface* around a fairly small core:

- **Core harness** (the part actually worth studying): `run_agent.py` (the `AIAgent` loop), `model_tools.py` (tool dispatch), `tools/registry.py` (tool registration), `toolsets.py` (which tools are exposed when).
- **Everything else** is delivery surface: a TUI (Ink/React over JSON-RPC), an Electron desktop app, a messaging gateway with ~20 platform adapters, a plugin system, a memory-provider system, a skills system, a cron scheduler, an ACP adapter for editors, delegation/subagents, batch trajectory generation for training data.

They're explicit about this split themselves — from their own `AGENTS.md`:

> "The core is a narrow waist; capability lives at the edges... every model tool we add is sent on every API call, so the bar for a new core tool is high."

## Part 2 — The actual mechanics (the part worth copying)

**1. The loop itself** is a synchronous while-loop:

```python
while api_call_count < max_iterations and budget.remaining > 0:
    response = client.chat.completions.create(model=model, messages=messages, tools=tool_schemas)
    if response.tool_calls:
        for call in response.tool_calls:
            result = handle_function_call(call.name, call.args)
            messages.append(tool_result_message(result))
    else:
        return response.content
```

Everything else in `run_agent.py`'s 6-12k lines is edge cases around this: interrupt handling, budget/iteration tracking, context compression, provider adapters, credential pooling.

**2. Tool registration is a self-registering plugin pattern.** Each file in `tools/` calls `registry.register(name, toolset, schema, handler, check_fn, requires_env)` at import time. `tools/registry.py` has zero dependencies (imported by everyone); `model_tools.py` auto-discovers any `tools/*.py` with a top-level `registry.register()` call via AST parsing — no manual import list to maintain. A `check_fn` gates availability (e.g. only expose the Docker tool if Docker is actually running), with a TTL + grace-period cache so a flaky probe doesn't silently strip a whole toolset mid-session.

**3. Toolsets are named bundles** (`toolsets.py`) — `terminal`, `file`, `browser`, `memory`, etc. Each platform (CLI, Telegram, Discord...) picks a base toolset. This is how they keep the *per-model* tool list small even though 100+ tools exist in the codebase.

**4. Everything returns JSON strings.** Tool handlers always return `json.dumps(...)`; `registry.dispatch()` wraps every call in try/except and sanitizes errors so exception text can't smuggle prompt-injection-like framing tokens back into the model's context.

## Part 3 — Design invariants they treat as sacred

From `AGENTS.md`, stated as the two things that "shape almost every design decision":

- **Prompt caching is sacred.** Providers cache a shared prefix of your message history. Anything that mutates past messages, swaps tool schemas mid-conversation, or rebuilds the system prompt invalidates the cache and multiplies cost. Design your message/tool-schema mutation points around this from day one — retrofitting it later is painful.
- **Strict message role alternation** — never two same-role messages in a row, no synthetic user messages injected mid-loop. This trips people up constantly when adding features like "nudges" or corrections.
- **The footprint ladder** for new capability: extend existing code → CLI command + skill → gated tool → plugin → MCP server → new core tool (last resort). A genuinely good discipline for keeping a harness from turning into spaghetti as you add capabilities.

## Part 4 — Recommended build order

1. **Build the bare loop first** — OpenAI-format messages, one provider, 3-4 tools (read_file, write_file, terminal/shell, maybe web_search). Get the while-loop + tool-call dispatch working end to end. A day or two of work, not a big lift.
2. **Add the registry pattern early** — even with 4 tools, having `register()`/`dispatch()`/schema-generation separated out saves you from a giant if/elif tool dispatcher later.
3. **Get provider-agnostic** — study how different providers' function-calling formats get normalized into one internal shape (`agent/anthropic_adapter.py`, `agent/bedrock_adapter.py`, `agent/gemini_native_adapter.py` in Hermes). This is genuinely the fiddly part — each provider has different tool-call/streaming/reasoning-content conventions.
4. **Add persistence** — a SQLite session store so conversations survive restarts.
5. **Decide what you actually need beyond that** — memory/skills/delegation/gateway are all optional and each is its own subsystem. Don't build them speculatively; add them when you have a concrete use case (this is literally Hermes's own contribution rubric — "speculative infrastructure" is explicitly rejected in their own project).

Treat Hermes as a *reference*, not a template to reimplement wholesale — clone the loop + registry pattern, skip the gateway/TUI/plugin-marketplace machinery unless you specifically want a multi-platform product rather than a working harness.

---

## Part 5 — Elements of an agent harness, and where to learn each one

An "agent harness" is the scaffolding around an LLM that turns a single request/response call into a looping, tool-using, stateful system. Below are the load-bearing concepts, roughly in the order you'll need them, each with what it is, why it exists, and where to actually learn it.

### 1. The agent loop (orchestration loop / ReAct loop)

**What it is:** The core `while` loop that repeatedly calls the model, checks if it asked for a tool, executes the tool, feeds the result back, and repeats until the model returns a plain-text answer (or a budget/iteration cap is hit).

**Why it exists:** A single LLM call can't take actions or see results — the loop is what turns "predict next tokens" into "accomplish a task."

**Where to learn it:**
- The original [ReAct paper](https://arxiv.org/abs/2210.03629) (Yao et al.) — "Reasoning + Acting," the paper that named this pattern.
- [Anthropic's "Building Effective Agents"](https://www.anthropic.com/research/building-effective-agents) — practical, opinionated, short.
- Read `run_agent.py`'s loop directly (it's ~15 lines at its core, as shown above) — often faster than reading about it in the abstract.

### 2. Function/tool calling (structured output for actions)

**What it is:** The model doesn't call functions itself — it outputs a structured request (JSON: tool name + arguments) that *you* parse and execute, then you feed the result back as a message.

**Why it exists:** LLMs generate text; someone has to bridge "the model wants to read a file" to an actual file read. Tool calling is the standardized way models signal that intent in a parseable format instead of you regex-ing free text.

**Where to learn it:**
- [Anthropic tool use docs](https://docs.anthropic.com/en/docs/build-with-claude/tool-use) — schema format, multi-tool calls, forced tool choice.
- [OpenAI function calling guide](https://platform.openai.com/docs/guides/function-calling) — the format Hermes's loop is built around (`response.tool_calls`).
- JSON Schema itself — [json-schema.org/learn](https://json-schema.org/learn/getting-started-step-by-step) — every tool's `parameters` field is a JSON Schema object; you need to know this format regardless of provider.

### 3. The registry pattern (the thing you asked about)

**What it is:** A general software design pattern where, instead of hand-maintaining a big list/dictionary of "things that exist" (tools, plugins, handlers, routes), each unit *registers itself* into a shared, central object at load/import time. Code that needs to know "what tools exist" queries the registry rather than importing every tool file by name.

Concretely in Hermes:
```python
# tools/read_file.py
from tools.registry import registry

def read_file_handler(args, **kwargs):
    return json.dumps({"content": open(args["path"]).read()})

registry.register(
    name="read_file",
    toolset="file",
    schema={...},        # JSON Schema describing the function
    handler=read_file_handler,
    check_fn=None,        # optional: gate availability
)
```
`model_tools.py` never has to know `read_file` exists by name — it asks the registry for "all tools in the `file` toolset" and gets schemas + callable handlers back. Adding a new tool means adding a new file, not editing a central dispatcher.

**Why it exists:** Without it, you end up with a giant `if tool_name == "read_file": ... elif tool_name == "write_file": ...` chain that every new tool has to be added to in multiple places (schema list, dispatcher, docs). The registry pattern decouples "declaring a tool" from "using a tool" — new capabilities are additive, not edits to shared code. This is the single most important structural idea for keeping a harness maintainable past ~10 tools.

**Where to learn it:**
- This is a classic **Registry** / **Plugin architecture** pattern, related to but distinct from **Dependency Injection**. It doesn't have one canonical academic paper — it's a software engineering pattern, best learned from real code and general design-pattern resources:
  - [Refactoring Guru — Design Patterns](https://refactoring.guru/design-patterns) — not registry-specific, but teaches the vocabulary (Factory, Strategy, Observer) that registries are built from.
  - Look at how **pytest fixtures/plugins**, **Flask's `@app.route`**, or **Django's app registry** work — all are registry-pattern examples in mainstream frameworks you can install and inspect locally.
  - Simplest way to internalize it: read `tools/registry.py` in Hermes directly (766 lines, but the core — `register()`, `get_definitions()`, `dispatch()` — is under 100 lines). It's a very clean, real-world instance.

### 4. Tool schemas / JSON Schema for parameters

**What it is:** A structured description (name, description, parameter types/constraints) of each tool that gets sent to the model on every API call so it knows what's callable and with what arguments.

**Why it exists:** The model can't infer a function's signature — it needs an explicit contract, and that contract must be machine-parseable so the provider's API can validate/format the model's tool-call output.

**Where to learn it:** Same links as #2 (Anthropic/OpenAI tool-use docs) plus [json-schema.org](https://json-schema.org/) directly for the schema spec itself.

### 5. Message history / conversation state format

**What it is:** The list of `{role, content}` messages (system/user/assistant/tool) that gets replayed on every API call. Tool calls and their results get appended as their own message entries with a `role: "tool"` (or provider-specific equivalent).

**Why it exists:** LLM APIs are stateless — the entire conversation, including every past tool call and result, has to be resent every turn. How you structure and mutate this list *is* your state management.

**Where to learn it:**
- [OpenAI Chat Completions message format docs](https://platform.openai.com/docs/guides/text-generation) — canonical role/content shape.
- [Anthropic Messages API docs](https://docs.anthropic.com/en/api/messages) — slightly different shape (tool_use/tool_result content blocks instead of a separate role).
- Read Hermes's `AGENTS.md` note on "strict message role alternation" — a real constraint you'll hit once you start adding features.

### 6. Prompt caching

**What it is:** Providers (Anthropic, OpenAI, others) let you mark a prefix of your message list as cacheable so repeated calls with the same prefix are cheaper and faster. Since agent loops resend the whole history every turn, an unchanging system prompt + early messages is exactly what caching targets.

**Why it exists:** Without it, a 50-turn conversation costs roughly turn² in tokens processed. Caching makes long conversations economically viable.

**Where to learn it:**
- [Anthropic prompt caching docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) — cache breakpoints, TTL, cost model.
- [OpenAI prompt caching docs](https://platform.openai.com/docs/guides/prompt-caching) — automatic, but same underlying idea (stable prefixes get discounted).
- Practical rule of thumb (from Hermes's own `AGENTS.md`): never mutate past messages, never swap tool schemas mid-conversation, keep the system prompt byte-stable for the life of a conversation.

### 7. Provider abstraction / adapter pattern

**What it is:** A layer that normalizes different LLM providers' request/response formats (tool-call shape, streaming events, reasoning/thinking content) into one internal representation, so the rest of your harness doesn't care which provider is active.

**Why it exists:** Anthropic, OpenAI, Gemini, and Bedrock all format tool calls, streaming chunks, and reasoning content differently. Without an adapter layer, supporting a second provider means forking your whole loop.

**Where to learn it:**
- This is the classic **Adapter design pattern** applied to APIs — [Refactoring Guru's Adapter pattern page](https://refactoring.guru/design-patterns/adapter) for the general concept.
- Read multiple providers' docs side by side and diff the shapes yourself: [Anthropic Messages API](https://docs.anthropic.com/en/api/messages) vs [OpenAI Chat Completions](https://platform.openai.com/docs/api-reference/chat) — you'll immediately see why an adapter layer is needed.
- Libraries like [LiteLLM](https://docs.litellm.ai/) exist specifically to solve this — worth reading their source for a working example, even if you don't depend on it directly (Hermes's own dependency-pinning policy notes they got burned by a litellm supply-chain compromise, so treat it as a reference, not necessarily a dependency).

### 8. Budget / iteration control

**What it is:** Hard caps (`max_iterations`, token/cost budgets, wall-clock timeouts) that stop the loop from running forever — e.g. a model stuck in a tool-call retry cycle.

**Why it exists:** Agent loops are open-ended by default. Without a cap, a bug or an unhelpful model response can loop indefinitely and burn API spend.

**Where to learn it:** No single canonical resource — this is mostly engineering judgment. Look at how Hermes exposes `max_iterations` and an `iteration_budget` object, and think about what "done" and "stuck" look like for your use case (cost cap? turn cap? both?).

### 9. Persistence / session store

**What it is:** Saving conversation state (messages, session metadata) to disk/DB so a conversation can resume after a process restart, and so you can search past conversations.

**Why it exists:** In-memory-only state means every restart loses history — fine for a demo, not for anything you'd actually use daily.

**Where to learn it:**
- [SQLite docs](https://www.sqlite.org/docs.html) — Hermes uses SQLite with FTS5 (full-text search) for session search; it's the simplest durable store for a single-user/local harness.
- General concept: this is just "persist an append-only log + queryable index" — any embedded DB (SQLite, DuckDB) works; no exotic pattern needed.

### 10. Error handling / sanitization at the tool boundary

**What it is:** Every tool call is wrapped so exceptions become structured `{"error": "..."}` JSON instead of raw stack traces, and error text is sanitized before being fed back to the model (so it can't contain injection-like framing tokens, e.g. fake `<system>` tags).

**Why it exists:** Tool output becomes part of the model's context. If a tool's raw error text (or, worse, a malicious file/webpage a tool reads) can contain text that looks like a system instruction, you've opened a prompt-injection vector.

**Where to learn it:**
- [OWASP LLM Top 10 — LLM01: Prompt Injection](https://owasp.org/www-project-top-10-for-large-language-model-applications/) — the security framing for why this matters.
- [Simon Willison's writing on prompt injection](https://simonwillison.net/series/prompt-injection/) — the most practical, concrete treatment of this problem, written specifically about agent/tool-using systems.

### 11. (Optional, once the above is solid) Memory, skills, delegation/subagents, multi-platform gateways

These are all *product* layers, not core-harness requirements. Each is its own subsystem with its own concepts (vector/dialectic memory providers, procedural "skill" files, subagent spawning with isolated context, multi-platform message adapters). Don't build these until you have a concrete need — Hermes's own contribution policy explicitly rejects "speculative infrastructure" for the same reason. When you do need one, treat it as a separate research task rather than bundling it into "learn the harness basics."

---

## Suggested learning path (condensed)

1. Read Anthropic's "Building Effective Agents" (30 min) — the conceptual frame for the whole loop.
2. Read the OpenAI function-calling guide + Anthropic tool-use guide back to back (1 hr) — you'll internalize the schema format and see the format differences that make #7 (adapters) necessary.
3. Build the bare loop + 2-3 tools without a registry first — feel the pain of a growing if/elif dispatcher.
4. Refactor into a registry pattern once it hurts — you'll understand *why* it exists instead of just copying it.
5. Add prompt caching once you have a real multi-turn conversation to measure cost on.
6. Add persistence (SQLite) once you're tired of losing history on restart.
7. Read Simon Willison's prompt injection series before you connect any tool that reads untrusted external content (web pages, emails, files from other users).
