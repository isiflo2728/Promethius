# agent-harness

A basic, pluggable-tools agent harness, built against a local Ollama model.
Scaffolded intentionally — the files here have signatures and comments, not
implementations. See `../learning_agent_architecture.md` for the concepts
behind this.

## Setup

```bash
# 1. install Ollama: https://ollama.com/download
# 2. pull a tool-calling-capable model
ollama pull llama3.1

# 3. start the Ollama server (if not already running)
ollama serve

# 4. python deps (uv manages the venv for you)
uv sync
```

Run scripts with `uv run main.py` (no manual venv activation needed). To add
a dependency later: `uv add <package>`.

## Files

- `tool.py` — the `Tool` dataclass: name, description, JSON Schema, function.
- `agent.py` — the `Agent` class: the loop, tool dispatch, message state.
- `tools/example_tools.py` — `read_file` and `run_shell_command` as example tools.
- `main.py` — wires it together into a simple chat loop.

## Build order

1. Implement `Tool.to_schema()` in `tool.py`.
2. Implement `Agent.__init__`, `_tool_schemas`, `_dispatch` in `agent.py`.
3. Implement `Agent.run()` — the actual loop.
4. Implement the two functions + `Tool(...)` wrappers in `tools/example_tools.py`.
5. Wire it up in `main.py` and run it.

## Sanity check once it runs

Ask it something that requires a tool call, e.g. "what's in requirements.txt
in this directory?" — it should call `read_file`, not hallucinate an answer.
