# Python's `logging` module: what it is, how it's structured

**Question asked:** What is the stdlib `logging` module for, and how are
Logger / Handler / Formatter / Filter structured — what's the level
hierarchy, and how does propagation work?

This is a general conceptual reference, not tied to any specific project
code. All quotes and examples below are pulled from the official docs:

- [`docs.python.org/3/library/logging.html`](https://docs.python.org/3/library/logging.html)
  (the library reference — generated from
  [`Doc/library/logging.rst`](https://github.com/python/cpython/blob/v3.11.14/Doc/library/logging.rst)
  in the CPython repo)
- [`docs.python.org/3/howto/logging.html`](https://docs.python.org/3/howto/logging.html)
  (the Logging HOWTO — generated from
  [`Doc/howto/logging.rst`](https://github.com/python/cpython/blob/v3.11.14/Doc/howto/logging.rst))
- [`docs.python.org/3/howto/logging-cookbook.html`](https://docs.python.org/3/howto/logging-cookbook.html)
  (worked examples — generated from
  [`Doc/howto/logging-cookbook.rst`](https://github.com/python/cpython/blob/v3.11.14/Doc/howto/logging-cookbook.rst))

docs.python.org *is* this GitHub source, rendered — the `.rst` files in
`cpython`'s `Doc/` directory are the single source of truth for both.

---

## 1. What problem `logging` solves

> **ELI5:** `print()` is shouting into the room — everyone hears it, all
> the time, and there's no way to tell it "only shout the important stuff"
> or "shout somewhere else today." `logging` is more like a walkie-talkie
> with a volume knob and a channel selector: you can turn a whole category
> of messages up or down, and choose where they go (screen, file, both),
> without changing the code that sends them.

The HOWTO's own guidance on when to reach for which tool:

| Task | Best tool |
|---|---|
| Display console output for ordinary usage of a command line script/program | `print()` |
| Report events that occur during normal operation of a program (e.g. for status monitoring or fault investigation) | Logger's `info()` (or `debug()` for very detailed diagnostic output) |
| Issue a warning regarding a particular runtime event | `warnings.warn()` in library code, if the issue is avoidable and the client should modify their code; `logging.warning()` if there's nothing the client can do |
| Report an error regarding a particular runtime event | Raise an exception |
| Report suppression of an error without raising an exception | Logger's `error()`, `exception()`, or `critical()` as appropriate |

The standard severity levels, in increasing order — from
`Doc/library/logging.rst`:

| Level | Numeric value | Meaning |
|---|---|---|
| `NOTSET` | 0 | On a logger: "consult ancestor loggers to determine the effective level." On a handler: handle all events. |
| `DEBUG` | 10 | Detailed information, typically of interest only when diagnosing problems. |
| `INFO` | 20 | Confirmation that things are working as expected. |
| `WARNING` | 30 | An indication that something unexpected happened, or a problem may occur in the near future; the software is still working as expected. **This is the default level** — a script using only `logging.warning()`/`.error()`/`.critical()` needs no configuration at all. |
| `ERROR` | 40 | Due to a more serious problem, the software has not been able to perform some function. |
| `CRITICAL` | 50 | A serious error, indicating that the program itself may be unable to continue running. |

The numbers matter more than they look: level filtering is just
`if event_level >= threshold: handle it`. `WARNING` (30) is the default
threshold, which is why plain `logging.info(...)` calls silently produce
no output until you configure something — this trips people up constantly.

## 2. The four core building blocks

> **ELI5:** A **Logger** is the person deciding "is this worth mentioning
> at all?" A **Handler** is a mail carrier deciding "does this particular
> letter go to *my* mailbox?" A **Formatter** is the person addressing the
> envelope — deciding what the letter actually looks like on the outside.
> A **Filter** is a bouncer who can reject a letter for a much pickier
> reason than just its volume level, at either the Logger's desk or the
> Handler's mailbox.

| Component | Job | Notes from the docs |
|---|---|---|
| **Logger** | The interface application code calls (`.debug()`, `.info()`, etc.) | "Loggers... **should NEVER be instantiated directly**, but always through the module-level function `logging.getLogger(name)`." |
| **Handler** | Sends a `LogRecord` to its actual destination (console, file, network, email, ...) | `Handler` itself is never instantiated directly — it's a base class for `StreamHandler`, `FileHandler`, etc. Its `emit(record)` "raises `NotImplementedError`" in the base class; subclasses implement it. |
| **Formatter** | Decides the final text layout of a record | Constructor: `logging.Formatter(fmt=None, datefmt=None, style='%', ...)`. Default `fmt` is just `'%(message)s'` — no level, no timestamp, unless you ask for them. |
| **Filter** | Finer-grained accept/reject logic than a level threshold | "You don't need to subclass `Filter`" — any callable with a `.filter(record)` method, or even a plain function, works as a filter. |

Both **Loggers and Handlers can each have their own level threshold**
(`setLevel(level)`), and both can have their own list of filters. This is
why the cookbook's canonical multi-destination example sets the *logger*
to `DEBUG` but a *console handler* to `ERROR` — one logger, two handlers,
two different thresholds, no duplicated logging calls:

```python
# Doc/howto/logging-cookbook.rst
logger = logging.getLogger('simple_example')
logger.setLevel(logging.DEBUG)
# create file handler which logs even debug messages
fh = logging.FileHandler('spam.log')
fh.setLevel(logging.DEBUG)
# create console handler with a higher log level
ch = logging.StreamHandler()
ch.setLevel(logging.ERROR)
# create formatter and add it to the handlers
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
fh.setFormatter(formatter)
logger.addHandler(ch)
logger.addHandler(fh)

logger.debug('debug message')     # → file only (below console's ERROR threshold)
logger.error('error message')     # → both file and console
```

## 3. How a call actually flows through the system

> **ELI5:** Think of it as a series of doors, each with its own bouncer.
> Your message has to get past the Logger's bouncer (is it loud enough?
> does it pass the Logger's own filters?) before it's even offered to any
> Handler. Then each Handler has *its own* bouncer at *its* door (its own
> level, its own filters) before the message is allowed to actually get
> written anywhere.

The HOWTO's own description of the flow, condensed:

```
logger.info("...")
  → is INFO >= this logger's effective level?          (else: drop, stop here)
  → does the record pass this logger's filters?         (else: drop)
  → hand the record to every Handler on this logger
       → for each Handler:
            is the record's level >= this handler's level?  (else: skip this handler)
            does the record pass this handler's filters?     (else: skip)
            handler.emit(record)   — format via its Formatter, write to destination
  → if this logger's `propagate` is True, repeat the "hand to every Handler"
    step for the parent logger, then *its* parent, up to the root
```

One detail worth calling out because it's easy to get backwards:
**propagation only re-checks handlers up the chain — it does not re-check
the ancestor logger's own level or filters.** Once a record clears its
*own* logger's threshold, it will reach every ancestor's handlers
regardless of what level those ancestor loggers are set to. Only an
ancestor with `propagate = False` breaks the chain early.

## 4. The logger hierarchy and dotted names

> **ELI5:** Logger names are like a family tree written as an address:
> `"myapp.database.queries"` is a child of `"myapp.database"`, which is a
> child of `"myapp"`, which is a child of the one root ancestor everyone
> shares. Naming things this way means you can turn the volume up or down
> for an entire branch of the family at once, just by configuring one
> ancestor.

From the reference docs: logger names use a dot-separated hierarchy — a
logger named `foo` is the parent of `foo.bar`, `foo.bar.baz`, and
`foo.bam`; every logger is ultimately a descendant of the one root logger.
This is also why the near-universal convention is:

```python
logger = logging.getLogger(__name__)
```

Because `__name__` inside a module is that module's dotted import path,
loggers created this way automatically mirror your package layout — "it's
intuitively obvious where events are logged just from the logger name,"
per the HOWTO. The same page is explicit about *why* library code
shouldn't skip this and just call `logging.info(...)` (which logs to the
implicit root logger):

> "It is strongly advised that you do not log to the root logger in your
> library. Instead, use a logger with a unique and easily identifiable
> name... Logging to the root logger will make it difficult or impossible
> for the application developer to configure the logging verbosity or
> handlers of your library as they wish."

The practical consequence: **libraries should only ever create loggers and
log to them** — never call `basicConfig()` or attach handlers themselves.
Deciding *where logs go and at what verbosity* is the application's job,
done exactly once, typically at the program's entry point.

## 5. `basicConfig()` — the entry-point shortcut

> **ELI5:** Setting up a Logger, a Handler, and a Formatter by hand every
> time is like assembling furniture from raw lumber. `basicConfig()` is
> the flat-pack version — one function call gives you a console (or file)
> handler with a reasonable format already attached to the root logger, as
> long as you call it before anything else has configured logging.

```python
# Doc/howto/logging.rst
import logging
logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.DEBUG)
logging.debug('This message should appear on the console')
```

Common keyword arguments, per the docs:

| Argument | Effect |
|---|---|
| `level` | Threshold for the root logger (e.g. `logging.DEBUG`) |
| `format` | The `Formatter` string applied to the handler `basicConfig` creates |
| `datefmt` | Format for `%(asctime)s`, if used |
| `filename` | If given, logs to this file via a `FileHandler` instead of the console |
| `filemode` | `'a'` (append, default) or `'w'` (overwrite) — only relevant with `filename` |
| `handlers` | A list of pre-built `Handler` instances, if you need more control than `filename`/`format` alone give you |

**The one gotcha that matters most in practice:** `basicConfig()` "does
nothing if the root logger already has handlers configured, unless the
keyword argument `force` is set to `True`." It's meant to be called
**once**, early, typically in the program's main entry point — calling it
repeatedly, or after something else has already added a handler, is
silently a no-op unless you pass `force=True`.

## 6. Putting the whole picture together

```
your code:  logger = logging.getLogger(__name__)
            logger.warning("disk usage at %d%%", pct)
                 │
                 ▼
       [Logger "myapp.disk"]  level check, own filters
                 │  (propagate=True by default)
                 ▼
       [Handler(s) on "myapp.disk"]  level check, own filters → Formatter → destination
                 │
                 ▼
       [Handler(s) on "myapp"]  (same check, if "myapp" has any)
                 │
                 ▼
       [Handler(s) on root]  (same check — this is usually where
                               basicConfig()'s one handler lives)
```

Four independent knobs — **which logger you call, that logger's level,
each handler's level, and each handler's formatter** — is the entire
vocabulary of the module. Everything else in the stdlib docs (rotating
file handlers, `dictConfig`/`fileConfig`, `QueueHandler` for multiprocess
logging, `LoggerAdapter`, structured `extra=` fields) is built on top of
these same four pieces, not a replacement for them.
