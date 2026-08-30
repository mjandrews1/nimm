# Contracts — Dafny models ↔ Nim runtime mirrors

Every `formal/*.dfy` model states a property that the NimM source must satisfy.
Each *lemma* is mirrored by a Nim test/contract that asserts the same property
on the real code at runtime. The machine-readable, per-lemma manifest is
`formal/contracts.tsv`; `check_contracts.sh` enforces it in CI (every lemma
listed, no stale rows, every mirror present).

| Model | Proves | Nim mirror (runtime) |
|---|---|---|
| `collation.dfy` | `mCollationCmp` reflexive/skew/transitive | `tests/test_collation.nim` |
| `key_encoding.dfy` | type-byte framing + `decode∘encode == id` | `tests/test_encoding_roundtrip.nim`, `tests/test_key_encoding.sh` |
| `numeric_encoding.dfy` | 9's-complement order + inverse | `tests/test_encoding_roundtrip.nim` |
| `globals_order.dfy` | `$ORDER` successor minimal + next-element | `tests/test_order_lmdb.sh` |
| `order_pairs.dfy` | multi-level `$ORDER` candidate order | `tests/test_order_lmdb.sh` |
| `txn_overlay.dfy` | overlay write/kill + nested `$TLEVEL`/rollback | `tests/test_txn_lmdb.sh`, `tests/test_txn_reads.sh` |
| `pattern.dfy` | pattern alternation match semantics | `tests/test_pattern.nim`, `tests/ansi_iso_m_conformance.py` |
| `value_format.dfy` | `formatNumber` canonical (no leading zero) | `tests/test_property_fuzz.nim`, `value.nim` (inline assert) |
| `data_tristate.dfy` | `$DATA` 0/1/10/11 tri-state | `tests/test_contracts.nim` |
| `scope_stack.dfy` | NEW/QUIT discipline + multi-level propagate | `tests/test_contracts.nim`, `globals.nim` (inline assert) |
| `bytecode_stack.dfy` | operand-stack discipline (expr/stmt invariants) | `tests/test_vm_table.nim` |
| `bytecode_bisim.dfy` | compiled bytecode ≡ AST (core language) | `tests/test_bytecode_conformance.sh` |
| `entry_term_expansion.dfy` | FST dict+BM25 merge dedup/dict-first | `tests/test_bm25_m.sh` |
| `bm25.dfy` | BM25 idf/tfNorm + `SEARCH` top-K | `tests/test_bm25_m.sh` |
| `hybrid_merge.dfy` | RRF fusion positive/monotone rerank | `tests/test_hybrid_rrf.nim` |
| `vm_opcodes.dfy` | concrete opcode Pops/Pushes table + compiler safety | `tests/test_vm_table.nim` |

## Runtime-mirror kinds
- **test** — a `tests/test_*.nim`/`*.sh` asserts the property on the real code.
- **contract** — a debug-only `assert` in a source file (active unless `-d:release`).
- **fuzz** — seeded randomized property test.
- **conformance** — validated against frozen RSM/RFC baselines.

## Invariant
`make verify` runs `dafny` on all models (proof), the full test suite (runtime
mirrors), and `check_contracts.sh` (that no model or mirror has drifted).
