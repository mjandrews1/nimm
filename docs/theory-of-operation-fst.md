# FST — Theory of Operation

**What this is:** a reference for resuming work on the FST (Full-Text Search)
subsystem — `future_search_tool/` — and its data pipeline. It explains *why*
(invariants, join-key decisions) not just what. Companion to the NimM theory,
`critical-path.md`, and issue #454.

## 1. What the FST is

A search engine over biomedical data, living *on top of* the NimM global store
(no separate database engine). Data is loaded into `^…` globals, indexed into
`^BM25*` postings, cross-linked through a MeSH-outbound `^LINK` hub, and queried
through `$NI_*` intrinsics. The design is **formal-first** (Dafny model + Nim
mirror per concern) and **measured** (perf/cost gated by real numbers).

## 2. The data model

Sources are separate globals; the cross-reference hub ties them together:

```
 ^MESH(dui,"name"/"treeNumber"/...)      ^MESHTERM(name,dui)        ^QUAL(ui,...)
 ^SUPP(scrui,"name"/"mesh"/"regnum"/...) ^SUPPNAME(name,scrui)
 ^CATLINE(nlmId,...)   ^SERLINE(nlmId,...)   ^PUBMED(pmid,...)
 ^CTRIAL(nct,...)   ^ORANGEBOOK(applType,applNo,product,...)
 ^PROVIDER(npi,...)  ^CDC(...)  ^FAERS(caseid,...)  ^REPORTER (via ^LINK)

 ^LINK(fromType, fromId, toType, toId) = rel
```

The hub is **MeSH-outbound by design** (LMDB range-scans only from the left, and
every query is "given a MeSH term, find related records"). Reverse lookups are
per-record subscripts (e.g. `^PUBMED(pmid,"mesh",dui)`), which are cheap because
the record id is the leading subscript. `link_consistency.dfy` proves the
forward/reverse encodings stay equal under link/unlink and that name→UI
resolution emits no dangling link.

## 3. The join keys (each chosen after measurement / literature)

| Link | Key | Issue |
|---|---|---|
| PUBMED→SERLINE `journal` | `NlmUniqueID` (id, not title) | #466 |
| CATLINE→SERLINE `serial` | ISSN (022$a) | #465 |
| MESH↔records `subject`/`mesh_term` | descriptor UI via name→UI | #459 |
| ORANGEBOOK→SUPP `ingredient` | exact ingredient name → SCR (unambiguous only) | #462 |
| CTRIAL↔MESH | MeSH DUI (`conditionBrowseModule.meshes`) | #462 |
| PUBMED→REPORTER `funding` | PMID (ExPORTER link tables) | #462 |

#467 (ISSN fallback to NlmUniqueID) was measured at a 0.0003% gain and rejected.

## 4. Indexing

Built by `global_bm25.nim` (`buildIndex`) and `build_bm25.nim` CLI:

```
 ^BM25(term, src, docId) = tf      ^BM25DF(term, src) = df
 ^BM25LEN(src, docId) = len        ^BM25META(src, "N"/"avgdl")
 ^BMPOS(src, docId, term) = "p1|p2|..."   (phrase positions, #468)
 ^BM25PROG(src, ...) = build high-water mark
```

- `tokenizeDoc` is the **exact-char-set** tokenizer that `bm25idx.m` COMMON used
  (the P punctuation set, no `\n`/`\r` split) — tokenization parity with M is a
  hard rule (#458).
- Writes are **batched** (`beginWriteBatch` + `flushEvery`) so a write txn never
  grows to the ~1.2M-doc size that aborted the M build (#457).
- `df` is accumulated in-memory per flush window (`flushDfDelta`) instead of
  read-modify-write per term — the fix for ~1h CatLine builds.
- `^BMPOS` positions are **continuous 1-based across a doc's concatenated fields**
  (title^abstract^journal as one stream) — adjacency is only meaningful over one
  continuous space. `buildPositions` (or `--pos`) backfills it independently of
  the `^BM25` idempotency guard.
- k1 = **1.5** to match the M SCORE/SEARCH (bm25.nim's default is 1.2).

## 5. Retrieval surface (`$NI_*` intrinsics)

| Intrinsic | What | Model |
|---|---|---|
| `$NI_SEARCH(src, q, k)` | BM25 top-K | `bm25.dfy` |
| `$NI_EXPLAIN(src, id, q)` | per-term tf/df/idf | — (#463) |
| `$NI_BOOL(src, q, k)` | Boolean AND/OR/NOT + parens + phrases | `boolean_search.dfy`, `phrase_search.dfy` |
| `$NI_SQL("SELECT…")` | declarative SELECT-only | `query_semantics.dfy` |
| `$NI_PROFILE()` | cursor-step counter | — (#463) |

- **Boolean** (`bool_search.nim`) evaluates by **zig-zag merge** over the sorted
  postings (no materialization); `NOT` is set difference (`A AND NOT B`); phrases
  are the rarest-term posting walked against `^BMPOS` adjacency. `boolean_search.dfy`
  (over nat ordinals — chosen because strings lack Dafny trichotomy) proves the
  merge soundness/completeness.
- **SQL** (`sql_select.nim`) is a planner-first SELECT-only compiler to `$ORDER`
  walks, not an engine. M1 (single relation) is done. See #462.

## 6. Load & build pipeline

- `xmlload.nim` `ZLOADXML` formats: `mesh`, `qualifier`, `catline`, `pubmed`,
  `scr`. Stream-parses (no full-file DOM), writes `^FST("load",<file>)`
  high-water markers (`in-progress:N` → `complete:N`) so load progress is O(1)
  observable and partial loads are detectable.
- `build_*.nim` loaders per complementary source (ClinicalTrials, RePORTER,
  Orange Book, Medicare, CDC, FAERS). Each is idempotent on re-run.
- `deploy/rebuild_fst_full.sh` is the canonical from-scratch build; `db_audit.nim`
  (step 5) stream-checks framing/round-trip/ordering + `^LINK` symmetry + df
  over the live DB. Binaries from `make fst-build` land in `bin/` only.

## 7. Freshness & cadence

See #470 and its summary in `critical-path.md`. Freshness is an observable in
the DB (`^FST("load",…)`, `^BM25PROG`, and the planned per-source timestamp);
cadence is per-source policy (weekly PubMed/RxNorm/ClinicalTrials, monthly
CDC/Orange Book, quarterly FAERS/CatLine/SerLine, annual MeSH).

## 8. Key invariants (why the checks exist)

- **Tokenization parity with M** — `tokenizeDoc` matches `bm25idx.m` P-set exactly.
- **Join-by-id, not title** — NlmUniqueID/ISSN/DUI/PMID, each chosen from data.
- **Deterministic cross-links only** — no fuzzy name match; ambiguous names link nothing.
- **Batched writes + idempotent guards** — `^BM25LEN` skip, `^FST` markers.
- **Reader never blocks writer** — `--readonly` path; enables live query during build.
