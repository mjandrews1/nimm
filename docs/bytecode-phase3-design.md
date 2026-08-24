# Bytecode VM Phase 3: Optimization Passes — Implementation Outline

## Current State

The compiler emits straightforward bytecode from AST. No post-compilation
optimizations are applied. The bytecode is a direct translation of the AST.

## Optimization Passes

### Pass 1: Constant Folding

Fold constant expressions at bytecode level. When both operands of an
arithmetic/comparison operation are PUSH_CONST, compute the result at
compile time and replace with a single PUSH_CONST.

**Pattern:**
```
PUSH_CONST "3"
PUSH_CONST "4"
ADD
→
PUSH_CONST "7"
```

**Applies to:** ADD, SUB, MUL, DIV, INTDIV, MOD, POW, CMP_*, CONCAT

**Implementation:**
```nim
proc foldConstants(bc: var Bytecode) =
  var i = 0
  while i < bc.instructions.len - 2:
    let a = bc.instructions[i]
    let op = bc.instructions[i + 1]
    let b = bc.instructions[i + 2]
    if a.opcode == opPushConst and b.opcode == opPushConst:
      let aval = bc.constants[a.argInt]
      let bval = bc.constants[b.argInt]
      let folded = foldOp(aval, op.opcode, bval)
      if folded.isSome:
        let idx = bc.addConst(folded.get)
        bc.instructions[i] = Instruction(opcode: opPushConst, argInt: idx)
        bc.instructions.delete(i + 2)
        bc.instructions.delete(i + 1)
        continue
    inc i
```

### Pass 2: Dead Code Elimination

Remove unreachable instructions after unconditional JUMP and QUIT.

**Pattern:**
```
JUMP 10
PUSH_CONST "dead"    ← unreachable
WRITE 1              ← unreachable
→
JUMP 10
```

**Implementation:**
```nim
proc eliminateDeadCode(bc: var Bytecode) =
  var reachable = newSeq[bool](bc.instructions.len)
  # Mark reachable from start
  var queue = @[0]
  while queue.len > 0:
    let idx = queue.pop()
    if idx < 0 or idx >= bc.instructions.len: continue
    if reachable[idx]: continue
    reachable[idx] = true
    let instr = bc.instructions[idx]
    case instr.opcode
    of opJump:
      queue.add(instr.argInt)
    of opJumpIfFalse, opJumpIfTrue:
      queue.add(instr.argInt)
      queue.add(idx + 1)
    of opQuit, opReturn:
      discard  # no fallthrough
    else:
      queue.add(idx + 1)
  # Remove unreachable instructions
  var newInstrs: seq[Instruction] = @[]
  for i, instr in bc.instructions:
    if reachable[i]:
      newInstrs.add(instr)
  bc.instructions = newInstrs
```

### Pass 3: Peephole Optimizations

Remove redundant instruction pairs.

**Patterns:**
```
PUSH_CONST x + POP        → (remove both)
DUP + POP                  → (remove both)
JUMP next_instruction      → (remove jump)
PUSH_CONST "0" + JUMP_IF_FALSE offset → JUMP offset
PUSH_CONST "1" + JUMP_IF_TRUE offset  → JUMP offset
```

**Implementation:**
```nim
proc peephole(bc: var Bytecode) =
  var changed = true
  while changed:
    changed = false
    var i = 0
    while i < bc.instructions.len - 1:
      let a = bc.instructions[i]
      let b = bc.instructions[i + 1]
      # PUSH_CONST + POP → remove both
      if a.opcode == opPushConst and b.opcode == opPop:
        bc.instructions.delete(i)
        bc.instructions.delete(i)
        changed = true
        continue
      # DUP + POP → remove both
      if a.opcode == opDup and b.opcode == opPop:
        bc.instructions.delete(i)
        bc.instructions.delete(i)
        changed = true
        continue
      # JUMP to next instruction → remove
      if a.opcode == opJump and a.argInt == i + 1:
        bc.instructions.delete(i)
        changed = true
        continue
      inc i
```

### Pass 4: Jump Chain Simplification

Simplify chains of jumps: `JUMP A` where instruction at A is `JUMP B` → `JUMP B`.

**Implementation:**
```nim
proc simplifyJumps(bc: var Bytecode) =
  for i, instr in bc.instructions:
    if instr.opcode == opJump:
      let target = instr.argInt
      if target >= 0 and target < bc.instructions.len:
        if bc.instructions[target].opcode == opJump:
          bc.instructions[i] = Instruction(opcode: opJump, argInt: bc.instructions[target].argInt)
```

## Integration

Add an `optimize` proc to compiler.nim that runs all passes:

```nim
proc optimize*(bc: var Bytecode) =
  bc.foldConstants()
  bc.eliminateDeadCode()
  bc.peephole()
  bc.simplifyJumps()
```

Call after `compileLine` in the DO handler:

```nim
var bc = compileLine(parsed)
bc.optimize()
rtRoutine.bytecodeCache.add(bc)
```

## Testing

- Unit tests for each optimization pass
- Verify all 179 ISO tests pass with bytecode + optimizations
- Benchmark: bytecode+opts vs bytecode-only vs AST

## Files to modify

| File | Changes |
|---|---|
| `compiler.nim` | Add optimization passes |
| `tests/test_bytecode.nim` | Add optimization tests |
| `engine.nim` | Call optimize() after compileLine |

## Expected Impact

| Operation | AST | Bytecode | Bytecode+opts |
|---|---|---|---|
| `WRITE 1+2` | 0.90µs | ~0.30µs | ~0.25µs |
| `FOR 1000 × SET X=I` | 347µs | ~50µs | ~45µs |
| Constant-heavy code | 1.0µs | ~0.30µs | ~0.20µs |
