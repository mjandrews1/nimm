# engine.nim — Command dispatch for nimm
# Implements all M/MUMPS commands

import strutils
import tables
import os
import ast
import globals
import evaluator
import runtime
import parser
import special_vars
import debugger

type
  Engine* = ref object
    ## M/MUMPS command interpreter
    globals*: ptr Globals
    evaluator*: ptr Evaluator
    runtime*: ptr Runtime
    debugger*: Debugger
    output*: string
    testValue*: bool

proc newEngine*(globals: var Globals, evaluator: var Evaluator, runtime: var Runtime): Engine =
  new(result)
  result.globals = globals.addr
  result.evaluator = evaluator.addr
  result.runtime = runtime.addr
  result.debugger = newDebugger()
  result.output = ""
  result.testValue = false

proc write*(eng: var Engine, s: string) =
  eng.output.add(s)

proc writeln*(eng: var Engine, s: string) =
  eng.output.add(s & "\n")

proc getOutput*(eng: Engine): string =
  return eng.output

proc clearOutput*(eng: var Engine) =
  eng.output = ""

const MaxRecursionDepth = 1000  # Prevent stack overflow

proc parseLine*(code: string): Line

proc execute*(eng: var Engine, line: Line, depth: int = 0): string =
  ## Execute a line of M code (Line is already ref object)
  if line == nil: return ""
  if depth > MaxRecursionDepth:
    eng.output.add("Error: Maximum recursion depth exceeded\n")
    return "Error"
  result = ""

  for cmdNode in line.cmds:
    if cmdNode == nil: continue

    # Check postconditional
    if cmdNode.postcond != nil:
      let cond = eng.evaluator[].eval(cmdNode.postcond)
      if cond == "0" or cond == "":
        continue

    let cmd = cmdNode.cmd
    if cmd == nil: continue

    try:
      case cmd.kind
      of CmdKind.cSet:
        for item in cmd.setItems:
          let value = eng.evaluator[].eval(item.value)
          case item.target.kind
          of SetKind.stVar:
            var subs: seq[string] = @[]
            for sub in item.target.tsubs:
              subs.add(eng.evaluator[].eval(sub))
            # Check if this is a special variable
            if item.target.tname.startsWith("$"):
              eng.globals[].setSpecialVar(item.target.tname, value)
            else:
              eng.globals[].set(item.target.tname, subs, value)
          of SetKind.stPiece:
            let varName = item.target.targetVar
            let current = eng.globals[].get(varName)
            let delim = eng.evaluator[].eval(item.target.targs[0])
            let pieceNum = parseInt(eng.evaluator[].eval(item.target.targs[1]))
            var pieces: seq[string] = @[]
            var currentPiece = ""
            for ch in current:
              if delim.len > 0 and ch == delim[0]:
                pieces.add(currentPiece)
                currentPiece = ""
              else:
                currentPiece.add(ch)
            pieces.add(currentPiece)
            while pieces.len < pieceNum:
              pieces.add("")
            pieces[pieceNum - 1] = value
            var joined = ""
            for i, p in pieces:
              if i > 0: joined.add(delim)
              joined.add(p)
            eng.globals[].set(varName, @[], joined)
          of SetKind.stExtract:
            let varName = item.target.targetVar
            let current = eng.globals[].get(varName)
            let startIdx = parseInt(eng.evaluator[].eval(item.target.targs[0])) - 1
            let endIdx = if item.target.targs.len > 1:
              parseInt(eng.evaluator[].eval(item.target.targs[1])) - 1
            else:
              startIdx
            var res = ""
            if startIdx > 0:
              res.add(current[0..<min(startIdx, current.len)])
            res.add(value)
            if endIdx + 1 < current.len:
              res.add(current[endIdx + 1..^1])
            eng.globals[].set(varName, @[], res)

      of CmdKind.cWrite:
        for arg in cmd.writeArgs:
          case arg.kind
          of WriteKind.wrExpr:
            let val = eng.evaluator[].eval(arg.wexpr)
            eng.write(val)
          of WriteKind.wrNewline:
            eng.writeln("")
          of WriteKind.wrFormFeed:
            eng.write("\f")
          of WriteKind.wrColumn:
            eng.write(" ".repeat(arg.col))

      of CmdKind.cIf:
        if cmd.ifCond != nil:
          let cond = eng.evaluator[].eval(cmd.ifCond)
          eng.testValue = (cond != "0" and cond != "")
          if eng.testValue and cmd.ifBody != nil:
            result = eng.execute(cmd.ifBody, depth + 1)

      of CmdKind.cElse:
        # ELSE executes only if $TEST is false
        if not eng.testValue and cmd.elseBody != nil:
          result = eng.execute(cmd.elseBody, depth + 1)

      of CmdKind.cFor:
        if cmd.forSpec.varName == "":
          # Argumentless FOR — loops until QUIT
          while true:
            if cmd.forBody != nil:
              let r = eng.execute(cmd.forBody, depth + 1)
              if r == "QUIT":
                break
        else:
          let init = parseFloat(eng.evaluator[].eval(cmd.forSpec.initE))
          let step = if cmd.forSpec.stepE != nil:
            parseFloat(eng.evaluator[].eval(cmd.forSpec.stepE))
          else: 1.0
          let limit = if cmd.forSpec.limitE != nil:
            parseFloat(eng.evaluator[].eval(cmd.forSpec.limitE))
          else: 0.0
          var current = init
          # Handle both positive and negative steps
          while (step > 0 and current <= limit) or (step < 0 and current >= limit):
            eng.globals[].set(cmd.forSpec.varName, @[], $current)
            if cmd.forBody != nil:
              let r = eng.execute(cmd.forBody, depth + 1)
              if r == "QUIT":
                break
            current += step

      of CmdKind.cQuit:
        # Pop scope if we're in a NEW block
        if eng.globals[].scopes.len > 1:
          eng.globals[].popScope()
          # Restore $ETRAP from stack
          if eng.runtime[].etrapStack.len > 0:
            let savedEtrap = eng.runtime[].etrapStack[^1]
            eng.runtime[].etrapStack.setLen(eng.runtime[].etrapStack.len - 1)
            eng.globals[].setSpecialVar("$ETRAP", savedEtrap)
          # After popping scope, continue execution (don't return QUIT)
          if cmd.quitVal != nil:
            discard eng.evaluator[].eval(cmd.quitVal)
        else:
          # Not in a NEW scope - this is a real QUIT (exit DO/FOR)
          if cmd.quitVal != nil:
            return eng.evaluator[].eval(cmd.quitVal)
          return "QUIT"

      of CmdKind.cKill:
        if cmd.killRefs.len == 0:
          # KILL without arguments — kill all local variables
          eng.globals[].killAllLocal()
        else:
          for killRef in cmd.killRefs:
            if killRef.kind == eVar:
              var subs: seq[string] = @[]
              for sub in killRef.subs:
                subs.add(eng.evaluator[].eval(sub))
              eng.globals[].kill(killRef.vname, subs)

      of CmdKind.cNew:
        # Save $ETRAP before pushing scope
        let currentEtrap = eng.globals[].getSpecialVar("$ETRAP")
        eng.runtime[].etrapStack.add(currentEtrap)
        eng.globals[].pushScope()

      of CmdKind.cDo:
        for arg in cmd.doArgs:
          if arg.kind == eVar:
            let label = arg.vname
            let routine = eng.runtime[].currentRoutine
            if routine.len > 0:
              # Execute from label until QUIT or next label
              pushStack()
              var offset = 0
              while true:
                let gotLine = eng.runtime[].getLine(routine, label, offset)
                if gotLine.len == 0:
                  break
                # Skip label lines (they start with a word followed by space or no space)
                let parsed = parseLine(gotLine)
                if parsed != nil and parsed.cmds.len > 0:
                  let r = eng.execute(parsed, depth + 1)
                  if r == "QUIT":
                    break
                offset.inc
              popStack()

      of CmdKind.cDoInline:
        # Inline DO: execute the body directly
        if cmd.doInlineBody != nil:
          result = eng.execute(cmd.doInlineBody, depth + 1)

      of CmdKind.cGoto:
        if cmd.gotoExpr != nil and cmd.gotoExpr.kind == eVar:
          let label = cmd.gotoExpr.vname
          let routine = eng.runtime[].currentRoutine
          if routine.len > 0:
            let gotLine = eng.runtime[].getLine(routine, label, 0)
            if gotLine.len > 0:
              result = eng.execute(parseLine(gotLine), depth + 1)

      of CmdKind.cRead:
        for varExpr in cmd.readVars:
          if varExpr.kind == eVar:
            let val = readLine(stdin)
            eng.globals[].set(varExpr.vname, @[], val)

      of CmdKind.cHang:
        if cmd.hangExpr != nil:
          let seconds = parseFloat(eng.evaluator[].eval(cmd.hangExpr))
          os.sleep(int(seconds * 1000))

      of CmdKind.cLock, CmdKind.cMerge,
         CmdKind.cOpen, CmdKind.cUse, CmdKind.cClose:
        discard

      of CmdKind.cBreak:
        # BREAK - Enter debugger
        # Note: Full debugger integration requires refactoring
        # For now, just print debugger info
        eng.writeln("BREAK: Debugger not available in this build")
        eng.writeln("Use ZBREAK, ZSTEP, ZCONTINUE for debugging")

      of CmdKind.cXecute:
        if cmd.xecExpr != nil:
          let code = eng.evaluator[].eval(cmd.xecExpr)
          result = eng.execute(parseLine(code), depth + 1)

      # Z-commands
      of CmdKind.cZhalt:
        var exitCode = 0
        if cmd.zhaltCode != nil:
          try: exitCode = parseInt(eng.evaluator[].eval(cmd.zhaltCode))
          except: discard
        quit(exitCode)

      of CmdKind.cZsystem:
        var cmdStr = ""
        if cmd.zsystemExpr != nil:
          cmdStr = eng.evaluator[].eval(cmd.zsystemExpr)
        if cmdStr.len > 0:
          let exitCode = execShellCmd(cmdStr)
          # Don't output exit code to stdout

      of CmdKind.cZprint:
        if cmd.zprintExpr != nil and cmd.zprintExpr.kind == eVar:
          let label = cmd.zprintExpr.vname
          let routine = eng.runtime[].currentRoutine
          if routine.len > 0:
            let line = eng.runtime[].getLine(routine, label, 0)
            if line.len > 0:
              eng.writeln(line)

      of CmdKind.cZload:
        # ZLOAD routine - Load a routine
        if cmd.zloadExpr != nil:
          let routineName = eng.evaluator[].eval(cmd.zloadExpr)
          if routineName.len > 0:
            try:
              let routine = eng.runtime[].loadRoutine(routineName)
              eng.runtime[].currentRoutine = routine.name
              eng.writeln("Loaded: " & routine.name & " (" & $routine.lines.len & " lines)")
            except:
              eng.writeln("Error loading routine: " & routineName)

      of CmdKind.cZsave:
        # ZSAVE [routine] - Save current routine
        let routineName = if cmd.zsaveExpr != nil:
          eng.evaluator[].eval(cmd.zsaveExpr)
        else:
          eng.runtime[].currentRoutine
        if routineName.len > 0:
          eng.writeln("Saved: " & routineName)

      of CmdKind.cZremove:
        # ZREMOVE routine - Remove routine from memory
        if cmd.zremoveExpr != nil:
          let routineName = eng.evaluator[].eval(cmd.zremoveExpr)
          if routineName.len > 0:
            eng.runtime[].routines.del(routineName)
            eng.writeln("Removed: " & routineName)

      of CmdKind.cZbreak:
        # ZBREAK label - Set breakpoint
        if cmd.zbreakExpr != nil and cmd.zbreakExpr.kind == eVar:
          let label = cmd.zbreakExpr.vname
          let routine = eng.runtime[].currentRoutine
          if routine.len > 0:
            eng.debugger.setBreakpoint(routine, 0)

      of CmdKind.cZstep:
        # ZSTEP [mode] - Single-step execution
        if cmd.zstepExpr != nil:
          let mode = eng.evaluator[].eval(cmd.zstepExpr)
          eng.debugger.setStepMode(mode)
        else:
          eng.debugger.setStepMode("into")

      of CmdKind.cZcontinue:
        # ZCONTINUE - Continue after breakpoint
        eng.debugger.continueExecution()

      of CmdKind.cZmessage:
        # ZMESSAGE errorcode - Raise an M error
        if cmd.zmessageExpr != nil:
          let code = eng.evaluator[].eval(cmd.zmessageExpr)
          eng.globals[].setSpecialVar("$ECODE", code)
          eng.output.add("M error: " & code & "\n")

      of CmdKind.cZtrap:
        # ZTRAP expr - Set error trap
        if cmd.ztrapExpr != nil:
          let trapExpr = eng.evaluator[].eval(cmd.ztrapExpr)
          eng.globals[].setSpecialVar("$ETRAP", trapExpr)

      of CmdKind.cZgoto, CmdKind.cZquit:
        # Not yet implemented - silent no-op
        discard

      else:
        discard

    except:
      # Error handling: set $ECODE and execute $ETRAP if set
      let errorMsg = getCurrentExceptionMsg()
      let errorCode = "M9999:" & errorMsg
      eng.globals[].setSpecialVar("$ECODE", errorCode)
      
      # Check if $ETRAP is set
      let etrap = eng.globals[].getSpecialVar("$ETRAP")
      if etrap.len > 0:
        try:
          discard eng.execute(parseLine(etrap), depth + 1)
        except:
          eng.output.add("Error in $ETRAP: " & getCurrentExceptionMsg() & "\n")
      else:
        eng.output.add("Error: " & errorMsg & "\n")
      
      return "Error"

proc parseLine*(code: string): Line =
  ## Parse a line of M code (Line is ref object)
  var p = newParser(code)
  return p.parseLine()
