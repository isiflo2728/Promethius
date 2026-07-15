# Switching Inference Engines: Ollama to LM Studio

A narrative of everything done to move this project off Ollama and onto
LM Studio as the local inference engine — what changed in the repo, what
changed on the machine, and two real failures hit along the way (an MLX
engine crash, and an `lms` CLI inconsistency) with how each was diagnosed
and resolved. Follows on from `docs/ISSUES.md` item 7 and
`docs/research/learning_agent_architecture.md`'s Part 0, which cover the
tool-use-enforcement bug this same debugging session started from.

---

## 1. Why switch

Ollama's OpenAI-compatible endpoint (what `providers/local.py` talks to)
defaults every model to a **4096-token context window**, with no way to
raise it per-request — confirmed directly from Ollama's own docs: *"The
OpenAI API does not natively support setting the context size for a model.
If you need to adjust the context size, you must create a `Modelfile`."*
A single Composio `COMPOSIO_SEARCH_TOOLS` tool result measured **~5,500
tokens on its own** — bigger than the whole default window — which was the
real cause of a bug logged in `docs/ISSUES.md` item 7 (the model
describing a tool result instead of acting on it). That got fixed with a
custom Ollama model (`ollama/qwen3-14b-agent.Modelfile`, `PARAMETER num_ctx
40960`) plus two system-prompt guidance blocks adapted from Hermes Agent.

Wanting a different engine entirely (not just a workaround) led to LM
Studio, which — like Ollama — exposes an OpenAI-compatible local server, so
in principle `providers/local.py` needed no rewrite, only a different
`base_url`.

## 2. Confirming the swap was actually low-risk, before doing it

Checked LM Studio's own developer docs before touching anything:

- Base URL: `http://localhost:1234/v1` (vs. Ollama's `:11434/v1`), API key
  is a throwaway placeholder (`"lm-studio"`) exactly like Ollama's
  (`"ollama"`) — neither server actually validates it.
- Tool calling returns the **identical OpenAI shape** —
  `response.choices[0].message.tool_calls[].function.name/arguments` — so
  none of `providers/local.py`'s `_format_messages`/`_format_tools`/
  `ToolCall` parsing logic needed to change.
- LM Studio has the **same context-window constraint** as Ollama: no
  per-request override, only settable when a model is *loaded*
  (`lms load <model> -c <N>`), the CLI equivalent of Ollama's Modelfile.

## 3. Code changes made

- **`providers/local.py`** — `LocalProvider.__init__` gained an `api_key`
  parameter (previously hardcoded to `"ollama"`), so it can authenticate
  against any OpenAI-compatible server.
- **`main.py` / `server.py`** — both now build `LocalProvider` from three
  env vars — `AGENT_MODEL`, `LLM_BASE_URL`, `LLM_API_KEY` — all defaulting
  to Ollama's original values, so nothing broke for anyone still on Ollama.
- **`docs/README.md`** — new "Switching inference engines (Ollama vs. LM
  Studio)" section documenting both side by side, including each engine's
  context-length fix.

Committed as `641f227`, "Add tool-use guidance to system prompt; make the
inference engine swappable" (bundled with the Hermes system-prompt fix from
the same debugging session), and pushed.

## 4. Setting up LM Studio on the machine

```bash
# App already installed by this point (LM Studio.app); CLI just needed
# bootstrapping onto PATH:
~/.lmstudio/bin/lms bootstrap

# Pulled the same model already validated on Ollama, in MLX format first
# (Apple Silicon's native format - this machine is an M4 Pro):
lms get qwen3-14b --mlx -y
```

The first download attempt timed out at ~2.5% (208MB of 8.32GB) — an
unstable transfer, not a real problem. Retrying resumed and completed
cleanly.

```bash
lms load qwen/qwen3-14b -c 40960   # same 40960 already validated to fit
                                    # this machine's 24GB RAM when tested
                                    # against the Ollama/GGUF version
lms server start --port 1234
```

`.env` updated to point at it:

```
AGENT_MODEL=qwen/qwen3-14b:2
LLM_BASE_URL=http://localhost:1234/v1
LLM_API_KEY=lm-studio
```

## 5. First real test — confirmed the actual root-cause fix, then hit a new bug

Reran the exact same "access my Google Drive, what's the most recent
document" test that had failed twice before under Ollama. This time it
worked correctly through several turns it had never reached before:

1. `COMPOSIO_SEARCH_TOOLS` (as before)
2. `COMPOSIO_MANAGE_CONNECTIONS` — **correctly called this time**, instead
   of being described in prose (the exact failure `docs/ISSUES.md` item 7
   logged twice under Ollama)
3. Presented connect links, waited for the user to authenticate
4. After "okay all authenticated": re-verified the connection, then
   correctly called `COMPOSIO_MULTI_EXECUTE_TOOL` to run
   `GOOGLEDRIVE_FIND_FILE`

This confirmed the context-window + Hermes-guidance fix from `docs/ISSUES.md`
item 7 was the right diagnosis all along — it just hadn't been possible to
prove with Ollama's context-window bug still in the way.

It then crashed on the next model call:

```
openai.BadRequestError: Error code: 400 - {'error': 'The model has crashed
without additional information. (Exit code: null)'}
```

`lms ps` showed the loaded instance had disappeared entirely (crashed, not
just slow). LM Studio's own server log
(`~/.lmstudio/server-logs/2026-07/2026-07-14.1.log`) had the real detail
the API's generic error didn't surface:

```
Fatal Python error: Aborted
...
mlx_engine/model_kit/batched_model_kit.py ... _generate_with_exception_handling
```

A hard abort inside LM Studio's **MLX** backend itself — not
`core/loop.py`, not the prompt, not a config mistake. `lms runtime update`
was checked as a quick fix in case it was an already-patched engine bug;
it reported everything already up to date, ruling that out.

**Was this a hardware ceiling?** No — ruled out directly: the identical
model at the identical 40960 context window had already run to completion
multiple times on this same 24GB machine via Ollama/GGUF. If the hardware
itself couldn't handle it, that run would have failed too. The more likely
explanation: MLX's batched-generation code path handling this specific
shape of workload (a long, tool-heavy context full of Composio's unusually
large JSON tool outputs) less gracefully than `llama.cpp`'s far more
battle-tested implementation.

## 6. Switching the loaded model from MLX to GGUF

```bash
lms get qwen/qwen3-14b --gguf -y
```

Downloaded cleanly (~9GB). Then hit a second, unrelated problem: `lms load`
would not accept the variant-specific key (`qwen/qwen3-14b@q4_k_m`) that
`lms ls`/`lms get` both freely displayed and recognized:

```
$ lms ls
qwen/qwen3-14b@q4_k_m    14B    qwen3    9.00 GB    Local
qwen/qwen3-14b@4bit      14B    qwen3    8.32 GB    Local

$ lms load 'qwen/qwen3-14b@q4_k_m' -c 40960 -y
Model not found
No model found that matches model key "qwen/qwen3-14b@q4_k_m".
```

Diagnosis: `@variant` suffixes are search/display syntax for `lms ls`/
`lms get`, but `lms load <model-key>` only resolves a **base** model key
and loads whichever variant is currently marked "selected" for it.
Switching the selected variant is `lms get --select`'s job — which
requires an interactive terminal (confirmed: piping input to it just
raised `"Error: The --select flag requires an interactive terminal"`).
Not a bug so much as a gap — `load` was never given a non-interactive way
to pick a specific variant when more than one is downloaded.

**Resolution:** did the variant selection through LM Studio's own GUI
instead (its load dialog has a variant picker that doesn't go through this
code path at all). First GUI load used the default context length
(8192 — smaller than intended); a second load explicitly set context to
**32768**, confirmed via:

```
$ lms ps
qwen/qwen3-14b    qwen/qwen3-14b    IDLE    9.00 GB    32768    4    Local
```

(`SIZE: 9.00 GB` confirms this is the GGUF variant, not MLX's 8.32GB.)

## 7. Final working configuration

```
# .env
AGENT_MODEL=qwen/qwen3-14b
LLM_BASE_URL=http://localhost:1234/v1
LLM_API_KEY=lm-studio
```

Reran the same two-message Google Drive test end-to-end: search → connect
→ authenticate → verify → execute → real file result, no crash. Confirmed
working.

## Summary

| Layer | Before | After |
|---|---|---|
| Engine | Ollama | LM Studio |
| Model format | N/A (Ollama manages its own) | GGUF (not MLX — MLX crashed) |
| Context window | 4096 (Ollama default, too small) | 32768 |
| `SYSTEM_PROMPT` | passive, one line | + Hermes's tool-use-enforcement and task-completion guidance |
| `LocalProvider` | hardcoded to Ollama's `base_url`/`api_key` | configurable via `LLM_BASE_URL`/`LLM_API_KEY` |

Two real, non-obvious failures surfaced and resolved along the way: an MLX
backend crash (engine-level, not application-level — resolved by using
GGUF instead) and an `lms load` CLI limitation around multi-variant models
(resolved by using the GUI for that one step). Neither was a sign the
underlying architecture was wrong — `providers/local.py`'s
provider-agnostic design meant the actual application code needed exactly
one new constructor parameter (`api_key`) to support a second inference
engine entirely.
