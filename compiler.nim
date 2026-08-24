# compiler.nim — AST to bytecode compiler for NimM
# Compiles M/MUMPS AST nodes to stack-based bytecode instructions

import ast
import bytecode
import strutils

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
    # FOR var=start:step:end — simplified
    bc.addInstr(opNop)  # placeholder

  of cQuit:
    bc.addInstr(opQuit)

  of cKill:
    bc.addInstr(opNop)  # placeholder

  of cNew:
    bc.addInstr(opNewScope, arg1 = cmd.newNames.join(","))

  of cNewExcept:
    bc.addInstr(opNewScope, arg1 = cmd.newKeep.join(","))

  of cDo:
    bc.addInstr(opNop)  # placeholder — needs DO compilation

  of cDoInline:
    if cmd.doInlineBody != nil:
      for childCmd in cmd.doInlineBody.cmds:
        bc.compileCommand(childCmd.cmd)

  of cGoto:
    bc.addInstr(opNop)  # placeholder — needs GOTO compilation

  of cBreak:
    bc.addInstr(opNop)  # placeholder

  of cXecute:
    bc.addInstr(opXecute)

  of cLock:
    bc.addInstr(opLockReleaseAll)

  of cMerge:
    bc.addInstr(opNop)  # placeholder

  of cTstart:
    bc.addInstr(opTstart)

  of cTcommit:
    bc.addInstr(opTcommit)

  of cTrollback:
    bc.addInstr(opTrollback)

  else:
    bc.addInstr(opNop)

proc compileLine*(line: Line): Bytecode =
  ## Compile a parsed line to bytecode
  result = newBytecode()
  if line == nil: return
  for cmdNode in line.cmds:
    if cmdNode != nil and cmdNode.cmd != nil:
      result.compileCommand(cmdNode.cmd)
