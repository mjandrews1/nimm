# compiler.nim — AST to bytecode compiler for NimM
# Compiles M/MUMPS AST nodes to stack-based bytecode instructions

import ast
import bytecode
import strutils
import value

proc compileExpr*(bc: Bytecode, expr: Expr) =
  ## Compile an expression to bytecode (pushes result onto stack)
  if expr == nil: return

  case expr.kind
  of numLit:
    bc.addPushConst(expr.sval)

  of eStr:
    bc.addPushConst(expr.sval)

  of eVar:
    if expr.subs.len == 0:
      if expr.vname.startsWith("$"):
        bc.addInstr(opPushSvar, arg1 = expr.vname[1..^1])
      elif expr.vname.startsWith("^"):
        bc.addInstr(opPushGlobal, arg1 = expr.vname)
      else:
        bc.addInstr(opPushVar, arg1 = expr.vname)
    else:
      # Subscripted variable — push name and subscripts
      bc.addInstr(opPushGlobal, arg1 = expr.vname, arg2 = expr.subs[0].sval)

  of eFunc:
    # Compile arguments first (pushed onto stack in order)
    for arg in expr.fargs:
      bc.compileExpr(arg)
    bc.addInstr(opCall, arg1 = expr.fname, argInt = expr.fargs.len)

  of eSvar:
    bc.addInstr(opPushSvar, arg1 = expr.sname)

  of eNeg:
    bc.compileExpr(expr.operand)
    bc.addPushConst("0")
    bc.addInstr(opSub)

  of ePos:
    bc.compileExpr(expr.operand)

  of eNot:
    bc.compileExpr(expr.operand)
    bc.addPushConst("0")
    bc.addInstr(opCmpEql)

  of eBinary:
    bc.compileExpr(expr.left)
    bc.compileExpr(expr.right)
    case expr.op
    of bAdd: bc.addInstr(opAdd)
    of bSub: bc.addInstr(opSub)
    of bMul: bc.addInstr(opMul)
    of bDiv: bc.addInstr(opDiv)
    of bIntDiv: bc.addInstr(opIntDiv)
    of bMod: bc.addInstr(opMod)
    of bPow: bc.addInstr(opPow)
    of bConcat: bc.addInstr(opConcat)
    of bEql: bc.addInstr(opCmpEql)
    of bNeql: bc.addInstr(opCmpNeq)
    of bLt: bc.addInstr(opCmpLt)
    of bGt: bc.addInstr(opCmpGt)
    of bNlt: bc.addInstr(opCmpGe)  # 'not less than' = >=
    of bNgt: bc.addInstr(opCmpLe)  # 'not greater than' = <=
    of bContains: bc.addInstr(opCmpContains)
    of bFollows: bc.addInstr(opCmpFollows)
    else: bc.addInstr(opNop)

  of ePattern:
    # Pattern match — fall back to AST
    bc.addPushConst("")

  of eIndirect:
    # Indirection — fall back to AST
    bc.addInstr(opXecute)

  of eEntryRef:
    bc.addPushConst(expr.entryLabel)

proc compileWriteArg*(bc: Bytecode, arg: WriteArg) =
  ## Compile a WRITE argument
  case arg.kind
  of wrExpr:
    bc.compileExpr(arg.wexpr)
  of wrNewline:
    bc.addInstr(opWriteNl)
  of wrFormFeed:
    bc.addInstr(opWriteFf)
  of wrColumn:
    # Tab to column — push spaces
    bc.addPushConst(" ")

proc compileSetTarget*(bc: Bytecode, target: SetTarget, valueExpr: Expr) =
  ## Compile a SET target=value
  bc.compileExpr(valueExpr)
  case target.kind
  of stVar:
    if target.tname.startsWith("$"):
      bc.addInstr(opSetSvar, arg1 = target.tname[1..^1])
    elif target.tname.startsWith("^"):
      bc.addInstr(opSetGlobal, arg1 = target.tname)
    else:
      bc.addInstr(opSetVar, arg1 = target.tname)
  of stPiece, stExtract, stIndirect:
    # SET $PIECE/$EXTRACT/@indirect — fall back to AST
    bc.addInstr(opPop)  # discard compiled value
    bc.addInstr(opXecute)

proc compileCommand*(bc: Bytecode, cmd: Cmd) =
  ## Compile a command to bytecode
  if cmd == nil: return

  case cmd.kind
  of cSet:
    for item in cmd.setItems:
      bc.compileSetTarget(item.target, item.value)

  of cWrite:
    var argc = 0
    for arg in cmd.writeArgs:
      case arg.kind
      of wrExpr:
        bc.compileExpr(arg.wexpr)
        argc += 1
      of wrNewline:
        bc.addInstr(opWriteNl)
      of wrFormFeed:
        bc.addInstr(opWriteFf)
      of wrColumn:
        bc.addPushConst(" ")
        argc += 1
    if argc > 0:
      bc.addInstr(opWrite, argInt = argc)

  of cIf:
    if cmd.ifBody != nil:
      bc.compileExpr(cmd.ifCond)
      let jumpIdx = bc.instructions.len
      bc.addInstr(opJumpIfFalse, argInt = 0)  # placeholder
      for childCmd in cmd.ifBody.cmds:
        bc.compileCommand(childCmd.cmd)
      bc.instructions[jumpIdx].argInt = bc.instructions.len

  of cElse:
    if cmd.elseBody != nil:
      for childCmd in cmd.elseBody.cmds:
        bc.compileCommand(childCmd.cmd)

  of cFor:
    # FOR var=start:step:end — compile to bytecode
    if cmd.forSpec.varName.len > 0 and cmd.forSpec.initE != nil:
      # Initialize loop variable
      bc.compileExpr(cmd.forSpec.initE)
      bc.addInstr(opSetVar, arg1 = cmd.forSpec.varName)

      # Loop start: check limit
      let loopStart = bc.instructions.len
      if cmd.forSpec.hasLimit and cmd.forSpec.limitE != nil:
        bc.addInstr(opPushVar, arg1 = cmd.forSpec.varName)
        bc.compileExpr(cmd.forSpec.limitE)
        bc.addInstr(opCmpGt)
        let exitJump = bc.instructions.len
        bc.addInstr(opJumpIfTrue, argInt = 0)  # placeholder

        # Compile body
        if cmd.forBody != nil:
          for childCmd in cmd.forBody.cmds:
            bc.compileCommand(childCmd.cmd)

        # Increment variable
        bc.addInstr(opPushVar, arg1 = cmd.forSpec.varName)
        if cmd.forSpec.stepE != nil:
          bc.compileExpr(cmd.forSpec.stepE)
        else:
          bc.addPushConst("1")
        bc.addInstr(opAdd)
        bc.addInstr(opSetVar, arg1 = cmd.forSpec.varName)

        # Jump back to loop start
        bc.addInstr(opJump, argInt = loopStart)

        # Patch exit jump
        bc.instructions[exitJump].argInt = bc.instructions.len
      else:
        # Infinite FOR — just compile body (will need QUIT to exit)
        if cmd.forBody != nil:
          for childCmd in cmd.forBody.cmds:
            bc.compileCommand(childCmd.cmd)

  of cQuit:
    bc.addInstr(opQuit)

  of cKill:
    if cmd.killRefs.len == 0:
      bc.addInstr(opKill)  # arg1 = "" → kill all locals
    else:
      for refExpr in cmd.killRefs:
        if refExpr.kind == eVar and refExpr.subs.len == 0:
          bc.addInstr(opKill, arg1 = refExpr.vname)
        else:
          bc.addInstr(opXecute)  # subscripted/indirect → AST fallback

  of cNew:
    bc.addInstr(opNewScope, arg1 = cmd.newNames.join(","))

  of cNewExcept:
    bc.addInstr(opNewScope, arg1 = cmd.newKeep.join(","))

  of cDo:
    # DO label / DO label^routine — compile to opCallLabel; DO with args or
    # DO ^routine (first-label resolution) falls back to AST (#378).
    var canCompile = true
    for arg in cmd.doArgs:
      if arg.kind == eEntryRef and arg.entryArgs.len == 0 and arg.entryLabel.len > 0:
        bc.addInstr(opCallLabel, arg1 = arg.entryLabel, arg2 = arg.entryRoutine)
      else:
        canCompile = false
    if not canCompile:
      bc.needsAst = true

  of cDoInline:
    if cmd.doInlineBody != nil:
      for childCmd in cmd.doInlineBody.cmds:
        bc.compileCommand(childCmd.cmd)

  of cGoto:
    if cmd.gotoExpr != nil and cmd.gotoExpr.kind == eEntryRef:
      bc.addInstr(opGoto, arg1 = cmd.gotoExpr.entryLabel, arg2 = cmd.gotoExpr.entryRoutine)
    elif cmd.gotoExpr != nil and cmd.gotoExpr.kind == eVar:
      bc.addInstr(opGoto, arg1 = cmd.gotoExpr.vname)
    else:
      bc.needsAst = true

  of cBreak:
    bc.addInstr(opBreak)

  of cXecute:
    bc.addInstr(opXecute)

  of cLock:
    bc.addInstr(opLockReleaseAll)

  of cMerge:
    for pair in cmd.mergePairs:
      bc.addInstr(opMerge, arg1 = pair[0], arg2 = pair[1])

  of cTstart:
    bc.addInstr(opTstart)

  of cTcommit:
    bc.addInstr(opTcommit)

  of cTrollback:
    bc.addInstr(opTrollback)

  of cZloadxml:
    # ZLOADXML file, global, format — compile args as expressions
    bc.compileExpr(cmd.zloadxmlFile)
    bc.compileExpr(cmd.zloadxmlGlobal)
    bc.compileExpr(cmd.zloadxmlFormat)
    bc.addInstr(opZloadxml)

  else:
    bc.addInstr(opNop)

proc compileLine*(line: Line): Bytecode =
  ## Compile a parsed line to bytecode
  result = newBytecode()
  if line == nil: return
  for cmdNode in line.cmds:
    if cmdNode != nil and cmdNode.cmd != nil:
      result.compileCommand(cmdNode.cmd)

# --- Optimization passes (#343) ---

proc foldConstants*(bc: var Bytecode) =
  ## Fold constant expressions: PUSH_CONST a, PUSH_CONST b, OP → PUSH_CONST result
  var i = 0
  while i < bc.instructions.len - 2:
    let a = bc.instructions[i]
    let b = bc.instructions[i + 1]
    let op = bc.instructions[i + 2]
    if a.opcode == opPushConst and b.opcode == opPushConst:
      let aval = bc.constants[a.argInt]
      let bval = bc.constants[b.argInt]
      var folded: string = ""
      case op.opcode
      of opAdd:
        folded = $(numPrefix(aval) + numPrefix(bval))
      of opSub:
        folded = $(numPrefix(aval) - numPrefix(bval))
      of opMul:
        folded = $(numPrefix(aval) * numPrefix(bval))
      of opDiv:
        let r = numPrefix(bval)
        if r != 0.0: folded = $(numPrefix(aval) / r)
      of opCmpEql:
        folded = if numPrefix(aval) == numPrefix(bval): "1" else: "0"
      of opCmpNeq:
        folded = if numPrefix(aval) != numPrefix(bval): "1" else: "0"
      of opCmpLt:
        folded = if numPrefix(aval) < numPrefix(bval): "1" else: "0"
      of opCmpGt:
        folded = if numPrefix(aval) > numPrefix(bval): "1" else: "0"
      of opConcat:
        folded = aval & bval
      else:
        inc i
        continue
      if folded.len > 0:
        let idx = bc.addConst(folded)
        bc.instructions[i] = Instruction(opcode: opPushConst, argInt: idx)
        bc.instructions.delete(i + 2)
        bc.instructions.delete(i + 1)
        continue
    inc i

proc eliminateDeadCode*(bc: var Bytecode) =
  ## Remove unreachable instructions after JUMP and QUIT
  if bc.instructions.len == 0: return
  var reachable = newSeq[bool](bc.instructions.len)
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
      discard
    else:
      queue.add(idx + 1)
  var newInstrs: seq[Instruction] = @[]
  for i, instr in bc.instructions:
    if reachable[i]:
      newInstrs.add(instr)
  bc.instructions = newInstrs

proc peephole*(bc: var Bytecode) =
  ## Remove redundant instruction pairs
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

proc optimize*(bc: var Bytecode) =
  ## Run all optimization passes
  bc.foldConstants()
  bc.eliminateDeadCode()
  bc.peephole()
