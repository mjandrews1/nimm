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
2. **#468 — Boolean search** (in progress). Formal + engine + `$NI_BOOL` +
   `^BMPOS` all committed and green; `^BMPOS` backfill for PubMed is running on
   Utility-01.
3. **#470 — Data freshness**: define per-source refresh cadence (user lean:
   week/month/quarter) and a scheduler; PubMed needs its baseline re-downloaded
   to completion (99/1200 files ≈ 18%).
4. **#469 — BioArxiv** data source (stub).
5. **#472 / #473 — Theory of Operation** for NimM / FST (docs).
6. **#471 — Odin experiment** (curiosity only).

### Blocked (need external input)

- **RxNorm → SCR** needs a UTS API key (UNII codes live only in the licensed
  full release; the unlicensed "prescribable" release has none).
- **PubMed baseline completion** (~1200 files; only 99 staged) — re-download.
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
