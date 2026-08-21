# ANSI/ISO M Conformance Critical Path

**Goal:** Close all 13 cross-implementation conformance failures (103-test suite,
`tests/mumps_cross_conformance.py`). Baseline: RSM 100%, RFC 100%, NimM 87.4%
(identical failure set on macOS x86_64 and Linux x86_64/gcc15 — confirmed pure
language bugs, not platform issues).

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
