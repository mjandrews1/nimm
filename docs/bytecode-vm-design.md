# Bytecode VM Design for NimM — Issue #337

## Problem

72% of execution time is spent parsing. For `WRITE 1+2`:
- Parse: 0.65µs (72%)
- Eval: 0.20µs (22%)
- Output: 0.05µs (6%)

For `FOR I=1:1:1000 SET X=I`, the same line is parsed 1000 times. A bytecode VM
would compile once and execute repeatedly.

## Design Principles

1. **Incremental adoption** — bytecode VM runs alongside existing AST interpreter
2. **Fallback to AST** — dynamic features (XECUTE, indirection) fall back to AST
3. **Cache per routine** — bytecode cached in Routine struct, invalidated on reload
4. **Stack-based VM** — simpler than register-based, maps well to M's expression model
5. **No GC pressure** — bytecode is flat array of instructions, no heap allocs per exec

## Bytecode Instructions

### Stack operations
```
PUSH_CONST  value     # Push string constant onto stack
PUSH_VAR    name      # Push variable value onto stack
PUSH_GLOBAL name subs # Push global variable value
PUSH_SVAR   name      # Push special variable value
SET_VAR     name      # Pop value, set local variable
SET_GLOBAL  name subs # Pop value, set global variable
SET_SVAR   name      # Pop value, set special variable
POP                   # Discard top of stack
DUP                   # Duplicate top of stack
```

### Arithmetic (pop 2, push 1)
```
ADD
SUB
MUL
DIV
INTDIV
MOD
POW
```

### Comparison (pop 2, push 1)
```
CMP_EQL
CMP_NEQ
CMP_LT
CMP_GT
CMP_LE
CMP_GE
CMP_CONTAINS
CMP_FOLLOWS
```

### String operations
```
CONCAT        # Pop 2, push concatenated
PIECE         # Pop delimiter+from+to+string, push piece
EXTRACT       # Pop from+to+string, push extract
LENGTH        # Pop string, push length
```

### Control flow
```
JUMP          offset    # Unconditional jump
JUMP_IF_FALSE offset    # Pop, jump if false
JUMP_IF_TRUE  offset    # Pop, jump if true
CALL          name argc # Call function, argc args on stack
RETURN                  # Return from current bytecode
QUIT                    # Quit execution
```

### I/O
```
WRITE         argc      # Pop argc values, write to output
WRITE_NL              # Write newline
WRITE_FF              # Write form feed
```

### M-specific
```
FOR_INIT      varname limit step  # Initialize FOR loop
FOR_NEXT      varname offset      # Increment, jump if not done
NEW_SCOPE     names               # Push new scope with listed vars
POP_SCOPE                           # Pop scope
LOCK_ACQUIRE  name                # LOCK +name
LOCK_RELEASE  name                # LOCK -name
LOCK_RELEASE_ALL                  # LOCK (bare)
TSTART                            # Begin transaction
TCOMMIT                           # Commit transaction
TROLLBACK                         # Rollback transaction
XECUTE        expr                # Fall back to AST for dynamic code
```

## Compilation Strategy

### Per-line compilation
Each M line compiles to a flat bytecode array. A routine is an array of
bytecode arrays, one per source line.

```
Routine:
  lines[0]: "SET X=1"  → [PUSH_CONST "1", SET_VAR "X"]
  lines[1]: "WRITE X"  → [PUSH_VAR "X", WRITE 1]
  lines[2]: "QUIT"     → [QUIT]
```

### Expression compilation
Expressions compile to stack operations:
```
1+2 → PUSH_CONST "1", PUSH_CONST "2", ADD
X+Y → PUSH_VAR "X", PUSH_VAR "Y", ADD
$L("hello") → PUSH_CONST "hello", CALL "LENGTH" 1
```

### Command compilation
Commands compile to VM instructions:
```
WRITE 1+2    → PUSH_CONST "1", PUSH_CONST "2", ADD, WRITE 1
SET X=1      → PUSH_CONST "1", SET_VAR "X"
IF X>0 W "Y" → PUSH_VAR "X", PUSH_CONST "0", CMP_GT, JUMP_IF_FALSE skip, PUSH_CONST "Y", WRITE 1, skip:
FOR I=1:1:10 → FOR_INIT "I" 10 1, [body], FOR_NEXT "I" back
```

### Dynamic features (fallback to AST)
```
XECUTE expr     → XECUTE instruction → falls back to AST interpreter
@indirect       → XECUTE instruction
$TEXT(ref)      → handled at compile time if possible, else XECUTE
```

## Implementation Plan

### Phase 1: Bytecode infrastructure (new files)
- `bytecode.nim` — instruction types, bytecode array, disassembler
- `vm.nim` — stack-based VM execution loop
- `compiler.nim` — AST → bytecode compilation

### Phase 2: Integration with existing engine
- Add `bytecode: seq[Instruction]` field to Routine struct
- Add `useBytecode: bool` flag to Engine
- Compile routine on first DO/XECUTE, cache in Routine
- VM execution loop replaces AST interpreter for compiled routines
- Fallback to AST for dynamic features

### Phase 3: Optimization passes
- Constant folding in bytecode (already done at AST level)
- Dead code elimination
- Peephole optimizations (PUSH_CONST + POP → remove both)

### Phase 4: Testing and benchmarking
- Bytecode unit tests (instruction encoding, VM execution)
- Conformance tests pass with bytecode VM
- Performance benchmarks: bytecode vs AST interpreter

## Files to create/modify

| File | Action | Purpose |
|---|---|---|
| `bytecode.nim` | Create | Instruction types, bytecode array |
| `vm.nim` | Create | Stack-based VM execution loop |
| `compiler.nim` | Create | AST → bytecode compilation |
| `ast.nim` | Modify | Add bytecode field to Routine |
| `engine.nim` | Modify | Add bytecode execution path |
| `evaluator.nim` | Modify | Add bytecode-aware eval |
| `runtime.nim` | Modify | Cache bytecode in Routine |
| `tests/test_bytecode.nim` | Create | Bytecode unit tests |
| `bench/bench.nim` | Modify | Add bytecode benchmarks |

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Dynamic features break | Fallback to AST for XECUTE, indirection |
| Memory overhead | Bytecode is flat array, much smaller than AST |
| Debugging harder | Keep AST interpreter as fallback, add disassembler |
| Conformance regression | Run full test suite after each phase |

## Expected Performance

| Operation | AST (current) | Bytecode (expected) | Speedup |
|---|---|---|---|
| `WRITE 1+2` | 0.90µs | ~0.30µs | 3x |
| `FOR 1000 × SET X=I` | 347µs | ~50µs | 7x |
| `$PIECE("a^b^c","^",2)` | 1.86µs | ~0.60µs | 3x |
| Mixed workload | 1.0µs | ~0.30µs | 3x |

## Dependencies

- No external dependencies
- Builds on existing AST (ast.nim) and evaluator (evaluator.nim)
- Requires Routine struct modification (runtime.nim)

## Effort Estimate

| Phase | Effort | Risk |
|---|---|---|
| Phase 1: Infrastructure | 1-2 days | Low |
| Phase 2: Integration | 2-3 days | Medium |
| Phase 3: Optimization | 1-2 days | Low |
| Phase 4: Testing | 1 day | Low |
| **Total** | **5-8 days** | Medium |
