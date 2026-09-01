# nimm Critical Path

**Canonical critical path:** GitHub issue [#454](https://github.com/mjandrews1/nimm/issues/454)
("Critical path: FST design — formal spec first, Nim core + NimM/Python helpers").
This file is a pointer; the issue tracker is authoritative.

**Remotes:** GitHub (`origin`) and Utility-01 (`/home/mark/nimm`, synced via
pull). GitLab is deprecated.

**Current state (2026-08-31):**
- Formal verification: 27 Dafny model sets, 281 lemmas, `make verify` green.
- Test suite: 73 tests passing.
- FST Phase A/B/C complete (`hnsw.dfy`, `search_engine.dfy`, `global_bm25.nim`,
  `$NI_SEARCH` intrinsic).
- BM25 index build consolidated onto Nim `buildIndex` (#457 fixed): MeSH validated
  exact-match vs the M build (31,110 docs / 989,742 tokens / avgdl 31.81); CatLine
  rebuilt 1,240,758 docs (tokens 11,918,897, avgdl 9.61).
- M `SCORE`/`SEARCH`/`BUILD*` entry points retired from `bm25idx.m`; `DICT`
  (entry-term expansion) remains.

## Standing policies
- **RSM source is frozen** — no development changes; the sole reference engine.
- **RFC deprecated** — RSM is the reference engine.
- **Utility-02 deprecated** — all roles on Utility-01.
- **nimm v0.1.0 frozen** (tag `v0.1.0`); development continues on v0.1.x.
