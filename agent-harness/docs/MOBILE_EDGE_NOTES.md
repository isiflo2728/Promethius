# Mobile & Edge Agent Notes

> **Purpose:** Reference notes covering mobile/edge agent architecture,
> Apple Foundation Models, on-device tool calling limitations, and how
> the Python agent harness built in this project maps to mobile platforms.
> Starts from the DAEX repo analysis. Read alongside AGENT_ARCHITECTURE.md.

---

## Table of Contents

1. [DAEX Repo Analysis](#1-daex-repo-analysis)
2. [Tool Calling Limitations on Edge](#2-tool-calling-limitations-on-edge)
3. [Edge Agent Frameworks](#3-edge-agent-frameworks)
4. [Apple Foundation Models](#4-apple-foundation-models)
5. [What Transfers from Python to Mobile](#5-what-transfers-from-python-to-mobile)
6. [The Three Paths to Mobile](#6-the-three-paths-to-mobile)
7. [Model Recommendations for Mobile](#7-model-recommendations-for-mobile)

---

## 1. DAEX Repo Analysis

**Repo:** https://github.com/DIIZZYFPS/DAEX

DAEX is an Android-native on-device agent written entirely in Kotlin with
Jetpack Compose. It implements tool calling, but in a limited hardcoded form.

### What DAEX implements

**Sandbox Tool Calling** — a secure native capability framework allowing the
model to check battery, check storage status, get system time, and launch apps
under sandbox controls. These are hardcoded native Android capabilities. The
model can call them, but you cannot add new tools without writing new Kotlin
code. There is no MCP, no dynamic tool registration, no external servers.

**Stack:**
- LiteRT for on-device inference with Vulkan GPU and NPU acceleration
- ObjectBox vector database for offline RAG
- Core memory — a localized fact logging engine that builds a memory profile
  from conversations (similar to Hermes's MEMORY.md)
- Reasoning visualizer — collapsible thinking block logs, real-time tok/s display
- Targets Gemma 2B and Qwen 1.5B — appropriate sizes for Android
- 100% on-device, no cloud dependency

### DAEX vs. this project

| | DAEX | This project |
|---|---|---|
| Tool calling | Hardcoded sandbox tools | MCP — any server, dynamic |
| Platform | Android only | Desktop → mobile |
| Inference | LiteRT on-device | Ollama locally, ExecuTorch eventually |
| Memory | Core memory (conversation facts) | MEMORY.md (Phase 4) |
| RAG | ObjectBox vector DB | Not yet planned |
| Language | Kotlin / Jetpack Compose | Python → port later |
| Tool extensibility | New tools = new Kotlin code | New tools = new MCP server |

**Assessment:** DAEX is ahead on the Android execution layer — LiteRT with
Vulkan/NPU acceleration is production-grade mobile inference. But it's behind
on the tool layer — hardcoded tools with no way to extend them without
modifying the app. The MCP approach in this project is architecturally better
for extensibility. DAEX's LiteRT integration is worth studying closely when
targeting mobile in Phase 3.

---

## 2. Tool Calling Limitations on Edge

These are the five core limitations of tool calling on mobile/edge devices.
Understanding them shapes every architectural decision for the mobile port.

### Limitation 1 — The model size vs. reliability cliff

Small models can technically return tool calls, but their ability to correctly
interpret JSON Schema degrades sharply below 7B parameters.

**What specifically breaks at small sizes:**
- Function descriptions longer than 2-3 lines — model misses parameters
- Multiple tools in the request — model picks the first, ignores the rest
- Non-standard query phrasing — model responds with text instead of a call
- Parameters with complex types (enum, nested object) — invalid JSON output

**The practical cliff:**

```
14B+   →  reliable multi-step tool chains
7-8B   →  reliable single tool calls, struggles with chains
3-4B   →  unreliable unless specifically fine-tuned for tool use
1-2B   →  intent classification only, not real tool calling
```

**Exception:** `gemma4:e2b` (2B) is the only sub-4B model that calls tools
more or less reliably in 2026, due to native function calling support built
into its architecture with dedicated special tokens.

### Limitation 2 — Compounding errors in multi-step loops

A model that calls the right tool 95% of the time sounds reliable, but in a
20-step workflow that is roughly one failure per run.

**The math:**

```
Step reliability   5-step task   10-step task   20-step task
95%                77%           60%            36%
85%                44%           20%            4%
70%                17%           3%             0.08%
```

A 2B model on mobile at ~70% per-step reliability makes a 5-step task succeed
only 17% of the time. This means your ReAct loop needs to be redesigned for
mobile — shorter chains, simpler tools, or offload reasoning to a server.

### Limitation 3 — Context window eaten by tool schemas

MCP registers all tools at startup. On a phone, the tool schemas alone can
consume 30-40% of the context budget before the user types anything. Research
shows that models with too many tools in context begin ignoring or confusing
them beyond ~128 tools.

**Why your Toolset system (Phase 2 roadmap) is critical for mobile:**
Load only the tools relevant to the current task. 5-6 tools maximum per
session on mobile. This is not optional on edge — it is required.

### Limitation 4 — Heat and thermal throttling

The single biggest constraint on mobile LLMs is not model size or RAM. It is
heat. An agent loop runs many sequential model calls. Each call generates heat.
The phone throttles. By turn 3 or 4 of a ReAct loop, the phone is running at
40-60% of initial speed. Long multi-step tasks become unusably slow.

**Practical consequence:** Keep agent loops short on mobile. 3-5 turns maximum
for on-device inference. Longer tasks should route to a server.

### Limitation 5 — Specialized tiny model approach (opportunity)

The most important 2026 development for mobile agents:

**Needle** — a 26M parameter model distilled from Gemini 3.1 that outperforms
models 10-25x its size on single-shot function calling, running at 1,200
tokens/second on edge hardware with under 50MB memory.

**FunctionGemma** — Google's 270M parameter model purpose-built for on-device
function calling.

This suggests a split architecture:

```
Tiny specialist model (26M-270M)  ← decides WHICH tool to call
                                    fast, low memory, reliable routing
    ↓
Full model (2B-4B)                ← does the actual reasoning and synthesis
```

The tiny model handles tool routing. The bigger model handles thinking.
This pattern resolves the reliability cliff for mobile.

---

## 3. Edge Agent Frameworks

Summary of what exists for mobile agent development as of July 2026.

### The honest answer

There are no mature agent *frameworks* for mobile. What exists is inference
engines — ways to run a model on device. The agent loop on top of that is
still written by hand. That is good news for this project — the loop you are
building in Python translates directly.

### By platform

**iOS — Apple Foundation Models (iOS 26)**
- Native Swift tool calling via the `Tool` protocol
- ~3B on-device model, same one powering Apple Intelligence
- Free, offline, no API keys
- Locked to Apple's model — cannot swap in Qwen or Gemma
- Not designed for multi-step ReAct loops
- Good for: single tool calls, structured extraction, in-app features
- Bad for: full agent harness with deep chains

**iOS — llama.cpp Swift bindings**
- Full model flexibility — any GGUF model
- More manual integration work
- Gemma 4 E2B at 40 tok/s on iPhone 17 Pro is the best on-device result in 2026
- This is the path for a full agent harness on iOS

**Android — LiteRT-LM (replaced MediaPipe)**
- Google's replacement for the deprecated MediaPipe LLM API
- Powers Gemini Nano in Chrome and Pixel Watch
- Multi-Token Prediction (added April 2026) delivers 2x+ faster decode
- Kotlin and C++ APIs with proper KV-cache management
- This is what DAEX uses

**Cross-platform — React Native ExecuTorch**
- PyTorch models on-device with hardware acceleration
- `useLLM` hook feels like calling a REST API
- Supports Llama 3.2, Qwen 3, Whisper out of the box
- Best DX for cross-platform — one codebase for iOS and Android

**Cross-platform — Koog (JetBrains, Kotlin)**
- Kotlin-native agent framework targeting JVM, Android, iOS, WASM
- Has MCP integration built in
- Has Ollama integration
- Has built-in history compression and agent persistence
- Closest existing framework to what this project is building
- Worth monitoring as a potential mobile port target

**Cross-platform — Llamatik**
- Kotlin Multiplatform: Android, iOS, Desktop, JVM, WASM
- Powered by llama.cpp, whisper.cpp, stable-diffusion.cpp
- Supports concurrent agent sessions with named session management
- Has MCP server support
- MIT license

---

## 4. Apple Foundation Models

### What it is

Foundation Models is Apple's framework for accessing the on-device language
model that ships with Apple Intelligence-eligible devices in iOS 26. The
framework exposes `SystemLanguageModel`, `LanguageModelSession`, and the
`Tool` protocol so apps can run typed, on-device LLM calls without network
access.

iOS 26.4 rebuilt the on-device model from the ground up with better logic and
tool calling. Vision capabilities are coming in a future update.

### Tool calling in Swift

```swift
// 1. Define a tool as a Swift struct
struct SearchRestaurants: Tool {
    let name = "searchRestaurants"
    let description = "Search for restaurants by cuisine and party size"

    // Arguments are type-safe Swift structs, not JSON
    // @Generable lets the model parse natural language into these types
    @Generable
    struct Arguments {
        let cuisine: String
        let partySize: Int
        let date: String
    }

    // Your actual app logic runs here
    func call(arguments: Arguments) async throws -> String {
        return "Found 3 \(arguments.cuisine) restaurants for \(arguments.partySize)"
    }
}

// 2. Register tools with the session at construction time
let session = LanguageModelSession(
    tools: [SearchRestaurants()],
    instructions: "You are a restaurant booking assistant."
)

// 3. The model decides when to call the tool automatically
// No JSON parsing needed — everything is typed Swift
let response = try await session.respond(
    to: "Find italian for 4 people next Friday"
)
```

The model extracts parameters from natural language automatically. No JSON
schema writing, no response parsing — the framework handles it all.

### What is good about it

- Free, offline, no API keys, no cloud costs
- Rebuilt model in iOS 26.4 with better tool calling reliability
- `@Generable` macro gives type-safe structured output without JSON parsers
- Private Cloud Compute fallback — Apple's secure server model with 32K context,
  no account setup, no API keys. This is Apple's version of the Modal pattern.
- New in WWDC26: `LanguageModelSession` profiles let you switch between
  on-device and Private Cloud Compute mid-conversation

### What is bad about it for this project

| Limitation | Impact |
|---|---|
| Locked to Apple's ~3B model | Cannot use Qwen, Gemma, or any other model |
| Not designed for multi-step chains | ReAct loops confuse it beyond 3-4 turns |
| No MCP support | Tools are Swift structs, not MCP servers |
| Device availability is not guaranteed | Must handle unavailable state in UI |
| iOS 26 + Apple Intelligence required | Cuts out older devices |
| tvOS and watchOS not supported | Tool protocol unavailable on those platforms |

### Where it fits in this project's architecture

```
Simple, fast, single-step tasks
    → Apple Foundation Models Tool protocol
    → Free, offline, instant, great DX

Complex multi-step agent tasks (the ReAct loop)
    → Modal backend (Phase 3) — server handles reasoning, phone is UI
    → OR llama.cpp with Gemma4:e4b on-device for full offline agent
    → Full MCP tool layer works with either of these
```

Foundation Models is a complement, not a replacement for the full agent
harness. Use it for quick in-app features. Use the full loop for anything
requiring multiple tool calls or deep reasoning.

---

## 5. What Transfers from Python to Mobile

This is the core question. The answer is: the concepts transfer completely.
The Python files do not. You rewrite the logic, not invent new logic.

### File by file

```
core/loop.py
    Concept:  transfers 100%
    Code:     does not transfer — rewrite in Swift/TypeScript/Kotlin
    Effort:   ~1-2 hours — it is ~50 lines of logic
    Notes:    the loop is language-agnostic by design

core/history.py
    Concept:  transfers 100%
    Code:     does not transfer
    Effort:   ~15 minutes — it is a list and three methods
    Notes:    trivial rewrite in any language

core/interrupts.py
    Concept:  partially transfers
    Code:     does not transfer — SIGINT is Python/desktop specific
    Mobile:   use async task cancellation instead (Swift Task.cancel(),
              Kotlin coroutine cancellation)

providers/local.py
    Concept:  transfers — the translation layer idea is the same
    Code:     does not transfer — can't call Ollama HTTP on mobile
    Replace:  llama.cpp bindings (iOS/Android)
              ExecuTorch (cross-platform)
              LiteRT-LM (Android)
              Foundation Models (iOS, locked model)

mcp/client.py
    Concept:  transfers
    Code:     partially — MCP over stdio does not work on mobile
    Replace:  MCP over HTTP/SSE to a remote server (works on mobile)
              Kotlin MCP SDK (exists, targets Android and iOS)
              Swift MCP client (available in ecosystem)
```

### The mental model

```
Python now (desktop)         Mobile later
─────────────────────────────────────────────
LocalProvider            →   llama.cpp / ExecuTorch / LiteRT
mcp/client.py (stdio)    →   MCP over HTTP/SSE (remote server)
                             OR native MCP SDK per platform
core/loop.py             →   Same logic, ~50 lines, new language
core/history.py          →   Same logic, trivial rewrite
main.py                  →   Swift/Kotlin entry point
```

The Python agent is the blueprint. Mobile is the same blueprint in a different
material. No work is wasted.

---

## 6. The Three Paths to Mobile

### Path 1 — Thin client via Modal (Phase 3, do this first)

Your Python agent runs on Modal. The phone is a UI that sends messages and
displays responses. Nothing moves to mobile — the phone just talks to your
server over HTTP.

```
Phone (Swift / React Native)
    ↓ HTTP
Modal server running your Python agent
    ↓ stdio
MCP servers (filesystem, browser, search, etc.)
    ↓
Full model (qwen3:14b or gemma4:12b)
```

**Pros:**
- No rewrite required — your Python agent works as-is
- Full model capability — no size constraints
- Full MCP tool layer — no limitations
- Ship mobile immediately
- Modal hibernates when idle — very cheap when not in use

**Cons:**
- Requires internet connection
- Latency of a server round trip
- Not truly on-device

**This is the right approach for Phase 3.** Get mobile working via this path
first. On-device inference comes later.

### Path 2 — React Native + ExecuTorch (Phase 4+, cross-platform)

Loop logic stays in TypeScript. ExecuTorch runs the model on-device.
MCP connects to a remote server over HTTP/SSE for complex tools.

```
React Native app
├── loop.ts          ← your loop.py rewritten in TypeScript (~1-2 hours)
├── history.ts       ← your history.py rewritten in TypeScript (~15 min)
├── ExecuTorch       ← replaces LocalProvider (Gemma4:e4b on-device)
└── MCP over HTTP    ← replaces mcp/client.py stdio (remote MCP server)
```

**Pros:**
- One codebase for iOS and Android
- Works offline for simple tasks
- useLLM hook is clean DX
- Supports Qwen3, Gemma4, Llama3

**Cons:**
- On-device model limited to 2-4B (reliability cliff applies)
- Native module setup pushes you out of pure JavaScript
- Multi-step chains need server fallback

### Path 3 — Native Swift / Kotlin (best performance, most work)

Full native rewrite targeting each platform separately. Use Foundation Models
or llama.cpp for iOS, LiteRT or ExecuTorch for Android. This is the DAEX
approach.

**Pros:**
- Best performance per platform
- Full hardware acceleration (Neural Engine, NPU, Vulkan)
- No bridge overhead

**Cons:**
- Two separate codebases
- Most engineering effort
- Tool calling still limited by model size on-device

---

## 7. Model Recommendations for Mobile

### iPhone (current best — July 2026)

| Model | Size | Tool calling | Notes |
|---|---|---|---|
| `gemma4:e2b` | ~1.5GB | Native, reliable | Only sub-4B with reliable tool calling |
| `gemma4:e4b` | ~3GB | Native, good | Better reasoning than e2b |
| `phi-4-mini` | ~2.4GB | Good with prompting | Strongest sub-4GB reasoning overall |
| Apple Foundation Models | ~0GB (system) | Native Swift | Locked model, single-step only |

Gemma 4 E2B running at 40 tok/s on iPhone 17 Pro with full offline reasoning
is the best on-device AI result in 2026. Google's AI Edge Gallery app makes
it easy to test.

### Android (current best — July 2026)

| Model | Size | Tool calling | Engine |
|---|---|---|---|
| `gemma4:e2b` | ~1.5GB | Native | LiteRT or ExecuTorch |
| `gemma4:e4b` | ~3GB | Native | LiteRT or ExecuTorch |
| Gemini Nano | System | Via AICore | Built-in on Pixel devices |

### Key constraint for both platforms

Phone RAM is shared. Subtract roughly 2-4GB for the OS before budgeting for a
model. The practical sweet spot for most phones in 2026 is 1B-3B parameters.
Flagship hardware (iPhone 17 Pro, Pixel 9 Pro) can push 4-8B at Q4.

Everything uses Q4 quantization (4 bits per weight) to fit models into mobile
RAM. Q3 and lower degrade tool calling reliability before they degrade general
chat quality — use Q4_K_M as the minimum for any agent use.

### Verify tool calling support before using any model

```bash
# For Ollama on desktop (development)
ollama show gemma4:e4b    # look for "tools" in Capabilities section

# The word "supports" is ambiguous.
# A model can claim tool calling but return plain text in practice.
# Always run a real tool call test before trusting a model in your loop.
```

---

## Summary

The Python agent harness being built in this project is not wasted work for
mobile. It is the blueprint. The loop logic, history management, and MCP
architecture all transfer directly — just rewritten in Swift, TypeScript, or
Kotlin when the time comes.

The recommended mobile progression:

```
Phase 3 now  →  Modal backend + thin mobile UI client
                Full agent capability, no on-device constraints
                Ship mobile without rewriting anything

Phase 4      →  React Native + ExecuTorch
                Hybrid: simple tasks on-device, complex tasks via Modal
                Toolset system required (max 5-6 tools per session)

Phase 5+     →  Native Swift/Kotlin if performance demands it
                llama.cpp on iOS, LiteRT on Android
                Split model architecture (tiny router + small reasoner)
```

The agent pattern you are building now works at every layer of this stack.
Only the inference engine and transport change per platform.

---

*Last updated: July 2026. Covers DAEX repo analysis, on-device tool calling
limitations, Apple Foundation Models framework, edge agent frameworks, and
mobile port strategy for the Python agent harness.*
