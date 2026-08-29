# Introspection Design — Genera-level introspection for NimM

## Goal

Make the interpreter able to inspect itself at runtime: variables in every
scope, routines (source / labels / bytecode), the call stack with per-frame
locals, the symbol table (routines / globals), and self-describing errors with
source positions.

This is a **design plan** (Phase 10). Implementation is tracked per-phase
below; each phase lands independently with its own tests.

## Current state (accurate as of Phase 9)

What already works:

| Feature | Where | Status |
|---|---|---|
| `ZWRITE` / `ZKILL` | engine.nim `cZwrite`/`cZkill` | **done** (#386). Bare ZWRITE lists top-scope locals via `scopes[^1].keys`; `ZWRITE expr` walks a tree via `writeVarTree` |
| `ZSTACK` | engine.nim `cZstack` | routine:label per frame (no locals) |
| `ZSTATS` | engine.nim `cZstats` | commands / function-calls / variable-accesses / elapsed |
| `ZVHISTORY` | engine.nim `cZvhistory` | last 20 variable accesses |
| `ZPRINT` | engine.nim `cZprint` | single label's source line |
| `ZANALYZE` | engine.nim `cZanalyze` | static analysis W001–W006 |
| `ZBREAK`/`ZSTEP`/`ZCONTINUE`/`ZGOTO`/`ZEDIT` | engine.nim + debugger.nim | breakpoints, stepping |
| `$TEXT`, `$QUERY`/`$DATA`/`$ORDER` | evaluator / globals | global introspection |
| `$ESTACK`, `$TLEVEL`, `$REFERENCE`, `$ECODE`/`$ETRAP`/`$ZSTATUS` | special_vars.nim | special variables |

Raw materials that exist but are **not wired** to any M-level command:

| Raw material | Location | Needed for |
|---|---|---|
| `Inspector.inspectVariable` / `formatVariable` / `VariableInfo` | inspector.nim | `ZINSPECT` — used only in `test_inspector.nim`, no engine handler |
| `globals.scopes` (flat `name\x00subs` keys) | globals.nim:28 | local enumeration — no `listLocals` proc (only `listSubs`/`listNodes`) |
| `Bytecode.disassemble` + `Runtime.bytecodeCache` | bytecode.nim / runtime.nim | `ZDUMP` disassembly — no command exposes it |
| `CommandNode.line`/`col` | ast.nim:337 | command-level source positions — populated by parser, read by `Debugger.currentLine/currentCol` |
| Lexer `Token.line`/`col` | lexer.nim | source positions (#326) |
| Debugger `vars`/`stack` prompt commands | debugger.nim | stubs that defer to ZWRITE/ZSTACK |

Raw materials **removed in #388** (dead-code sweep) that some phases re-add:

| Removed field | Re-added for | Notes |
|---|---|---|
| `Expr.line`/`col`, `Cmd.line`/`col` | Phase E expression-level error positions | command-level `CommandNode.line/col` already exist; re-add only if per-expression positions are wanted |
| `StackFrame.variables` | Phase B per-frame locals | was always empty; re-add and *populate* on frame push |
| `RuntimeStats.memoryUsed` | Phase A (optional) | only if a memory stat is wanted |

Known defects to fix along the way:

- `$ZPOS` is broken: evaluator returns `routine:currentLine`, but the engine
  updates `Debugger.currentLine`, never `Runtime.currentLine` (always 0).

## Design principles

1. **M-level primitives, not a UI.** Commands / `$` functions, matching the
   existing `Z*` command family. No CLIM/presentation system (non-goal).
2. **Reuse existing modules.** `inspector.nim`, `globals.scopes`, `disassemble`,
   `ZANALYZE` are the building blocks; phases wire them rather than rewrite.
3. **One enumeration API for locals.** Add `globals.listLocals(scopeIdx)` that
   decodes `name\x00subs` keys (reusing the key-decoding logic from
   `listSubs`/`listNodes`) so ZWRITE, ZINSPECT, and ZSTACK share it.
4. **Composable output.** Variable/stack/bytecode views render through
   `inspector.formatVariable` / `formatStack` / `disassemble`, so a future
   REPL/MCP layer can call the same formatters.

## Phased roadmap

### Phase A — Variable & scope inspection

- Add `globals.listLocals(scopeIdx: int): seq[(string, seq[string])]` — decode
  each `name\x00sub...` key into (name, subs).
- Wire `ZINSPECT`:
  - `ZINSPECT expr` → `formatVariable(inspectVariable(...))` for one variable.
  - bare `ZINSPECT` → every local in the top scope (via `listLocals`).
- Refactor bare `ZWRITE` to use `listLocals` (drop the ad-hoc key split).
- Tests: `tests/test_zinspect.sh`; extend `tests/test_introspection.sh`.

### Phase B — Call stack & per-frame locals

- Re-add `StackFrame.variables` and populate it on frame push (snapshot of the
  frame's `scopes[^1]` via `listLocals`).
- `ZSTACK` prints `routine:label` plus `name="value"` locals per frame.
- Wire the debugger prompt's `vars`/`stack` commands to the same formatters.
- Tests: extend `test_introspection.sh` (locals visible in ZSTACK).

### Phase C — Routine & source introspection

- `ZPRINT` a whole routine (bare `ZPRINT routine` lists every line; the current
  single-label form stays for `ZPRINT label+off^routine`).
- `ZROUTINES` (or `$ZROUTINES`) lists loaded routine names + label count; a
  label-listing form lists `routine.labels`.
- `ZDUMP` disassembles `bytecodeCache` via `disassemble` (bytecode mode only).
- Tests: `tests/test_source.sh`.

### Phase D — Symbol browsing

- Whole-program pass over `Runtime.routines` for **who-calls** / **who-references**
  (extend the existing `ZANALYZE` static-analysis pass; reuse `analyzeLines`).
- `ZAPROPOS "substring"` — search routine/label names and return matches.
- Tests: extend `test_introspection.sh`.

### Phase E — Self-describing errors + source positions

- Fix `$ZPOS`: have the engine also update `Runtime.currentLine` (or make
  `$ZPOS` read `Debugger.currentLine`); return `routine:label+offset`.
- Wire `CommandNode.line`/`col` (already populated) into error output:
  `M<code>:<message> at routine:label+offset` plus a source snippet.
- Optionally re-add `Expr.line`/`col` (removed in #388) for per-expression
  positions — only if finer granularity is wanted; command-level is enough for
  v1.
- Tests: `tests/test_errorloc.sh`.

### Phase F — REPL / MCP integration

- MCP tools: `list_routines`, `list_variables`, `get_source`, `disassemble`
  (call the same formatters as phases A–C).
- REPL `:inspect` / `:stack` shortcuts.
- Tests: extend the MCP server smoke test.

## Test items

- `tests/test_introspection.sh` — existing 18 checks (ZSTACK/ZSTATS/ZVHISTORY);
  extend as each phase lands.
- `tests/test_zinspect.sh` (Phase A), `tests/test_source.sh` (Phase C),
  `tests/test_errorloc.sh` (Phase E).

## Non-goals

- No Genera presentation system / CLIM / windowing.
- No hot-reload or incremental recompile of routines.
- No persistent "image" of the interpreter state (ZSAVE covers source only).
