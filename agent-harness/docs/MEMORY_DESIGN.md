# Brain-Inspired Memory — Design

The agent gets a memory that works like a brain: facts it uses often get
stronger and easier to recall, facts it never touches fade from the
foreground, and related facts link together — so over time, recall stays
fast, relevant, and personal.

We are NOT simulating neurons. Every "cell" is a readable sentence
("JaeHub is a collaborator on free-pizza-project"), so the whole store is
inspectable, editable, and deletable by the user. Same principles as the
brain — strengthening, decay, association — at the altitude of facts.

## Why not just RAG?

Plain vector search fixes *recall* (find what looks similar) but has no
notion of *importance* — every stored fact is equal forever. The brain
layer adds salience: `score = similarity × strength`, where strength is
earned through use.

## The four rules

1. **STORE** — facts get extracted from completed runs and saved as nodes.
2. **STRENGTHEN** — every time a memory is recalled and actually helps,
   its strength goes up.
3. **DECAY** — strength drains with time since last use (ACT-R style).
4. **ASSOCIATE** — memories used together get linked (Hebbian); recalling
   one pulls its neighbors toward the surface.

## The refinements (v2 — from the "why forget?" discussion)

The naive version has three flaws; each has a fix baked into this design:

### 1. Rarely used ≠ unimportant → importance is its own axis
Your passport number is touched once a year and must never be lost. Human
brains solve this with salience tagging (one-shot permanent memories).
So every node carries **two independent scores**:

- `strength` — usage-driven, decays; controls how easily the memory wins
  the recall competition.
- `importance` — set at write time by the extraction pass ("is this
  costly to forget?") or pinned by the user; sets a floor decay cannot
  cross.

### 2. Forgetting = deprioritizing, never deleting
Decayed nodes are **archived**: out of the default recall competition,
still fully searchable on demand. "Tip of the tongue," not "gone."
Forgetting exists to keep recall fast and uncluttered, not to destroy
information.

### 3. Memories must be conditional, not binary verdicts
"User ignores LinkedIn alerts" is a lossy compression — the truth is
"skips ~95% of LinkedIn job alerts, but opens ones about IT internships."
The ingest step must extract **graded, conditional memories** ("usually
X, except when Y"). And when behavior contradicts a memory (the plate
downranked a LinkedIn alert; the user opened it), that contradiction is
the most valuable signal in the system: it triggers **memory revision**
into the exception form, not just a missing reinforcement.

### 4. Preferences are rankers, never filters
The briefing agent still *reads everything*. Memory supplies a prior for
ranking; content can override it. "LinkedIn alert" scores low by default,
but "LinkedIn alert mentioning the company you interviewed with" scores
high on content regardless. A blacklist creates blind spots; a prior just
raises the bar for attention.

## Architecture

```
 user chats / briefings run
          │
          ▼
 ┌────────────────────────┐   after each completed run, one cheap
 │ INGEST  (ingest.py)    │   background model call extracts durable,
 │ extract / revise facts │   conditional facts + importance tags,
 └───────────┬────────────┘   dedupes against existing nodes
             ▼
 ┌────────────────────────┐   SQLite, one file per user:
 │ STORE   (store.py)     │   nodes(text, embedding, strength cols,
 │ nodes + edges          │   importance, archived) + edges(weights)
 └───────────┬────────────┘
             ▼
 ┌────────────────────────┐   embed query → cosine × strength →
 │ RECALL  (recall.py)    │   spread through strong edges → top-k;
 │ + reinforce on use     │   used memories get strengthened
 └───────────┬────────────┘
             ▼
  relevant memories injected into the agent's prompt
  (auto-inject first; a search_memory tool later)
```

Supporting pieces:
- `embedder.py` — local nomic-embed via LM Studio's `/v1/embeddings`
  (private; the index never leaves the machine even when chat inference
  is on Cerebras).
- `activation.py` — the math: ACT-R base-level activation
  `ln(Σ tᵢ⁻ᵈ)` for strength, the combined recall score, the freshness
  bonus for new nodes (anti rich-get-richer), the archive floor.

## Schema

```sql
nodes:
  id          INTEGER PRIMARY KEY
  text        TEXT      -- the fact, as a readable (conditional) sentence
  source      TEXT      -- chat | briefing | manual
  embedding   BLOB      -- float32 vector (local nomic-embed)
  importance  REAL      -- write-time / user-pinned floor (0..1)
  use_count   INTEGER
  last_used   TEXT      -- ISO timestamp
  uses        TEXT      -- JSON list of use timestamps (for ACT-R sum)
  archived    INTEGER   -- 0/1 — archived nodes skip default recall
  created_at  TEXT

edges:
  node_a, node_b  INTEGER
  weight          REAL   -- Hebbian association strength
```

## Build order (each stage works on its own)

```
Stage 1  Foundation        embedder + store + ingest hook (schema complete)
Stage 2  Plain recall      similarity-only, auto-injected at run start
Stage 3  Usage weighting   score = similarity × strength   ← ~70% of value
Stage 4  Decay + archive   ACT-R decay, importance floor, archive sweep
Stage 5  Hebbian edges     co-use links + spreading activation
Stage 6  App UI            "What Promethius knows about you" (view/edit/
                            delete/pin) + GET/PUT /memory endpoints
```

## Risks and their mitigations

| Risk | Mitigation |
|---|---|
| Rich-get-richer (popular memories crowd out new ones) | freshness bonus for young nodes; contradiction-driven revision drains wrong-but-popular nodes |
| Fuzzy reinforcement signal ("retrieved" ≠ "helped") | start with the honest crude proxy: reinforce memories used in runs the user didn't correct/redo; refine later |
| Decay tuning | ship ACT-R's canonical d=0.5, expect empirical iteration |
| Memory quality / safety | ingest is the chokepoint: cap node count, dedupe near-identicals, skip sensitive categories; every node human-readable and editable |
```
