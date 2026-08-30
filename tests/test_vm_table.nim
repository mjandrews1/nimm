# test_vm_table.nim — VM opcode stack-effect table sync + value checks.
#
# Executes every real opcode against a known sentinel stack and asserts:
#   (a) the observed stack *depth* matches the Pops/Pushes table in
#       formal/vm_opcodes.dfy (table sync);
#   (b) for the semantic opcodes, the observed stack *values* are correct
#       (value-level check — catches wrong-value handlers that depth-only
#        checks would miss).
#
# Run: nim c -r tests/test_vm_table.nim

import ../bytecode
import ../vm
import ../globals

proc runOpcode(op: Opcode, inputs: openArray[string],
               arg1 = "", arg2 = "", argInt = 0, presetVar = false): seq[string] =
  var g = newGlobals()
  if presetVar:
    g.setLocalDirect(arg1, "1")
  var vm = newVM(addr g)
  var bc = newBytecode("test")
  for v in inputs:
    let idx = bc.addConst(v)
    bc.addInstr(opPushConst, argInt = idx)
  bc.addInstr(op, arg1, arg2, argInt)
  discard vm.execute(bc)
  return vm.stack

proc checkDepth(op: Opcode, pops, pushes: int,
                arg1 = "", arg2 = "", argInt = 0, presetVar = false) =
  var inputs: seq[string] = @[]
  for i in 0 ..< pops:
    inputs.add($(i + 1))   # numeric sentinel (safe for parseInt)
  let st = runOpcode(op, inputs, arg1, arg2, argInt, presetVar)
  assert st.len == pushes,
    "opcode " & $op & " stack effect mismatch: expected " & $pushes &
    " left, got " & $st.len

proc checkStack(op: Opcode, inputs: openArray[string], expected: openArray[string],
                arg1 = "", arg2 = "", argInt = 0) =
  let st = runOpcode(op, inputs, arg1, arg2, argInt)
  let exp = @expected
  assert st == exp,
    "opcode " & $op & " value mismatch: expected " & $exp & ", got " & $st

proc main() =
  echo "VM opcode stack-effect table sync (mirrors formal/vm_opcodes.dfy)..."

  # Stack ops (depth)
  checkDepth(opPushConst, 0, 1)
  checkDepth(opPushVar, 0, 1, arg1 = "X")
  checkDepth(opPushGlobal, 0, 1, arg1 = "^G")
  checkDepth(opPushSvar, 0, 1, arg1 = "H")
  checkDepth(opSetVar, 1, 0, arg1 = "X")
  checkDepth(opSetGlobal, 1, 0, arg1 = "^G")
  checkDepth(opSetSvar, 1, 0, arg1 = "H")
  checkDepth(opPushVarSub, 3, 1, arg1 = "X", argInt = 3)
  checkDepth(opPushGlobalSub, 2, 1, arg1 = "^G", argInt = 2)
  checkDepth(opSetVarSub, 2, 0, arg1 = "X", argInt = 2)
  checkDepth(opSetGlobalSub, 1, 0, arg1 = "^G", argInt = 1)
  checkDepth(opPop, 1, 0)
  checkDepth(opDup, 0, 1)

  # Arithmetic (pop 2, push 1) — depth + value
  for o in [opAdd, opSub, opMul, opDiv, opIntDiv, opMod, opPow]:
    checkDepth(o, 2, 1)
  checkStack(opAdd, ["2", "3"], ["5"])
  checkStack(opSub, ["5", "3"], ["2"])
  checkStack(opMul, ["2", "3"], ["6"])
  checkStack(opDiv, ["6", "3"], ["2"])
  checkStack(opIntDiv, ["7", "3"], ["2"])
  checkStack(opMod, ["7", "3"], ["1"])
  checkStack(opPow, ["2", "3"], ["8"])

  # Comparison (pop 2, push 1) — depth + value
  for o in [opCmpEql, opCmpNeq, opCmpLt, opCmpGt, opCmpLe, opCmpGe,
            opCmpContains, opCmpFollows]:
    checkDepth(o, 2, 1)
  checkStack(opCmpEql, ["3", "3"], ["1"])
  checkStack(opCmpNeq, ["3", "4"], ["1"])
  checkStack(opCmpLt, ["1", "2"], ["1"])
  checkStack(opCmpGt, ["2", "1"], ["1"])
  checkStack(opCmpLe, ["2", "2"], ["1"])
  checkStack(opCmpGe, ["2", "2"], ["1"])

  # String ops — depth + value
  checkDepth(opConcat, 2, 1)
  checkDepth(opPiece, 4, 1)
  checkDepth(opExtract, 3, 1)
  checkDepth(opLength, 1, 1)
  checkStack(opConcat, ["ab", "cd"], ["abcd"])
  checkStack(opLength, ["abc"], ["3"])
  checkStack(opDup, ["X"], ["X", "X"])

  # Control flow (depth)
  checkDepth(opJump, 0, 0, argInt = 1)
  checkDepth(opJumpIfFalse, 1, 0, argInt = 1)
  checkDepth(opJumpIfTrue, 1, 0, argInt = 1)
  checkDepth(opReturn, 0, 0)
  checkDepth(opQuit, 0, 0)

  # I/O (depth)
  checkDepth(opWrite, 3, 0, argInt = 3)
  checkDepth(opWriteNl, 0, 0)
  checkDepth(opWriteFf, 0, 0)

  # M-specific (depth)
  checkDepth(opNewScope, 0, 0)
  checkDepth(opPopScope, 0, 0)
  checkDepth(opLockAcquire, 0, 0, arg1 = "L")
  checkDepth(opLockRelease, 0, 0, arg1 = "L")
  checkDepth(opLockReleaseAll, 0, 0)
  checkDepth(opTstart, 0, 0)
  checkDepth(opTcommit, 0, 0)
  checkDepth(opTrollback, 0, 0)
  checkDepth(opZloadxml, 3, 1)
  checkDepth(opKill, 0, 0, arg1 = "X")
  checkDepth(opBreak, 0, 0)
  checkDepth(opGoto, 0, 0, arg1 = "LBL")
  checkDepth(opCallLabel, 0, 0, arg1 = "LBL")
  checkDepth(opMerge, 0, 0, arg1 = "A", arg2 = "B")
  checkDepth(opNop, 0, 0)

  echo "  all 55 opcodes match the Dafny table; semantic values verified"
  echo "VM table sync passed!"

main()
