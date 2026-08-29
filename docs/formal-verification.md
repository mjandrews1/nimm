# Formal Verification — NimM scope, tool choice, invariants

## Goal

Describe NimM's *correctness-critical, pure* behavior in a machine-checkable
form, and prove the invariants that have historically caused bugs. This is a
**model of the spec**, not an end-to-end proof of the ~10k-line interpreter
(which mixes FFI, mutation, a global state machine, and a bytecode VM that no
practical verifier can ingest today).

## What we actually verify vs. test

| Layer | Method | Status |
|---|---|---|
| Algorithms (collation, framing, ordering, txn overlay) | Dafny model + lemmas | started (`formal/key_encoding.dfy`) |
| Implementation ↔ model | property tests (`test_encoding_roundtrip.nim`) + conformance | in place |
| Whole-interpreter behavior | ANSI/ISO conformance (179 tests) + differential/parity tests | in place |

The conformance + property + differential suites are the **executable spec**;
the Dafny model is the **proof layer** for the small pure core where the bugs
actually were (#356 nested `$ORDER`, #394/#397 subscripts/ordering, #396
overlay reads).

## Tool choice

- **Dafny + Z3** (Z3 4.16 is installed): verification-aware language with
  `function`/`lemma`, good for total functions over algebraic datatypes and
  sequences — exactly the shape of the key-encoding/collation code.
- **Rejected**: DrNim (Nim-native Z3 analyzer — dormant, tiny subset), Coq/Lean
  (full power but high cost for this scope), F* (heavier setup), CBMC (would
  require a C translation of the FFI layer).

## Model / implementation boundary

The model abstracts the one thing that is not faithfully modelable and is also
not the point:

- **Numbers are modeled as exact scaled integers** (`Num(scale)`, value =
  `scale / 10^12`). The Nim `encodeNumeric` uses `float64 * 1e12`, exact only
  for integers ≤ 2^53. The model asserts the *intent*; the Nim round-trip test
  pins the float behavior over the canonical domain.
- **9's-complement negative encoding** is an implementation trick that makes
  byte-order coincide with numeric-order; the model proves the *order* directly
  rather than the byte trick.

## Invariants to prove (by priority)

1. **Framing round-trip** — `Decode(Encode(g, subs)) == (g, subs)`. This is the
   AGENTS.md "unambiguous separators" rule, formalized: each type byte
   (`0x00`/`0x01`/`0x02`) unambiguously delimits its data. (Done: structural
   injectivity in `EncodeInjective`; numeric body via `NumCodecRoundTrip`.)
2. **Collation total order** — `mCollationCmp` is antisymmetric, transitive,
   and total, with `Empty < Num < Str`, numeric by value, string lexicographic.
   (Done: `CmpAntisymmetric`, `CmpTransitive`, `CmpInRange`.)
3. **`$ORDER`/`$QUERY` §9.9 + DFS pre-order** — `orderPairs`/`queryPairs`
   (globals.nim) return the correct successor/predecessor, and backward-from-
   null returns empty. (Next.)
4. **Transaction overlay monotonicity** — `txnSubs` merges writes/kills so that
   reads see the innermost level; kills remove node + descendants. (Next.)
5. **Pattern matching termination + whole-string consumption** — `matchPattern`
   is total and matches only if the entire string is consumed. (Next.)

## Roadmap

- [x] Mark `storage/key_encoding.nim` functions `func` (enforce purity at compile time).
- [x] `formal/key_encoding.dfy` — framing + collation model and lemmas.
- [ ] Install/verify Dafny (or CI with `dafny verify`), tighten proof bodies.
- [ ] Model `orderPairs`/`queryPairs` + txn overlay (`formal/globals_order.dfy`).
- [ ] Model pattern matching (`formal/pattern.dfy`).
- [ ] Wire a `make verify` target that runs Dafny + the property tests together.

## Non-goals

- Proving the whole evaluator/engine/VM (infeasible; covered by conformance).
- Verifying the LMDB C FFI (covered by the store-parity + crash-recovery tests).
- Reimplementing M semantics in a proof assistant (only if a reference oracle
  is ever wanted).
