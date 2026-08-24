# Bytecode VM Phase 2: Engine Integration — Implementation Outline

## Current Architecture (AST interpreter)

```
DO LOOP → for each line:
  gotLine = getLine(routine, label, offset)    # fetch source
  parsed = cachedParseLine(stripLabel(gotLine)) # parse to AST
  result = eng.execute(parsed, depth + 1)       # interpret AST
```

**Problem:** Each line is parsed on every execution. For `FOR I=1:1:1000 SET X=I`,
the same line is parsed 1000 times.

## Target Architecture (bytecode VM)

```
DO LOOP → compile routine to bytecode (once, cached):
  for each line:
    bc = compileLine(parsed)  # AST → bytecode
    routine.bytecode[offset] = bc
  then for each line:
    result = vm.execute(bc)   # execute bytecode
```

## Implementation Steps

### Step 1: Add bytecode cache to Routine struct (runtime.nim)

```nim
import bytecode

Routine* = object
  name*: string
  lines*: seq[string]
  labels*: Table[string, int]
  filePath*: string
  bytecodeCache*: seq[Bytecode]  # Compiled bytecode per line (nil = not compiled)
  bytecodeReady*: bool           # True when all lines compiled
```

### Step 2: Add VM instance to Engine (engine.nim)

```nim
import vm

Engine* = ref object
  ...
  vm*: VM              # Bytecode VM instance
  useBytecode*: bool   # Enable bytecode execution (default: false for safety)
```

Initialize in `newEngine`:
```nim
result.vm = newVM(result.globals)
result.useBytecode = false  # opt-in for now
```

### Step 3: Compile routine on first DO (engine.nim)

In the cDo handler, before the execution loop:

```nim
# Compile routine to bytecode on first DO
let rt = eng.runtime[]
if routine in rt.routines:
  var rtRoutine = rt.routines[routine]
  if not rtRoutine.bytecodeReady and eng.useBytecode:
    rtRoutine.bytecodeCache = @[]
    for i, lineStr in rtRoutine.lines:
      let stripped = stripLabel(lineStr)
      let parsed = eng.cachedParseLine(stripped)
      if parsed != nil:
        rtRoutine.bytecodeCache.add(compileLine(parsed))
      else:
        rtRoutine.bytecodeCache.add(nil)
    rtRoutine.bytecodeReady = true
    rt.routines[routine] = rtRoutine
```

### Step 4: Execute via VM when bytecode available (engine.nim)

Replace the inner execution loop:

```nim
var offset = 0
while true:
  let gotLine = eng.runtime[].getLine(routine, label, offset)
  if gotLine.len == 0: break

  # Try bytecode execution first
  if eng.useBytecode and routine in eng.runtime[].routines:
    let rtRoutine = eng.runtime[].routines[routine]
    if rtRoutine.bytecodeReady and offset < rtRoutine.bytecodeCache.len:
      let bc = rtRoutine.bytecodeCache[offset]
      if bc != nil:
        let output = eng.vm.execute(bc)
        if output.len > 0:
          eng.output.add(output)
        offset.inc
        continue

  # Fallback to AST interpreter
  let parsed = eng.cachedParseLine(stripLabel(gotLine))
  if parsed != nil and parsed.cmds.len > 0:
    let r = eng.execute(parsed, depth + 1)
    if r == "QUIT" or eng.quitAll:
      break
  offset.inc
```

### Step 5: Add --bytecode CLI flag (main.nim)

```nim
type CliArgs = object
  ...
  useBytecode: bool

# In parseArgs:
of "bytecode":
  result.useBytecode = true

# In main:
eng.useBytecode = args.useBytecode
```

### Step 6: Handle QUIT in VM (vm.nim)

The VM's opQuit currently just sets `halted = true`. Need to propagate
QUIT result back to the engine so it can break the DO loop.

```nim
of opQuit:
  vm.halted = true
  vm.push("QUIT")  # signal to engine
```

Engine checks:
```nim
let output = eng.vm.execute(bc)
if output.contains("QUIT") or eng.vm.halted:
  break
```

### Step 7: Handle dynamic features (fallback to AST)

The compiler already emits `opXecute` for dynamic features. The VM's
opXecute handler should signal "fall back to AST":

```nim
of opXecute:
  vm.halted = true
  vm.push("FALLBACK")  # signal to engine to use AST
```

Engine checks:
```nim
let output = eng.vm.execute(bc)
if output.contains("FALLBACK"):
  # Re-execute this line via AST
  let parsed = eng.cachedParseLine(stripLabel(gotLine))
  if parsed != nil and parsed.cmds.len > 0:
    let r = eng.execute(parsed, depth + 1)
    if r == "QUIT" or eng.quitAll:
      break
```

## Files to modify

| File | Changes |
|---|---|
| `runtime.nim` | Add bytecodeCache, bytecodeReady to Routine |
| `engine.nim` | Add VM instance, useBytecode flag, bytecode execution path |
| `vm.nim` | Handle QUIT/FALLBACK signals |
| `compiler.nim` | Ensure all commands compile (fill in placeholders) |
| `main.nim` | Add --bytecode CLI flag |
| `tests/test_bytecode.nim` | Add integration tests |

## Testing strategy

1. Unit tests: compile routine lines, execute via VM, verify output
2. Integration tests: `nimm --bytecode -x 'FOR I=1:1:3 WRITE I'`
3. Conformance: `nimm --bytecode` passes all 179 ISO tests
4. Fallback: XECUTE/indirection falls back to AST correctly
5. Performance: benchmark bytecode vs AST on loop-heavy code

## Risks

| Risk | Mitigation |
|---|---|
| Dynamic features break | Fallback to AST for XECUTE, indirection |
| QUIT propagation | VM signals QUIT via output/halted flag |
| Memory overhead | Bytecode cached per routine, much smaller than AST |
| Conformance regression | Run full test suite with --bytecode flag |

## Expected performance

| Operation | AST | Bytecode | Speedup |
|---|---|---|---|
| `FOR 1000 × SET X=I` | 347µs | ~50µs | 7x |
| `WRITE 1+2` | 0.90µs | ~0.30µs | 3x |
| Mixed workload | 1.0µs | ~0.30µs | 3x |
