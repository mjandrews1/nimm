# ANSI/ISO M Conformance Critical Path

**Goal:** Close all 13 cross-implementation conformance failures (103-test suite,
`tests/mumps_cross_conformance.py`). Baseline: RSM 100%, RFC 100%, NimM 87.4%
(identical failure set on macOS x86_64 and Linux x86_64/gcc15 — confirmed pure
language bugs, not platform issues).

> **STATUS: Phase 1 complete (44a8ede). 103/103 everywhere; issues #247-#254 closed.
> Superseded by the ANSI/ISO suite below.**

---

# ANSI/ISO M Suite — 170 Tests (`tests/ansi_iso_m_conformance.py` @ 9e9bea9)

## Frozen Reference Baselines

RSM and RFC are **frozen** as stable reference points. All development happens
on NimM V0.1.3; re-test against the frozen references only.

| Implementation | Source commit | macOS binary sha256 | Linux binary sha256 |
|---|---|---|---|
| RSM V1.83.1 | `17458f03cf` | `996b9e69…a0d82f` | `47082d4b…8e5c63c8` |
| RFC V1.83.1 | `ff9c938222` | `a493046a…5d03f346`* | `34ad9530…3af346`* |

\* RFC macOS build additionally carries the local gcc-compat patch from rfc#11.

Results matrix (identical failure sets across machines, verified by diff):
RSM 153/170 (90.0%) · RFC 153/170 (90.0%) · NimM 135/170 (79.4%).
The 17 shared RSM/RFC failures are frozen-in findings (rsm#11-15, rfc#12);
NimM's target is 135 → 170/170 since it already passes the comparison tests.

## Final Matrix — af36717 (2026-08-21)

Isolation protocol: daemon up → suite → daemon down between implementations.
Identical sources on both machines (tree `04a7b18f`). RSM/RFC failure sets are
byte-identical across machines (`diff` clean) and identical between RSM/RFC.

| Implementation | MacBook Pro (macOS x86_64) | Utility-01 (Linux x86_64) |
|---|---|---|
| RSM V1.83.1 | 153/170 (90.0%) · 17F/3E | 153/170 (90.0%) · 17F/3E |
| RFC V1.00.0 | 153/170 (90.0%) · 17F/3E | 153/170 (90.0%) · 17F/3E |
| **NimM V0.1.3** | **170/170 (100%)** | **170/170 (100%)** |

Shared 17 frozen-in failures: BUG03_COLLATE_LOWER, BUG04_COLLATE_MIXED,
BUG05_NUMEQ_FORMS, BUG06_ELSE_RUNS, BUG08_ORD_BACK_EMPTY, BUG09_PAT_ALT,
CMP_CASE, CMP_DIGIT_LETTER, CMP_FRAC_EQ, CMP_FRAC_EQ_STR, CMP_NUM_CANON_EQ,
CMP_PARTIAL_STR, ELSE_RUNS, ORD_BACK_EMPTY, PAT_ALTERNATION, SV_TLEVEL,
SV_TRESTART. (The "3 errors" column entries are the suite's cross-runner
comparisons against implementations not under test — environmental.)

## Timing Matrix — 10 runs × 170 tests (2026-08-21)

TOTAL = sum of per-test wall-clock averages over 10 runs (includes process
spawn + environment attach per test; same methodology everywhere).
Pass/fail identical at run 1 and run 10 on every leg.

| Implementation | MBPR total | Utility-01 total | U1 speedup |
|---|---|---|---|
| RSM V1.83.1 | 2091.86 ms | 794.08 ms | 2.63× |
| RFC V1.00.0 | 2097.40 ms | 819.42 ms | 2.56× |
| **NimM V0.1.3** | **1906.11 ms** | **443.07 ms** | **4.30×** |

NimM is the fastest implementation on both machines while being the only
one at 100%: ~9% faster than RSM/RFC on the MacBook Pro, ~1.8× faster on
utility-01. Raw outputs: `/tmp/timing_{mbpr,u1}_{rsm,rfc,nimm}.txt`
(ephemeral — copy before reboot).

## NimM Fix Plan — Issues #264–#273 (35 failures)

| Pri | Issue | Root cause area | Anchor |
|-----|-------|----------------|--------|
| 1 | #264 truth values | non-empty string ⇒ true; must use numeric-prefix rule §2.2.4 | evaluator truth fn |
| 2 | #265 comma lists | SET `(A,B)=v`, IF `c1,c2`, FOR `v=1,3,5`, NEW `(A,B)` rejected | parser |
| 3 | #271 numeric literals | `.5` parse fail; `-.25` → 0 | lexer |
| 4 | #266 KILL subtree/bare | node kill leaves descendants; bare KILL no-op | globals/engine |
| 5 | #267 MERGE | unimplemented | parser+engine+globals |
| 6 | #268 naked refs | `^(3)` after `^G(1,2)` fails | evaluator/globals |
| 7 | #269 $QUERY/$QS | no empty-subscript start; $QS keeps quotes | evaluator+globals |
| 8 | #270 $X/$Y | never advance | engine/device state |
| 9 | #272 patterns | ?3E, ""?.N, mixed literal seqs | pattern matcher |
| 10 | #273 svars/misc | $ESTACK/$TLEVEL/$TRESTART, $RANDOM range, $HOROLOG shape | special_vars |

Universal findings also affecting frozen references: `$TLEVEL`/`$TRESTART`
(rsm#15), backward `$ORDER` empty start (rsm#14) — NimM fixing these exceeds
the references' 90.0%.

## Failure → Root-Cause Map

| # | Test(s) | Symptom | Root cause | Anchor |
|---|---------|---------|-----------|--------|
| 1 | QUIT_TOPLEVEL, NEW_RESTORE | Top-level `QUIT` pops NEW scope then *continues* the line | `cQuit` conflates NEW-scope frames with DO-frame depth; no top-level halt | engine.nim:247-256 |
| 2 | KILL_SELECTIVE | `KILL (A,B)` does nothing | `CmdKind.cKillExcept` parsed but executor has no case for it | parser.nim:1193, engine.nim:264-276 |
| 3 | FN_ASCII_POS | `$ASCII("ABC",2)`→65 not 66 | position argument ignored entirely; always reads byte 0 | evaluator.nim:334-337 |
| 4 | FN_ASCII_NEG | `$ASCII("",1)`→"" not -1 | empty string returns "" instead of `-1` | evaluator.nim:335 |
| 5 | FN_EXTRACT_ONE | `$EXTRACT("ABCDE",3)`→"CDE" not "C" | 2-arg form treated as range start, not single position | evaluator.nim:346-358 |
| 6 | FN_EXTRACT_FIRST | `$EXTRACT("ABCDE")`→whole string not "A" | missing-arg case falls to full-length copy | evaluator.nim:346-358 |
| 7 | FN_FIND_POS | `$FIND("ABCDE","CD",3)`→0 not 5 | 1-based M start passed directly to Nim's 0-based `find` | evaluator.nim:360-366 |
| 8 | FN_ORDER_LAST, GLOB_ORDER | `$ORDER(last)` wraps instead of returning "" | callFunction drops subscripts (`@[]`); orderLocal then returns first key | evaluator.nim:409, globals.nim:131-174 |
| 9 | SV_IO | `$IO`→"stdout" not "0" | special-var registered with hostname-ish default | special_vars.nim:89-93 |
| 10 | GLOB_SUBSCRIPTS | `^G(1,2)` set/get silent no-op | `dbPath==""` → setGlobal/getGlobal early-return; plain `^A` accidentally aliases to local via `setLocalDirect` | globals.nim:166-181, engine.nim:108-111 |
| 11 | GLOB_KILL | `$DATA(^G)` after KILL → "" not 0 | same no-db no-op path; KILL deletes nothing, DATA reads nothing | globals.nim:234-242 |

Eleven failures collapse into **seven fixes** (rows 5+6 share one rewrite; rows
8a/8b are one fix; row 10+11 are one fix).

---

## Fix Order (impact ÷ effort, dependency-aware)

### Phase 1 — Mechanical, zero-risk (~1h total)

**F1. $EXTRACT semantics** — evaluator.nim:346-358, rewrite:
- `$E(s)` → first char (`s[0..1]`)
- `$E(s,n)` → one char at n ("" if out of range)
- `$E(s,n,m)` → chars n..m inclusive (end < start → "")
Standard ref: §8.4. Keep cached-length guard for empty-string fast path.

**F2. $ASCII position + sentinel** — evaluator.nim:334-337:
- read `args[1]`, clamp: pos<1 or pos>len or s=="" → `-1`
- return `$int(uint8(s[pos-1]))`
Standard ref: §8.3.

**F3. $FIND start conversion** — evaluator.nim:362: change
`parseInt(args[2])` → `parseInt(args[2]) - 1` before `s.find`. One-line.
Standard ref: §8.9.

**F4. $IO device ID** — special_vars.nim:89: return `"0"` ($PRINCIPAL device
number per §7.2). Keep `io` variable only if Z-device tracking needs it later.

### Phase 2 — Executor logic (~2-3h)

**F5. Top-level QUIT halt** — engine.nim:247-256:
- Track DO/XECUTE/extrinsic frame depth separately from NEW scopes
  (add `doDepth: int` to Engine).
- `cQuit`: if `doDepth > 0` → pop one frame, return quit value (current behavior).
  If `doDepth == 0` → unwind ALL NEW scopes (restore values), then return
  hard-stop sentinel consumed by both `execute()` loop and the `-x` driver in
  main.nim:112-114.
- FOR-loop QUIT (engine.nim:222,238) keeps existing frame semantics — verify
  FOR_QUIT still passes after change.
Standard ref: §10.3 (QUIT terminates execution at command level; top level ends run).

**F6. Exclusive KILL** — engine.nim:264-276, add `of CmdKind.cKillExcept`:
- Snapshot keys of top scope; delete every local whose base var name ∉ keep-list;
  also kill all globals (exclusive KILL spans locals AND globals per §12.2).
- Globals side: iterate LMDB keys (store.listKeys exists) deleting those not kept.
- Postcond already handled by shared path.

### Phase 3 — Storage correctness (~3-4h)

**F7. $ORDER subscript passthrough** — two parts:
1. evaluator.nim:406-409: `$ORDER` must receive a *variable reference*, not an
   evaluated string. Parser must mark ORDER/DATA/NEXT/QUERY arg[0] as naked-ref
   (reuse existing `nakedGlobal`/`nakedSubs` machinery, globals.nim:21-22):
   eval sets them from the inner var expr before dispatching.
2. After passthrough, orderLocal's wraparound disappears naturally: with real
   `lastSub`, the `k > lastSub` scan falls through to `return ""` (globals.nim:169)
   — already correct once fed correct input.
- Apply same fix to `$DATA`/`$QUERY` call sites (they share the dropped-subs bug
  even though current tests don't catch it).
Standard ref: §8.14 ($ORDER null terminator).

**F8. Global storage fallback (no `-db` mode)** — biggest item:
1. Add in-memory global store to `Globals` (Table[string,string] keyed by
   `makeKey`) used when `dbPath == ""`; route getGlobal/setGlobal/killGlobal/
   order/listSubs/data through it. Removes the silent no-op AND the accidental
   `setLocalDirect("^NAME")` aliasing (delete that fallthrough in engine.nim:110).
   - Reuse lmdb_store.nim key encoding so switching `-db` on/off is transparent.
2. Fix `$DATA` for globals to distinguish node-with-value (1) vs
   descendants-only (10/11) — currently boolean-only (globals.nim:234-242);
   required for GLOB_KILL and future conformance rounds.
3. Decide policy: document that bare `nimm -x` uses ephemeral memory store;
   persistence requires `-db file`. (Matches how tests invoke it today.)
Standard ref: §8.5 ($DATA tri-state), §13 (global storage).

---

## Verification Protocol

Per fix:
```
nim c -d:release -o:nimm main.nim && ./nimm -x '<target snippet>'
./nimm -t   # internal suite must stay 60/60
python3 tests/mumps_cross_conformance.py --impls nimm --failures
```

Full gate after each phase (isolation discipline applies — kill daemons between impls):
```
# macOS + utility-01, identical commits:
python3 tests/mumps_cross_conformance.py --impls rsm --runs 3   # daemon up
python3 tests/mumps_cross_conformance.py --impls rfc --runs 3   # after killing rsm
python3 tests/mumps_cross_conformance.py --impls nimm --runs 3  # standalone
```
Expected trajectory: 90 → 96 (Phase 1) → 99 (Phase 2) → 101 (F7) → **103 (F8)**.

## Issue Wiring

| Fix | Closes |
|-----|--------|
| F1+F2+F3 | #247, #248, #249 |
| F4 | #252 |
| F5 | QUIT items inside #254 |
| F6 | #251 |
| F7 | #250 |
| F8 | #253 |

Close #254 (tracking) last, with final three-machine matrix attached.

## Risks

- **F5** is the only behavioral overlap with working tests (FOR_QUIT, NEW_BASIC);
  regression-prone. Land with dedicated unit cases: QUIT in FOR-in-DO,
  QUIT at depth 2, QUIT with value at top level.
- **F7** naked-ref plumbing touches parser+evaluator contract; keep the change
  behind the existing four function names only.
- **F8.2** ($DATA tri-state) may surface latent test expectations of "1" where
  standard says 10/11 — audit test_conformance.nim before flipping.

## Extended Matrix — 18 tests × 10 runs (2026-08-21 evening)

New suite: `tests/mumps_extended_conformance.py`. Categories: SSV (^$JOB,
^$LOCK, ^$GLOBAL), Std99 extras not in the 170-test suite (indirection forms,
$QLENGTH, FOR lists, MERGE preservation, $TRANSLATE/$REVERSE, negative
$JUSTIFY, $ECODE), RSMExt (exponent notation, numeric-first collation).
Expected values = RSM ∩ RFC consensus (both references agree on all 18).
Isolation protocol held on both machines: one daemon up per leg, verified
down before the next.

| Implementation | MBPR (macOS x86_64) | Utility-01 (Linux x86_64) | U1 speedup |
|---|---|---|---|
| RSM V1.83.1  | 18/18 · 218.0 ms | 18/18 · 78.2 ms | 2.79× |
| RFC V1.00.0  | 18/18 · 226.6 ms | 18/18 · 80.1 ms | 2.83× |
| **NimM**     | **12/18 · 200.0 ms** | **12/18 · 24.2 ms** | **8.26×** |

NimM failure set byte-identical across machines (6):
- SSV_JOB_SELF — ^$JOB returns 0 (unimplemented)
- SSV_LOCK_TAKE — LOCK/^$LOCK missing → empty output
- IND_EXPR — expression indirection @A unsupported → empty
- MERGE_PRESERVE — CRASH RangeDefect (formatNumber via setGlobal, MERGE
  overwrite of scalar root)
- FN_JUSTIFY_NEG — CRASH RangeDefect ($JUSTIFY negative width)
- EXP_NUM_PLUS — +'2E3' unevaluated

The two crashes are new (not in #264–#273): #276 MERGE-overwrite
crash, #277 $J-negative-width crash. SSV gaps: #278. Indirection:
#279. Exponent notation: #280.

Note: rfc client reads RSM_DBFILE only (shared rsm client code) — suite's
RFCEngine now points both vars at the RFC environment.
