# bytecode.nim — Bytecode instruction types and bytecode array for NimM
# Stack-based VM instructions compiled from M/MUMPS AST

import strutils

type
  Opcode* = enum
    # Stack operations
    opPushConst     # Push string constant onto stack
    opPushVar       # Push local variable value
    opPushGlobal    # Push global variable value
    opPushSvar      # Push special variable value
    opSetVar        # Pop value, set local variable
    opSetGlobal     # Pop value, set global variable
    opSetSvar       # Pop value, set special variable
    opPop           # Discard top of stack
    opDup           # Duplicate top of stack

    # Arithmetic (pop 2, push 1)
    opAdd
    opSub
    opMul
    opDiv
    opIntDiv
    opMod
    opPow

    # Comparison (pop 2, push 1)
    opCmpEql
    opCmpNeq
    opCmpLt
    opCmpGt
    opCmpLe
    opCmpGe
    opCmpContains
    opCmpFollows

    # String operations
    opConcat        # Pop 2, push concatenated
    opPiece         # Pop delimiter+from+to+string, push piece
    opExtract       # Pop from+to+string, push extract
    opLength        # Pop string, push length

    # Control flow
    opJump          # Unconditional jump
    opJumpIfFalse   # Pop, jump if false
    opJumpIfTrue    # Pop, jump if true
    opCall          # Call function
    opReturn        # Return from bytecode
    opQuit          # Quit execution

    # I/O
    opWrite         # Pop argc values, write to output
    opWriteNl       # Write newline
    opWriteFf       # Write form feed

    # M-specific
    opForInit       # Initialize FOR loop
    opForNext       # Increment, jump if not done
    opNewScope      # Push new scope
    opPopScope      # Pop scope
    opLockAcquire   # LOCK +name
    opLockRelease   # LOCK -name
    opLockReleaseAll # LOCK (bare)
    opTstart        # Begin transaction
    opTcommit       # Commit transaction
    opTrollback     # Rollback transaction
    opXecute        # Fall back to AST for dynamic code
    opNop           # No operation

  Instruction* = object
    opcode*: Opcode
    arg1*: string       # First argument (name, value, etc.)
    arg2*: string       # Second argument (subscripts, etc.)
    argInt*: int        # Integer argument (offset, argc, etc.)

  Bytecode* = ref object
    ## Compiled bytecode for a single M line
    instructions*: seq[Instruction]
    constants*: seq[string]     # String constants referenced by opPushConst
    sourceLine*: string         # Original source line (for debugging)

proc newBytecode*(sourceLine: string = ""): Bytecode =
  new(result)
  result.instructions = @[]
  result.constants = @[]
  result.sourceLine = sourceLine

proc addInstr*(bc: Bytecode, opcode: Opcode, arg1: string = "", arg2: string = "", argInt: int = 0) =
  ## Add an instruction to the bytecode
  bc.instructions.add(Instruction(opcode: opcode, arg1: arg1, arg2: arg2, argInt: argInt))

proc addConst*(bc: Bytecode, value: string): int =
  ## Add a string constant and return its index
  for i, c in bc.constants:
    if c == value: return i
  bc.constants.add(value)
  return bc.constants.len - 1

proc addPushConst*(bc: Bytecode, value: string) =
  ## Add a PUSH_CONST instruction for a string value
  let idx = bc.addConst(value)
  bc.addInstr(opPushConst, argInt = idx)

proc disassemble*(bc: Bytecode): string =
  ## Disassemble bytecode to human-readable string
  result = "Bytecode: " & bc.sourceLine & "\n"
  result.add("Constants: " & $bc.constants.len & "\n")
  for i, instr in bc.instructions:
    result.add("  " & $i & ": " & $instr.opcode)
    case instr.opcode
    of opPushConst:
      let idx = instr.argInt
      if idx >= 0 and idx < bc.constants.len:
        result.add(" \"" & bc.constants[idx] & "\"")
      else:
        result.add(" [invalid index " & $idx & "]")
    of opPushVar, opSetVar, opPushGlobal, opSetGlobal, opPushSvar, opSetSvar,
       opLockAcquire, opLockRelease:
      result.add(" " & instr.arg1)
      if instr.arg2.len > 0:
        result.add("(" & instr.arg2 & ")")
    of opJump, opJumpIfFalse, opJumpIfTrue:
      result.add(" " & $instr.argInt)
    of opCall:
      result.add(" " & instr.arg1 & " argc=" & $instr.argInt)
    of opWrite:
      result.add(" argc=" & $instr.argInt)
    of opForInit:
      result.add(" " & instr.arg1 & " limit=" & instr.arg2 & " step=" & $instr.argInt)
    of opForNext:
      result.add(" " & instr.arg1 & " offset=" & $instr.argInt)
    of opNewScope:
      result.add(" " & instr.arg1)
    else:
      discard
    result.add("\n")
