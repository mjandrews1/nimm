# test_bytecode.nim — Tests for bytecode VM

import ../bytecode
import ../vm
import ../compiler
import ../parser
import ../globals

proc testBytecodeBasics() =
  echo "Testing bytecode basics..."
  let bc = newBytecode("test line")
  assert bc.sourceLine == "test line"
  assert bc.instructions.len == 0
  assert bc.constants.len == 0
  bc.addInstr(opPushConst, argInt = 0)
  bc.addInstr(opWrite, argInt = 1)
  assert bc.instructions.len == 2
  assert bc.instructions[0].opcode == opPushConst
  assert bc.instructions[1].opcode == opWrite
  let idx = bc.addConst("hello")
  assert idx == 0
  assert bc.constants[0] == "hello"
  let idx2 = bc.addConst("world")
  assert idx2 == 1
  let idx3 = bc.addConst("hello")
  assert idx3 == 0
  echo "  ✓ Bytecode basics"

proc testVMBasic() =
  echo "Testing VM basic operations..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  vm.push("hello")
  vm.push("world")
  assert vm.pop() == "world"
  assert vm.pop() == "hello"
  assert vm.pop() == ""
  vm.push("test")
  assert vm.peek() == "test"
  assert vm.stack.len == 1
  discard vm.pop()
  echo "  ✓ VM basic operations"

proc testVMWrite() =
  echo "Testing VM WRITE..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  let bc = newBytecode("W \"hello\"")
  let idx = bc.addConst("hello")
  bc.addInstr(opPushConst, argInt = idx)
  bc.addInstr(opWrite, argInt = 1)
  let output = vm.execute(bc)
  assert output == "hello", "Expected 'hello', got '" & output & "'"
  echo "  ✓ VM WRITE"

proc testVMArithmetic() =
  echo "Testing VM arithmetic..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  let bc = newBytecode("W 1+2")
  bc.addPushConst("1")
  bc.addPushConst("2")
  bc.addInstr(opAdd)
  bc.addInstr(opWrite, argInt = 1)
  let output = vm.execute(bc)
  assert output == "3", "Expected '3', got '" & output & "'"
  let bc2 = newBytecode("W 3*4")
  bc2.addPushConst("3")
  bc2.addPushConst("4")
  bc2.addInstr(opMul)
  bc2.addInstr(opWrite, argInt = 1)
  let output2 = vm.execute(bc2)
  assert output2 == "12", "Expected '12', got '" & output2 & "'"
  echo "  ✓ VM arithmetic"

proc testVMComparison() =
  echo "Testing VM comparison..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  let bc = newBytecode("W 1<2")
  bc.addPushConst("1")
  bc.addPushConst("2")
  bc.addInstr(opCmpLt)
  bc.addInstr(opWrite, argInt = 1)
  let output = vm.execute(bc)
  assert output == "1", "Expected '1', got '" & output & "'"
  let bc2 = newBytecode("W 2<1")
  bc2.addPushConst("2")
  bc2.addPushConst("1")
  bc2.addInstr(opCmpLt)
  bc2.addInstr(opWrite, argInt = 1)
  let output2 = vm.execute(bc2)
  assert output2 == "0", "Expected '0', got '" & output2 & "'"
  echo "  ✓ VM comparison"

proc testVMConcat() =
  echo "Testing VM concatenation..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  let bc = newBytecode("W \"hello\"_\"world\"")
  bc.addPushConst("hello")
  bc.addPushConst("world")
  bc.addInstr(opConcat)
  bc.addInstr(opWrite, argInt = 1)
  let output = vm.execute(bc)
  assert output == "helloworld", "Expected 'helloworld', got '" & output & "'"
  echo "  ✓ VM concatenation"

proc testVMVariables() =
  echo "Testing VM variables..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  let bc = newBytecode("SET X=1 WRITE X")
  bc.addPushConst("1")
  bc.addInstr(opSetVar, arg1 = "X")
  bc.addInstr(opPushVar, arg1 = "X")
  bc.addInstr(opWrite, argInt = 1)
  let output = vm.execute(bc)
  assert output == "1", "Expected '1', got '" & output & "'"
  echo "  ✓ VM variables"

proc testVMTransactions() =
  echo "Testing VM transactions..."
  var g = create(Globals); g[] = newGlobals("")
  var vm = newVM(g)
  let bc = newBytecode("TSTART SET ^X=1 TCOMMIT W ^X")
  bc.addInstr(opTstart)
  bc.addPushConst("1")
  bc.addInstr(opSetGlobal, arg1 = "^X")
  bc.addInstr(opTcommit)
  bc.addInstr(opPushGlobal, arg1 = "^X")
  bc.addInstr(opWrite, argInt = 1)
  let output = vm.execute(bc)
  assert output == "1", "Expected '1', got '" & output & "'"
  echo "  ✓ VM transactions"

proc testDisassemble() =
  echo "Testing disassembler..."
  let bc = newBytecode("W 1+2")
  bc.addPushConst("1")
  bc.addPushConst("2")
  bc.addInstr(opAdd)
  bc.addInstr(opWrite, argInt = 1)
  let dis = bc.disassemble()
  let hasPush = dis.len > 0
  assert(hasPush)
  echo "  ✓ Disassembler"

proc testConstantFolding() =
  echo "Testing constant folding..."
  var bc = newBytecode("W 1+2")
  bc.addPushConst("1")
  bc.addPushConst("2")
  bc.addInstr(opAdd)
  bc.addInstr(opWrite, argInt = 1)
  assert bc.instructions.len == 4
  bc.foldConstants()
  assert bc.instructions.len == 2, "Expected 2 instructions after folding, got " & $bc.instructions.len
  assert bc.instructions[0].opcode == opPushConst
  assert bc.constants[bc.instructions[0].argInt] == "3.0"
  echo "  ✓ Constant folding"

proc testDeadCodeElimination() =
  echo "Testing dead code elimination..."
  var bc = newBytecode("QUIT W 1")
  bc.addInstr(opQuit)
  bc.addPushConst("1")
  bc.addInstr(opWrite, argInt = 1)
  assert bc.instructions.len == 3
  bc.eliminateDeadCode()
  assert bc.instructions.len == 1, "Expected 1 instruction after elimination, got " & $bc.instructions.len
  assert bc.instructions[0].opcode == opQuit
  echo "  ✓ Dead code elimination"

proc testPeephole() =
  echo "Testing peephole optimizations..."
  var bc = newBytecode("SET X=1 POP")
  bc.addPushConst("1")
  bc.addInstr(opPop)
  assert bc.instructions.len == 2
  bc.peephole()
  assert bc.instructions.len == 0, "Expected 0 instructions after peephole, got " & $bc.instructions.len
  echo "  ✓ Peephole optimizations"

proc main() =
  echo "=== Bytecode VM Tests ==="
  testBytecodeBasics()
  testVMBasic()
  testVMWrite()
  testVMArithmetic()
  testVMComparison()
  testVMConcat()
  testVMVariables()
  testVMTransactions()
  testDisassemble()
  testConstantFolding()
  testDeadCodeElimination()
  testPeephole()
  echo ""
  echo "All bytecode tests passed!"

main()
