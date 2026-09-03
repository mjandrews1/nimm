# nimm Critical Path

**Canonical critical path:** GitHub issue [#454](https://github.com/mjandrews1/nimm/issues/454)
("Critical path: FST design — formal spec first, Nim core + NimM/Python helpers").
The issue tracker is authoritative; this file is the human-readable plan.

**Remotes:** GitHub (`origin`) and Utility-01 (`/home/mark/nimm`, synced via
pull). GitLab is deprecated.

**Standing policies:**
- RSM source frozen — the sole reference engine. RFC deprecated.
- Utility-02 deprecated — all roles on Utility-01.
- nimm v0.1.0 frozen (tag `v0.1.0`); development continues on v0.1.x.

**Health (current):**
- Formal verification: **41 Dafny models, 364 lemmas**, `make verify` green.
- Test suite: **85 tests passing**.
- Loaded sources on Utility-01: MESH, SUPP, CATLINE, SERLINE, PUBMED, plus the
  complementary sources (ClinicalTrials, RePORTER, Orange Book, Medicare, CDC,
  FAERS) — see "Loaded data" below.

---

## Loaded data (Utility-01)

| Source | Global | Records | Cross-link |
|---|---|---|---|
| MeSH descriptors/qualifiers | `^MESH`, `^QUAL`, `^MESHTERM` | 31,110 | hub |
| MeSH Supplementary Concepts | `^SUPP`, `^SUPPNAME` | 324,049 | MESH↔SUPP (436k links) |
| CatLine | `^CATLINE` | 1,240,758 | MESH↔CATLINE `subject` |
| SerLine | `^SERLINE` | 150,942 | MESH↔SERLINE `subject`; PUBMED↔SERLINE `journal`; CATLINE↔SERLINE `serial` |
| PubMed | `^PUBMED` | ~2.97M | MESH↔PUBMED `mesh_term`; PUBMED↔REPORTER `funding` |
| ClinicalTrials.gov | `^CTRIAL` | 100,000 | CTRIAL↔MESH by DUI (1.14M links) |
| NIH RePORTER | `^REPORTER` (via `^LINK`) | 451,095 projects | PUBMED↔REPORTER `funding` (7.58M links) |
| FDA Orange Book | `^ORANGEBOOK` | 48,502 | ORANGEBOOK↔SUPP `ingredient` (3,838 links) |
| Medicare providers | `^PROVIDER` | 1,000 (page-1 stub) | none |
| CDC | `^CDC` | 74,790 rows | none |
| FAERS | `^FAERS` | (loading) | none |

Cross-reference hub: `^LINK(fromType, fromId, toType, toId) = rel`.

---

## Retrieval surface

| Intrinsic | Purpose |
|---|---|
| `$NI_SEARCH` | BM25 keyword (k1=1.5), top-K |
| `$NI_BOOL` | Boolean AND/OR/NOT + parens + `"phrases"` (#468) |
| `$NI_SQL` | SELECT-only layer (#462) |
| `$NI_EXPLAIN` | per-term tf/df/idf (#463) |
| `$NI_PROFILE` | cursor-step counter (#463) |

Indexes: `^BM25(term,src,docId)=tf` (posting), `^BM25DF`, `^BM25LEN`,
`^BM25META`, `^BMPOS(src,docId,term)=positions` (phrase, #468).

---

## Open issues (critical-path order)

1. **#462 — SELECT-only SQL layer** (the long-deferred experiment). M1 landed
   (single relation). M2 (nested-index JOIN over `^LINK`) and M3 (merge join +
   DESC) remain. Sole *genuinely-open* engine experiment.
2. **#468 — Boolean search** — engine/phrases **done** (formal + `bool_search.nim`
   + `$NI_BOOL` + `^BMPOS`; PubMed backfill completed, 2.97M docs in ~55 min,
   live phrase verified). **Sub-feature (next): named result sets** — Dialog-
   style `S1`/`S2` … set numbering (per source), sets referenced as operands
   (`S1 AND S2`), stored source-scoped (e.g. `^BOOLSET(src,name,id)`), plus a
   `bool_sets.dfy` model ("saved set == re-run result").
3. **#470 — Data freshness**: per-source cadence + scheduler (design below).
4. **#469 — BioArxiv** data source (design in #469: `^BIORXIV` by DOI, medRxiv
   first, BIORXIV→PUBMED post-publication PMID link).
5. **#472 / #473 — Theory of Operation** — **done** (`docs/theory-of-operation-nimm.md`,
   `docs/theory-of-operation-fst.md`).
6. **#471 — Odin experiment** — **designed** (spike scoring, decision gates; see
   #471).

---

## Data freshness (#470) — design summary

*Cadence is per-source, policy is a table, freshness is an observable in the
DB.*

- Ground truth markers already exist: `^FST("load",<file>)` (per-file state +
  count), `^BM25PROG`, `^BM25META`. All loaders are idempotent on re-run.
- **Missing piece: a timestamp.** Add `^FST("meta",<source>,<version>) = <ISO8601>`
  written by each loader on completion, so "how fresh is X" is one `$G`.

### Cadence policy (user trimers: week / month / quarter)

| Source | Cadence |
|---|---|
| PubMed baseline, RxNorm, ClinicalTrials, BioArxiv (later) | **weekly** |
| CDC tables, Orange Book | **monthly** |
| FAERS, CatLine, SerLine | **quarterly** |
| MeSH descriptors/qualifiers, MeSH SCR | **annual** |
| RePORTER (ExPORTER) | annual + weekly snapshots |

Daily/instant are explicitly out of v1 (overkill for a search corpus; NLM/CDC
rate limits favour less-frequent).

### Scheduler

- `deploy/sources.tsv` manifest: `source|cadence|loaderArgs…`.
- `deploy/refresh.sh --due-only` (bash) runs each source whose
  `^FST("meta",…)` timestamp is stale; driven by one cron/systemd timer on
  Utility-01.
- **Incremental vs full:** v1 does full re-load per source (idempotent, cheap
  for everything but PubMed); PubMed delta (update files) is a later milestone.

---

## Verify

### Blocked (need external input)

- **RxNorm → SCR** needs a UTS API key (UNII codes live only in the licensed
  full release; the unlicensed "prescribable" release has none).
- **PubMed baseline completion** (#474) — download job designed, not yet run
  (99/~1200 files staged; resumable `deploy/fetch_pubmed_baseline.sh`).
- **Medicare full provider directory** — re-download with pagination (staged
  file holds only page 1 = 1,000 of 3.39M).

### Deprecated / non-goals

- #467 ISSN fallback — measured 0.0003% gain → won't do.
- CDI/DailyMed-/FAERS-API stubs were replaced by real downloads (FAERS ASCII
  2026 Q1/Q2 + DailyMed RxNorm mapping); HCUP (DUA), MedWatch/VA (source
  unspecified) remain out of scope.

---

## Verify

- `make verify` green: every `formal/*.dfy` + `contracts.tsv` rows + a Nim mirror.
- After a load/build, `db_audit` (framing/round-trip/order + `^LINK` symmetry +
  df probes) is wired into `rebuild_fst_full.sh` step 5.
