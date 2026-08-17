# nimm Workplan: Wire into Testable M Interpreter

**Date:** 2026-08-16
**Goal:** Wire all nimm modules into a working, testable M/MUMPS interpreter

---

## Current State

**Modules exist but are disconnected:**
- `lexer.nim` — tokenizer
- `parser.nim` — recursive descent parser
- `ast.nim` — expression/command AST
- `value.nim` — M value types
- `pattern.nim` — pattern matching
- `runtime.nim` — routine loading, $TEXT, mode system, error handling, tracing, debugging
- `data_structures.nim` — 29 structures
- `network.nim` — TCP socket operations
- `ni_functions.nim` — HTTP, JSON, UUID, SLEEP
- `unicode_utils.nim` — UTF-8 support
- `static_analysis.nim` — unused vars, unreachable code
- `inspector.nim` — ZINSPECT, ZSTACK, ZSTATS
- `improvements.nim` — $FNUMBER, $CASE, $QUERY, ZSYSTEM
- `storage/lmdb_store.nim` — LMDB storage
- `storage/key_encoding.nim` — key encoding

**Missing:**
- `main.nim` — entry point
- `engine.nim` — command execution engine
- `evaluator.nim` — expression evaluator
- `globals.nim` — global/local variable storage
- `repl.nim` — interactive REPL
- Integration tests

---

## Phase 1: Core Engine (Week 1)

### 1.1 Global/Local Variable Storage
**File:** `globals.nim`
- Wrap SymbolTable or create new
- Local variables with NEW/QUIT scoping
- Global variables via LMDB
- Special variables ($X, $Y, $IO, $JOB, $HOROLOG, etc.)

### 1.2 Expression Evaluator
**File:** `evaluator.nim`
- Wire `ast.nim` expressions to `value.nim` types
- Arithmetic: +, -, *, /, \, #, **
- String: _, [, ]
- Comparison: =, '=, <, >, '<, '>
- Logical: &, !, '
- Function calls: dispatch to intrinsic functions
- Variable references: lookup in globals/locals
- Special variables: dispatch to runtime

### 1.3 Command Dispatch ✅ DONE
**File:** `engine.nim` — 215 lines
- SET (with $PIECE/$EXTRACT targets)
- WRITE (with !, #, ?n format controls)
- IF/ELSE
- FOR (argumentless, var=init:step:limit)
- QUIT (with optional value)
- KILL (with exception list)
- NEW (with scoping)
- DO (label, label^routine)
- GOTO (label, label^routine)
- READ, HANG, LOCK, MERGE, XECUTE, BREAK, OPEN/USE/CLOSE
- **Tests:** `tests/test_engine.nim` — 5 tests passing

### 1.4 Main Entry Point
**File:** `main.nim`
- CLI argument parsing
- `-x 'CODE'` — execute code
- `-r file.m -e 'CODE'` — load routine and execute
- `-d /path/to/db` — LMDB database path
- `-m strict|rsm|nimm` — mode selection
- `--repl` — interactive REPL mode

---

## Phase 2: Function Integration (Week 2)

### 2.1 Intrinsic Functions
Wire `evaluator.nim` to call:
- $ASCII, $CHAR, $DATA, $EXTRACT, $FIND, $GET, $INCREMENT
- $JUSTIFY, $LENGTH, $ORDER, $PIECE, $QUERY, $RANDOM
- $REVERSE, $SELECT, $STACK, $TEXT, $TRANSLATE
- $FNUMBER, $CASE (from improvements.nim)

### 2.2 NI Functions
Wire `evaluator.nim` to call:
- $NI_HTTP, $NI_JSON, $NI_UUID, $NI_SLEEP (from ni_functions.nim)

### 2.3 Special Variables
Wire get/set for:
- $DEVICE, $ECODE, $ETRAP, $HOROLOG, $IO, $JOB
- $KEY, $PRINCIPAL, $QUIT, $REFERENCE, $STORAGE
- $STACK, $SYSTEM, $TEST, $X, $Y

---

## Phase 3: Storage Integration (Week 3)

### 3.1 LMDB Global Store
- Wire `storage/lmdb_store.nim` to globals
- Global variable read/write via LMDB
- Transaction support for multi-key updates

### 3.2 Key Encoding
- Wire `storage/key_encoding.nim`
- M-collation for subscript ordering
- Numeric subscripts before string subscripts

### 3.3 Data Structure Integration
- Wire `$NI_*` functions to `data_structures.nim`
- Store data structures in LMDB or memory
- Reference counting or garbage collection

---

## Phase 4: REPL and Batch Mode (Week 4)

### 4.1 Interactive REPL
**File:** `repl.nim`
- Read-Eval-Print Loop
- Line editing (basic readline)
- Error recovery (don't crash on errors)
- Special commands: /quit, /load, /save, /clear

### 4.2 Batch Mode
- Execute M routines from files
- Support `-r file.m -e 'CODE'` pattern
- Exit codes: 0=success, non-zero=error

### 4.3 Error Handling
- Wire $ECODE/$ETRAP to error handling
- Stack traces on errors
- Graceful error recovery in REPL

---

## Phase 5: Testing (Week 5)

### 5.1 Unit Tests
- Test each module independently
- Test evaluator with all expression types
- Test interpreter with all commands
- Test storage with LMDB operations

### 5.2 Integration Tests
- Test full M programs
- Test routine loading and execution
- Test DO/GOTO with labels
- Test nested function calls

### 5.3 Conformance Tests
- Port RFC conformance tests to nimm
- Run against ANSI/ISO M standard
- Target: 139/141 (same as RFC)

---

## Phase 6: Polish (Week 6)

### 6.1 Performance
- Profile with large datasets
- Optimize hot paths
- LMDB batch operations

### 6.2 Documentation
- API documentation
- User guide
- Examples

### 6.3 Packaging
- Nimble package
- Binary distribution
- Docker image

---

## Issue Tracking

Each phase maps to GitHub issues:

| Phase | Issues | Status |
|-------|--------|--------|
| 1 | #14-18 | Pending |
| 2 | #19-21 | Pending |
| 3 | #22-24 | Pending |
| 4 | #25-27 | Pending |
| 5 | #28-30 | Pending |
| 6 | #31-33 | Pending |

---

## Dependencies

- Nim 2.2+ (installed)
- LMDB (installed via nimble)
- No external dependencies for core

## Estimated Effort: 6 weeks
