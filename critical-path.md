# nimm Critical Path

**Canonical critical path:** GitHub issue [#454](https://github.com/mjandrews1/nimm/issues/454)
("Critical path: FST design — formal spec first, Nim core + NimM/Python helpers").
The issue tracker is authoritative; this file is the human-readable plan.

**Remotes:** GitHub (`origin`) and Utility-01 (`/home/mark/nimm`, synced via
pull). GitLab is deprecated.

**Current state (2026-09-02):**
- Formal verification: **32 Dafny model sets, 305 lemmas**, `make verify` green.
- Test suite: **75 tests passing**.
- FST search pipeline complete and validated end-to-end. All four sources loaded
  and BM25-indexed on Utility-01:

  | Source | Docs | Tokens | avgdl |
  |--------|------|--------|-------|
  | MeSH | 31,110 | 989,742 | 31.81 |
  | CatLine | 1,240,758 | 11,918,897 | 9.61 |
  | SerLine | 150,942 | 790,134 | 5.23 |
  | PubMed | 2,970,000 | 325,288,042 | 109.52 |

- BM25 index build is Nim `buildIndex` (batched flush, #457); M `BUILD*`/`SCORE`/
  `SEARCH` retired from `bm25idx.m` (only `DICT` remains). `build_bm25.nim` CLI,
  `--readonly` reader path, and `^BM25PROG` high-water mark all landed (#458).

## Open issues

| # | Issue | Language (primary) |
|---|-------|--------------------|
| #462 | SELECT-only SQL layer | Nim (compiler) → M or Nim (emitted) |

Completed: #459 MeSH-outbound ^LINK graph, #465 CATLINE→SERLINE serial,
#466 PUBMED→SERLINE journal (NlmUniqueID), #460 Dafny gaps, #461 NOSYNC
measurement, #463 retrieval introspection. #467 ISSN fallback measured as a
0.0003% gain → won't do.

---

## Remaining work — #459: `^LINK` cross-references

The only cross-reference in the DB is `^LINK("PUBMED", pmid, "MESH", dui) =
"mesh_term"` — the wrong direction (should be MESH→PUBMED), and redundant with
the per-record `^PUBMED(pmid,"meshUI",dui)` subscript. MeSH↔CatLine and
MeSH↔SerLine links do not exist.

**Design decision (agreed):** links are **MeSH-outbound, not bi-directional**.
LMDB range-scans only from the left, and every FST query is "given a MeSH term,
find the related records", so the hub is MeSH:

```
^LINK("MESH", descUI, "PUBMED",  pmid)  = "mesh_term"
^LINK("MESH", descUI, "CATLINE", nlmID) = "subject"
^LINK("MESH", descUI, "SERLINE", nlmID) = "serial"
```

Reverse lookups (citation→MeSH, journal→MeSH, serial→MeSH) stay on the per-record
subscripts, which are already cheap (record id is the first subscript):

```
^PUBMED(pmid,   "mesh", descUI) = "1"   ; currently "meshUI" (rename)
^CATLINE(nlmID, "mesh", descUI) = "1"   ; missing
^SERLINE(nlmID, "mesh", descUI) = "1"   ; missing
```

**Design validated in Dafny** — `formal/link_consistency.dfy` (commit ee521dd)
proves the four core properties: forward/reverse consistency under link/unlink,
idempotent dedup, name→UI resolution soundness (no dangling links), and query
duality (bi-directional storage unnecessary). Mirror `tests/test_link_consistency.nim`.

**Implemented** (commit 8e030ea) — MeSH-outbound links written by the loaders:

- [x] MeSH → CatLine `subject` + MeSH → SerLine `subject` — resolve MeSH 6xx
      headings (600/610/611/630/650/651/655, ind2="2") to UI via `^MESHTERM`, write
      `^LINK("MESH",dui,type,nlmID)` + per-record `"mesh"` subscript.
- [x] `mesh_term` direction flipped to MESH→PUBMED.
- [x] `meshUI` → `mesh` rename.
- [x] `resolveName` prefers exact name ("1"), then unique synonym ("0").
- [x] Load high-water mark: `^FST("load",file)` advances `in-progress:N` per flush
      (commit 0aa8662), landing on `complete:N` — O(1) load observability.

### Remaining (record-to-record links)

- [x] **PubMed re-load + stale cleanup** — done (commit 3983fc5 era); all four
      sources now use the MeSH-outbound scheme and verified via db_audit.
- [ ] **#466 PUBMED→SERLINE `journal`** — join on `NlmUniqueID` (PubMed supplies
      it; literature confirms NLM links citations to journal serials by id, not
      title). Loader must extract `<NlmUniqueID>` from `<MedlineJournalInfo>`.
- [ ] **#465 CATLINE→SERLINE `serial`** — join on `issn` (`022 $a`), not NLMID.

### Dafny modeling gaps (#460)

Three source modules touched this session have no Dafny model:

1. **`global_bm25.nim` buildIndex** — df-batching equivalence (in-memory dfDelta ==
   per-term read-modify-write), re-run idempotency (^BM25LEN skip), high-water
   mark monotonicity. Highest priority.
2. **`xmlload.nim` resolveName** — `link_consistency.dfy` models `resolve` opaquely;
   the concrete preference rule (exact "1" → unique synonym "0") is unproven.
3. **`storage/lmdb_store.nim` read-only path** — reader-never-blocks-writer, write
   raises, write-txn read-back (#359/#368).

### Other open items

- **#461** NOSYNC-for-build / SYNC-for-serve durability split (experiment).
- **#462** SELECT-only SQL layer over M globals (experiment).
- **#463** Retrieval introspection (search-explain, raw-key view, query profiling).

### Data blockers (verify before implementing)

- CatLine `650`: 7,059 headings (catplus sample), `ind2="2"`, `$a` only.
- SerLine `650`: 164,070 headings, `ind2="2"`, `$a` only.
- No `$0` authority id in either — name→UI resolution via `^MESHTERM` is required.

### Verify

- `make verify` stays green (each `formal/*.dfy` + `contracts.tsv` rows + a Nim mirror).
- After a re-load, assert `$D(^LINK("MESH"))` = 10 (has children) and spot-check
  `^LINK("MESH",dui,"CATLINE"/"SERLINE"/"PUBMED",id)` for known descriptors.

---

## Standing policies
- **RSM source is frozen** — no development changes; the sole reference engine.
- **RFC deprecated** — RSM is the reference engine.
- **Utility-02 deprecated** — all roles on Utility-01.
- **nimm v0.1.0 frozen** (tag `v0.1.0`); development continues on v0.1.x.
