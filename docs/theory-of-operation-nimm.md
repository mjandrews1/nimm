# NimM — Theory of Operation

**What this is:** a reference for resuming work on NimM — the M/MUMPS
interpreter/compiler in this repo. It explains *why* things are the way they
are (invariants and decisions), not just the API surface. Companion to
`AGENTS.md` (conventions), `critical-path.md` (plan), and `docs/formal-verification.md`.

## 1. What NimM is

NimM is `nimm` — an M/MUMPS interpreter with a bytecode-compiling VM, written
in Nim, backed by an LMDB store for global variables. It is a *reference
implementation*: RSM is the frozen reference engine, and NimM tracks it
conformance-wise. M is the query surface in this project's larger FST stack
(see the FST theory), but NimM is a standalone interpreter too.

## 2. Layered architecture

```
 M source text
   → lexer.nim   (tokens: M has a character-level, context-sensitive syntax)
   → parser.nim  (AST: Line / Expr / var-name + subscripts)
   ↘ engine.nim  (AST interpreter: execute(Line) → evaluator calls)
   ↘ compiler.nim+bytecode.nim+vm.nim (bytecode compile → stack-machine VM)
   ↓
 evaluator.nim   callFunction() — expression evaluation, $FUNCTION dispatch,
                 the $NI_* intrinsics
   ↓
 globals.nim     Globals — locals/globals, scoping, transaction overlay
   ↓
 storage/lmdb_store.nim + storage/key_encoding.nim  — LMDB + M-collation keys
```

Two execution paths exist and are **bisim-tested** against each other
(`bytecode_bisim.dfy`, `control_flow_bisim.dfy`, `for_loop_bisim.dfy`): the AST
interpreter (`engine.execute`) and the bytecode VM (`vm.nim`). The bytecode VM
only runs via `DO`+`--bytecode`, never `-x` (a deliberate rule so the two paths
stay separately exercisable).

## 3. The execution model

- `runtime.nim` holds the `Mode` enum (`Strict` / `RSM` / `nimm`) — the conformance
  stance. `nimm` mode enables the `$NI_*` extensions (`allowExtensions`); `Strict`
  is ANSI/MDC X11.1-1995 (ISO/IEC 11756:1999).
- `engine.execute(Line, depth)` is the AST entry; `depth` tracks `DO` nesting for
  `$ETRAP` / label / line dispatch. `runRoutineBytecode` is the VM entry.
- `evaluator.callFunction` is the single dispatch point for intrinsic
  (`$FUNCTION`) evaluation — arithmetic, strings, and the `$NI_*` family. This is
  where `$NI_SEARCH`/`$NI_EXPLAIN`/`$NI_PROFILE`/`$NI_SQL`/`$NI_BOOL` live.

## 4. Storage: Globals over LMDB

`globals.nim` presents M variables as a single `Globals` object:

- **Locals** are a scope stack (`scopes: seq[Table]`) with `NEW`/`QUIT` copy-on-
  write sharing (`scopeShared`) and writer tracking for propagation on scope exit
  (`scopeWrittenVars` — the `scope_stack.dfy` contract).
- **Globals** are `^name` keys in an `LmdbStore`. Reads/writes route through
  `get`/`set` which first consult the **transaction overlay** (read-your-own-writes).
- **Transactions** (`TSTART`/`TCOMMIT`/`TROLLBACK`) buffer writes/kills in a
  `TransactionState.level` stack and batch-persist on the final `TCOMMIT`
  (`txn_overlay.dfy`).

### Key encoding (`storage/key_encoding.nim`) — the critical invariant

Globals are serialized to LMDB keys with **unambiguous type-byte framing**:

```
 global \x00 (type+data)*
   \x00 = empty string   \x01 = number (sign + 18 digits)   \x02 = string (\x00-terminated)
```

The type byte alone fixes each subscript's length, so there is **no overloaded
separator** — this is the fix for the #356 nested-`$ORDER` corruption (a prior
frame's `\x00` meant separator *and* empty-string *and* terminator *and* trailing
marker). M-collation order (empty < number < string, numbers by value, strings
lexicographic) is preserved so `$ORDER` is a cursor scan. `key_encoding.dfy` +
`numeric_encoding.dfy` prove round-trip and order; `test_encoding_roundtrip.nim`
and `auditScan` (db_audit) re-check it at runtime over the live DB.

### The read path that matters

- `--readonly` opens LMDB `MDB_RDONLY` so a reader never blocks a writer
  (`readonly_path.dfy`) — this is what lets search/audit run while a loader or
  index build holds the write txn.
- `--nosync` (`MDB_NOSYNC`) is for disposable writes (load/build); `--mapsize` /
  `NIMM_MAPSIZE` raise the LMDB ceiling (the default 50 GB was hit as
  `MDB_MAP_FULL`, #462).
- `$ORDER`/`$QUERY`/`$DATA` over globals are thin wrappers over LMDB cursors;
  the write-txn read-back case (reads during a write batch) is handled because
  opening a second txn on the same env deadlocks (#359/#368).

## 5. Conformance stance

- RSM is the frozen reference engine; RFC is deprecated.
- The executable spec is the conformance suite: `tests/ansi_iso_m_conformance.py`,
  `mumps_cross_conformance.py`, `mumps_extended_conformance.py`, plus `test_*.sh`
  parity tests. This is *stronger than* a Dafny spec of the parser — see
  `docs/formal-verification.md` ("what we verify vs test").

## 6. Formal-verification discipline

Every correctness-critical, *pure* subsystem has a `formal/*.dfy` model, and
every non-`support` lemma has a Nim mirror test; `formal/contracts.tsv` is the
authoritative manifest and `check_contracts.sh` enforces it (41 models, 364
lemmas as of this writing). The models cover: collation/key-encoding, `$ORDER`/
`$QUERY` successor semantics (`globals_order.dfy`), the txn overlay
(`txn_overlay.dfy`), `$DATA` tri-state, scope stack, bytecode↔AST bisimulation,
`$PIECE`/`$EXTRACT` string funcs, and the FST's own models (see FST theory).

## 7. Build & test

- `make build` → `nim c -d:release -o:bin/nimm main.nim`.
- `make test` → `bash tests/run_all.sh` (rebuilds + all shell/nim suites).
- `make formal` → `formal/verify.sh` (Dafny) + `check_contracts.sh`.
- `make verify` → both.
- **Binaries live in `bin/` only.** Never commit a compiled binary anywhere else.

## 8. Key historical invariants (why the checks exist)

- **#356** — `\x00` overloaded as separator+empty+terminator ⇒ type-byte framing.
- **#359/#368** — opening a second LMDB txn on the write-txn env deadlocks ⇒
  read-back goes through the write txn.
- **#396** — transaction overlay reads (read-your-own-writes during TSTART).
- **#457/#458** — index-build batching (`beginWriteBatch` + flush) to avoid a
  single giant write txn; `^BM25PROG` high-water mark.
- **#300** — read-modify-write (`SET ^X=^X+1`) needs `LOCK` for atomicity.
