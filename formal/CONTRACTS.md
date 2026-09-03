# Contracts — Dafny models ↔ Nim runtime mirrors

Every `formal/*.dfy` model states a property that the NimM source must satisfy.
Each *lemma* is mirrored by a Nim test/contract that asserts the same property
on the real code at runtime. The machine-readable, per-lemma manifest is
`formal/contracts.tsv`; `check_contracts.sh` enforces it in CI (every lemma
listed, no stale rows, every mirror present).

| Model | Proves | Nim mirror (runtime) |
|---|---|---|
| `collation.dfy` | `mCollationCmp` reflexive/skew/transitive | `tests/test_collation.nim` |
| `command_bisim.dfy` | KILL/MERGE/WRITE/QUIT/DO/GOTO bytecode ≡ AST | `tests/test_bytecode_conformance.sh` |
| `control_flow_bisim.dfy` | IF/ELSE bytecode ≡ AST (pc-based VM) | `tests/test_bytecode_conformance.sh` |
| `data_structures.dfy` | `$NI_*` stack/queue/heap/trie/graph/LRU/bitset invariants | `tests/test_data_structures_invariants.nim` |
| `key_encoding.dfy` | type-byte framing + `decode∘encode == id` | `tests/test_encoding_roundtrip.nim`, `tests/test_key_encoding.sh` |
| `numeric_encoding.dfy` | 9's-complement order + inverse | `tests/test_encoding_roundtrip.nim` |
| `numeric_prefix.dfy` | `numPrefix`/`truthy` prefix grammar + truth table | `tests/test_truthy.nim` |
| `globals_order.dfy` | `$ORDER` successor/predecessor minimal + next-element, `$QUERY` DFS | `tests/test_order_lmdb.sh`, `tests/test_zwrite.sh` |
| `order_pairs.dfy` | multi-level `$ORDER` candidate order | `tests/test_order_lmdb.sh` |
| `txn_overlay.dfy` | overlay write/kill + nested `$TLEVEL`/rollback | `tests/test_txn_lmdb.sh`, `tests/test_txn_reads.sh` |
| `pattern.dfy` | pattern alternation match semantics | `tests/test_pattern.nim`, `tests/ansi_iso_m_conformance.py` |
| `value_format.dfy` | `formatNumber` canonical (no leading zero) | `tests/test_property_fuzz.nim`, `value.nim` (inline assert) |
| `data_tristate.dfy` | `$DATA` 0/1/10/11 tri-state | `tests/test_contracts.nim` |
| `scope_stack.dfy` | NEW/QUIT discipline + multi-level propagate | `tests/test_contracts.nim`, `globals.nim` (inline assert) |
| `special_vars.dfy` | `$STACK`/`$ZLEVEL` depth + `$TEST` truth flag | `tests/test_special_vars.sh` |
| `string_functions.dfy` | `$LENGTH`/`$EXTRACT`/`$FIND`/`$PIECE` (single+multi)/`$TRANSLATE`/`$JUSTIFY`/`$FNUMBER` | `tests/test_string_functions.sh` |
| `functions_more.dfy` | `$GET`/`$CASE`/`$SELECT`/`$QLENGTH`/`$REVERSE` | `tests/test_string_functions.sh` |
| `subscript_bisim.dfy` | subscripted read/write (`opPushVarSub`/`opSetVarSub`) ≡ AST | `tests/test_bytecode_conformance.sh` |
| `bytecode_stack.dfy` | operand-stack discipline (expr/stmt invariants) | `tests/test_vm_table.nim` |
| `bytecode_bisim.dfy` | compiled bytecode ≡ AST (core language) | `tests/test_bytecode_conformance.sh` |
| `entry_term_expansion.dfy` | FST dict+BM25 merge dedup/dict-first | `tests/test_semantic_eval.sh` |
| `engine_execution.dfy` | DO/QUIT call-stack + $ETRAP cap + label dispatch | `tests/test_etrap.sh`, `tests/test_bytecode_conformance.sh` |
| `for_loop_bisim.dfy` | FOR loop bytecode ≡ AST (body + step + back-edge) | `tests/test_bytecode_conformance.sh` |
| `bm25.dfy` | BM25 idf/tfNorm + `$NI_SEARCH` top-K | `tests/test_global_bm25.nim` |
| `build_index.dfy` | df-batching == recompute, re-run idempotency, high-water-mark monotonicity | `tests/test_bm25_build_nim.nim` |
| `hybrid_merge.dfy` | RRF fusion positive/monotone rerank | `tests/test_hybrid_rrf.nim` |
| `hnsw.dfy` | HNSW neighbor symmetry + bounded degree + cosine | `tests/test_hnsw_invariants.nim` |
| `link_consistency.dfy` | FST ^LINK forward/reverse consistency, idempotent dedup, name→UI soundness (exact→synonym preference), query duality | `tests/test_link_consistency.nim` |
| `readonly_path.dfy` | read-only handle is pure, views agree, write-then-read, absent-key default | `tests/test_lmdb_readonly.nim` |
| `query_semantics.dfy` | SELECT scan soundness/completeness, order-preservation (free ORDER BY), LIMIT prefix/bound, point-lookup count | `tests/test_ni_sql.nim` |
| `reporter_link.dfy` | PUBMED→REPORTER funding-link consistency, idempotent dedup, query duality | `tests/test_reporter_link.nim` |
| `supp_concepts.dfy` | SCR star-strip normalization (bare DUI), MESH→SUPP link/unlink consistency + idempotency + query duality | `tests/test_supp_concepts.nim` |
| `search_engine.dfy` | FST index consistency + docId↔vecId bijection | `tests/test_fst_consistency.nim` |
| `lock_semantics.dfy` | `heldLocks` acquire/release/release-all | `tests/test_locks.nim` |
| `network.dfy` | network connection table (fresh id / close-removes / count / closeAll) | `tests/test_network_invariants.nim` |
| `orangebook_link.dfy` | Orange Book ingredient→SCR exact-name join (unambiguous resolve, consistency, idempotency) | `tests/test_orangebook.nim` |
| `m_programs.dfy` | M scripts (`samples/*.m`, `tests/*.m`, FST, ERIC) meet their specs | `tests/test_m_programs.sh` |
| `vm_opcodes.dfy` | concrete opcode Pops/Pushes table + compiler safety | `tests/test_vm_table.nim` |

## Runtime-mirror kinds
- **test** — a `tests/test_*.nim`/`*.sh` asserts the property on the real code.
- **contract** — a debug-only `assert` in a source file (active unless `-d:release`).
- **fuzz** — seeded randomized property test.
- **conformance** — validated against frozen RSM/RFC baselines.

## Invariant
`make verify` runs `dafny` on all models (proof), the full test suite (runtime
mirrors), and `check_contracts.sh` (that no model or mirror has drifted).
