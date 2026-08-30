# test_vm_table.nim — VM opcode stack-effect table sync.
#
# Executes every real opcode against a known sentinel stack and asserts the
# observed stack effect matches the Pops/Pushes table in formal/vm_opcodes.dfy.
# This keeps the Dafny model and the actual vm.nim handlers in agreement.
#
# Run: nim c -r tests/test_vm_table.nim

import ../bytecode
import ../vm
import ../globals

proc checkOpcode(op: Opcode, pops, pushes: int,
                 arg1 = "", arg2 = "", argInt = 0, presetVar = false) =
  var g = newGlobals()
  if presetVar:
    g.setLocalDirect(arg1, "1")
  var vm = newVM(addr g)
  var bc = newBytecode("test")
  for i in 0 ..< pops:
    let idx = bc.addConst($(i + 1))   # numeric sentinel (safe for parseInt)
    bc.addInstr(opPushConst, argInt = idx)
  bc.addInstr(op, arg1, arg2, argInt)
  discard vm.execute(bc)
  assert vm.stack.len == pushes,
    "opcode " & $op & " stack effect mismatch: expected " & $pushes &
    " left, got " & $vm.stack.len

proc main() =
  echo "VM opcode stack-effect table sync (mirrors formal/vm_opcodes.dfy)..."

  # Stack ops
  checkOpcode(opPushConst, 0, 1)
  checkOpcode(opPushVar, 0, 1, arg1 = "X")
  checkOpcode(opPushGlobal, 0, 1, arg1 = "^G")
  checkOpcode(opPushSvar, 0, 1, arg1 = "H")
  checkOpcode(opSetVar, 1, 0, arg1 = "X")
  checkOpcode(opSetGlobal, 1, 0, arg1 = "^G")
  checkOpcode(opSetSvar, 1, 0, arg1 = "H")
  checkOpcode(opPushVarSub, 3, 1, arg1 = "X", argInt = 3)
  checkOpcode(opPushGlobalSub, 2, 1, arg1 = "^G", argInt = 2)
  checkOpcode(opSetVarSub, 2, 0, arg1 = "X", argInt = 2)
  checkOpcode(opSetGlobalSub, 1, 0, arg1 = "^G", argInt = 1)
  checkOpcode(opPop, 1, 0)
  checkOpcode(opDup, 0, 1)

  # Arithmetic (pop 2, push 1)
  for o in [opAdd, opSub, opMul, opDiv, opIntDiv, opMod, opPow]:
    checkOpcode(o, 2, 1)

  # Comparison (pop 2, push 1)
  for o in [opCmpEql, opCmpNeq, opCmpLt, opCmpGt, opCmpLe, opCmpGe,
            opCmpContains, opCmpFollows]:
    checkOpcode(o, 2, 1)

  # String ops
  checkOpcode(opConcat, 2, 1)
  checkOpcode(opPiece, 4, 1)
  checkOpcode(opExtract, 3, 1)
  checkOpcode(opLength, 1, 1)

  # Control flow
  checkOpcode(opJump, 0, 0, argInt = 1)
  checkOpcode(opJumpIfFalse, 1, 0, argInt = 1)
  checkOpcode(opJumpIfTrue, 1, 0, argInt = 1)
  checkOpcode(opCall, 3, 1, argInt = 3)
  checkOpcode(opReturn, 0, 0)
  checkOpcode(opQuit, 0, 0)

  # I/O
  checkOpcode(opWrite, 3, 0, argInt = 3)
  checkOpcode(opWriteNl, 0, 0)
  checkOpcode(opWriteFf, 0, 0)

  # M-specific
  checkOpcode(opForInit, 0, 2, arg1 = "I", arg2 = "10", argInt = 1)
  checkOpcode(opForNext, 2, 2, arg1 = "I", argInt = 0, presetVar = true)
  checkOpcode(opNewScope, 0, 0)
  checkOpcode(opPopScope, 0, 0)
  checkOpcode(opLockAcquire, 0, 0, arg1 = "L")
  checkOpcode(opLockRelease, 0, 0, arg1 = "L")
  checkOpcode(opLockReleaseAll, 0, 0)
  checkOpcode(opTstart, 0, 0)
  checkOpcode(opTcommit, 0, 0)
  checkOpcode(opTrollback, 0, 0)
  checkOpcode(opXecute, 0, 1)
  checkOpcode(opZloadxml, 3, 1)
  checkOpcode(opKill, 0, 0, arg1 = "X")
  checkOpcode(opBreak, 0, 0)
  checkOpcode(opGoto, 0, 0, arg1 = "LBL")
  checkOpcode(opCallLabel, 0, 0, arg1 = "LBL")
  checkOpcode(opMerge, 0, 0, arg1 = "A", arg2 = "B")
  checkOpcode(opNop, 0, 0)

  echo "  all 59 opcodes match the Dafny table"
  echo "VM table sync passed!"

main()
