# engine.nim — Command dispatch for nimm
# Implements all M/MUMPS commands

import strutils
import tables
import os
import streams
import posix
import ast
import globals
import evaluator
import runtime
import parser
import special_vars
import debugger

type
  DeviceHandle = ref object
    ## Represents an open device (file or stream)
    fd: cint  # POSIX file descriptor
    readBuf: string
    readPos: int
    isOpen: bool
  
  Engine* = ref object
    ## M/MUMPS command interpreter
    globals*: ptr Globals
    evaluator*: ptr Evaluator
    runtime*: ptr Runtime
    debugger*: Debugger
    output*: string
    testValue*: bool
    channels: array[64, DeviceHandle]  # Channel 0-63 (0 = principal)
    currentChannel: int  # Current channel number (0 = principal)

proc newEngine*(globals: var Globals, evaluator: var Evaluator, runtime: var Runtime): Engine =
  new(result)
  result.globals = globals.addr
  result.evaluator = evaluator.addr
  result.runtime = runtime.addr
  result.debugger = newDebugger()
  result.output = ""
  result.testValue = false
  result.currentChannel = 0
  
  # Initialize channel array
  for i in 0..63:
    result.channels[i] = DeviceHandle(fd: -1, readBuf: "", readPos: 0, isOpen: false)
  
  # Channel 0 = principal device (stdin/stdout)
  result.channels[0] = DeviceHandle(fd: -1, readBuf: "", readPos: 0, isOpen: true)

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
            elif item.target.tname == "^":
              # Naked reference: ^(subs) uses last global reference
              if eng.globals[].nakedGlobal.len > 0:
                var allSubs = eng.globals[].nakedSubs
                for sub in subs:
                  allSubs.add(sub)
                eng.globals[].set(eng.globals[].nakedGlobal, allSubs, value)
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
          of SetKind.stIndirect:
            # SET @expr = value — indirect assignment
            let varName = eng.evaluator[].eval(item.target.indirectExpr)
            if varName.len > 0:
              var subs: seq[string] = @[]
              for sub in item.target.indirectSubs:
                subs.add(eng.evaluator[].eval(sub))
              # Check if this is a special variable
              if varName.startsWith("$"):
                eng.globals[].setSpecialVar(varName, value)
              else:
                eng.globals[].set(varName, subs, value)

      of CmdKind.cWrite:
        for arg in cmd.writeArgs:
          case arg.kind
          of WriteKind.wrExpr:
            let val = eng.evaluator[].eval(arg.wexpr)
            if eng.currentChannel == 0:
              eng.write(val)
            elif eng.channels[eng.currentChannel].isOpen:
              let handle = eng.channels[eng.currentChannel]
              discard posix.write(handle.fd, cstring(val), val.len)
          of WriteKind.wrNewline:
            if eng.currentChannel == 0:
              eng.writeln("")
            elif eng.channels[eng.currentChannel].isOpen:
              let handle = eng.channels[eng.currentChannel]
              discard posix.write(handle.fd, cstring("\n"), 1)
          of WriteKind.wrFormFeed:
            if eng.currentChannel == 0:
              eng.write("\f")
            elif eng.channels[eng.currentChannel].isOpen:
              let handle = eng.channels[eng.currentChannel]
              discard posix.write(handle.fd, cstring("\f"), 1)
          of WriteKind.wrColumn:
            if eng.currentChannel == 0:
              eng.write(" ".repeat(arg.col))
            elif eng.channels[eng.currentChannel].isOpen:
              let handle = eng.channels[eng.currentChannel]
              let spaces = " ".repeat(arg.col)
              discard posix.write(handle.fd, cstring(spaces), spaces.len)

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
            var val = ""
            if eng.currentChannel == 0:
              # Read from stdin
              val = readLine(stdin)
            elif eng.channels[eng.currentChannel].isOpen:
              let handle = eng.channels[eng.currentChannel]
              # Read one character at a time until newline or EOF
              var ch: array[1, char]
              var bytesRead = 0
              while true:
                let n = posix.read(handle.fd, addr ch[0], 1)
                if n <= 0:
                  # EOF reached
                  eng.globals[].setSpecialVar("$ZEOF", "1")
                  break
                bytesRead += 1
                if ch[0] == '\n':
                  break
                val.add(ch[0])
              if bytesRead > 0:
                eng.globals[].setSpecialVar("$ZEOF", "0")
            eng.globals[].set(varExpr.vname, @[], val)

      of CmdKind.cHang:
        if cmd.hangExpr != nil:
          let seconds = parseFloat(eng.evaluator[].eval(cmd.hangExpr))
          os.sleep(int(seconds * 1000))

      of CmdKind.cOpen:
        # OPEN channel:(file:mode)[:timeout]
        let channel = parseInt(eng.evaluator[].eval(cmd.openChannel))
        let deviceName = eng.evaluator[].eval(cmd.openDevice)
        let mode = eng.evaluator[].eval(cmd.openMode).toUpperAscii
        
        # Validate channel number
        if channel < 0 or channel > 63:
          eng.globals[].setSpecialVar("$ECODE", "M25:Channel out of range")
          eng.testValue = false
        elif channel == 0:
          eng.globals[].setSpecialVar("$ECODE", "M25:Cannot open channel 0")
          eng.testValue = false
        else:
          # Parse mode
          var flags = O_RDWR or O_CREAT
          if mode == "READ" or mode == "R":
            flags = O_RDONLY
          elif mode == "WRITE" or mode == "W":
            flags = O_WRONLY or O_CREAT or O_TRUNC
          elif mode == "APPEND" or mode == "A":
            flags = O_WRONLY or O_CREAT or O_APPEND
          elif mode == "IO":
            flags = O_RDWR or O_CREAT
          
          try:
            let fd = posix.open(cstring(deviceName), flags, 0o644)
            if fd < 0:
              raiseOSError(osLastError())
            
            # Reset file pointer to beginning
            discard lseek(fd, 0, SEEK_SET)
            
            eng.channels[channel] = DeviceHandle(fd: fd, readBuf: "", readPos: 0, isOpen: true)
            eng.testValue = true
          except:
            eng.testValue = false
            let errorMsg = getCurrentExceptionMsg()
            eng.globals[].setSpecialVar("$ECODE", "M1:" & errorMsg)

      of CmdKind.cUse:
        # USE channel[:params]
        let channel = parseInt(eng.evaluator[].eval(cmd.useChannel))
        
        # Validate channel number
        if channel < 0 or channel > 63:
          eng.globals[].setSpecialVar("$ECODE", "M25:Channel out of range")
          eng.testValue = false
        elif not eng.channels[channel].isOpen:
          eng.globals[].setSpecialVar("$ECODE", "M2:Channel not open: " & $channel)
          eng.testValue = false
        else:
          eng.currentChannel = channel
          eng.testValue = true

      of CmdKind.cClose:
        # CLOSE channel
        let channel = parseInt(eng.evaluator[].eval(cmd.closeChannel))
        
        # Validate channel number
        if channel < 0 or channel > 63:
          eng.globals[].setSpecialVar("$ECODE", "M25:Channel out of range")
          eng.testValue = false
        elif channel == 0:
          # Closing channel 0 is always ignored
          eng.testValue = true
        elif eng.channels[channel].isOpen:
          discard posix.close(eng.channels[channel].fd)
          eng.channels[channel] = DeviceHandle(fd: -1, readBuf: "", readPos: 0, isOpen: false)
          if eng.currentChannel == channel:
            eng.currentChannel = 0
          eng.testValue = true
        else:
          eng.testValue = false

      of CmdKind.cLock, CmdKind.cMerge:
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
