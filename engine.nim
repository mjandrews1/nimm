# engine.nim — Command dispatch for nimm
# Implements all M/MUMPS commands

import strutils
import tables
import os
import osproc
import streams
import posix
import ast
import globals
import evaluator
import runtime
import parser
import special_vars
import debugger
import inspector
import jobs
import value

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
    inspector*: Inspector
    callStack*: seq[StackFrame]
    output*: string
    testValue*: bool
    quitAll*: bool  # Set by top-level QUIT: unwind everything and halt
    doDepth*: int   # DO/XECUTE/extrinsic frame depth (0 = top level)
    channels: array[64, DeviceHandle]  # Channel 0-63 (0 = principal)
    currentChannel: int  # Current channel number (0 = principal)
    jobTable*: JobTable  # Job table for JOB command

# Global engine reference for debugger evalProc closure
var globalEngine: Engine = nil

proc newEngine*(globals: var Globals, evaluator: var Evaluator, runtime: var Runtime): Engine =
  new(result)
  result.globals = globals.addr
  result.evaluator = evaluator.addr
  result.runtime = runtime.addr
  result.debugger = newDebugger()
  result.inspector = newInspector()
  result.callStack = @[]
  result.output = ""
  result.testValue = false
  result.currentChannel = 0
  result.quitAll = false
  result.doDepth = 0
  result.jobTable = newJobTable()
  
  # Set global reference for debugger evalProc closure
  globalEngine = result
  
  # Initialize channel array
  for i in 0..63:
    result.channels[i] = DeviceHandle(fd: -1, readBuf: "", readPos: 0, isOpen: false)
  
  # Channel 0 = principal device (stdin/stdout)
  result.channels[0] = DeviceHandle(fd: -1, readBuf: "", readPos: 0, isOpen: true)

proc write*(eng: var Engine, s: string) =
  advanceDevicePos(s)
  eng.output.add(s)

proc writeln*(eng: var Engine, s: string) =
  advanceDevicePos(s & "\n")
  eng.output.add(s & "\n")

proc getOutput*(eng: Engine): string =
  return eng.output

proc clearOutput*(eng: var Engine) =
  eng.output = ""

const MaxRecursionDepth = 1000  # Prevent stack overflow

proc parseLine*(code: string): Line
proc cachedParseLine*(eng: var Engine, code: string): Line

proc lockRefName(ev: var Evaluator, e: Expr): string =
  ## Extract a LOCK argument's resource name (#278): the reference text
  ## itself (^L1, ^L1(2), A), not the argument's value.
  case e.kind
  of eVar:
    var name = e.vname
    if e.subs.len > 0:
      var subs: seq[string] = @[]
      for sub in e.subs:
        subs.add(ev.eval(sub))
      name = name & "(" & subs.join(",") & ")"
    return name
  else:
    return ev.eval(e)

proc execute*(eng: var Engine, line: Line, depth: int = 0): string =
  ## Execute a line of M code (Line is already ref object)
  if line == nil: return ""
  if depth > MaxRecursionDepth:
    eng.output.add("Error: Maximum recursion depth exceeded\n")
    return "Error"
  result = ""

  for cmdNode in line.cmds:
    if eng.quitAll: break
    if cmdNode == nil: continue

    # Check postconditional
    if cmdNode.postcond != nil:
      let cond = eng.evaluator[].eval(cmdNode.postcond)
      if not truthy(cond):
        continue

    let cmd = cmdNode.cmd
    if cmd == nil: continue

    # Update debugger position for source-level stepping (#326)
    eng.debugger.currentLine = cmdNode.line
    eng.debugger.currentCol = cmdNode.col

    # Record command execution for introspection
    eng.inspector.recordCommand()

    # Check breakpoints — enter stepping mode if breakpoint hit
    let routine = eng.runtime[].currentRoutine
    if eng.debugger.shouldBreak(routine, 0):
      eng.writeln("BREAK at " & routine)
      eng.debugger.setStepMode("into")

    try:
      case cmd.kind
      of CmdKind.cSet:
        for item in cmd.setItems:
          let value = eng.evaluator[].eval(item.value)
          case item.target.kind
          of SetKind.stVar:
            if item.target.tsubs.len == 0:
              if item.target.tname.startsWith("$"):
                eng.globals[].setSpecialVar(item.target.tname, value)
              elif item.target.tname == "^":
                if eng.globals[].nakedGlobal.len > 0:
                  eng.globals[].set(eng.globals[].nakedGlobal, eng.globals[].nakedSubs, value)
              elif item.target.tname.startsWith("^"):
                eng.globals[].set(item.target.tname, @[], value)
              else:
                eng.globals[].setLocalDirect(item.target.tname, value)
              eng.inspector.recordVariableAccess(item.target.tname, value)
            else:
              var subs: seq[string] = @[]
              for sub in item.target.tsubs:
                subs.add(eng.evaluator[].eval(sub))
              if item.target.tname.startsWith("$"):
                eng.globals[].setSpecialVar(item.target.tname, value)
              elif item.target.tname == "^":
                if eng.globals[].nakedGlobal.len > 0:
                  # §2.4.2: provided subscripts replace the last one
                  var allSubs =
                    if eng.globals[].nakedSubs.len > 0:
                      eng.globals[].nakedSubs[0 ..< ^1]
                    else:
                      @[]
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
            eng.globals[].setLocalDirect(varName, joined)
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
            eng.globals[].setLocalDirect(varName, res)
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
          eng.testValue = truthy(cond)
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
              if r == "QUIT" or eng.quitAll:
                break
            elif eng.quitAll:
              break
        else:
          # Comma-separated FOR args share the variable; QUIT exits all (§7.2.6)
          var specs = @[cmd.forSpec]
          for extra in cmd.forSpec.altSpecs:
            specs.add(extra)
          var quitFor = false
          block forArgs:
            for spec in specs:
              let init = parseFloat(eng.evaluator[].eval(spec.initE))
              if spec.onceOnly:
                eng.globals[].setLocalDirect(cmd.forSpec.varName,
                                             formatNumber(init))
                if cmd.forBody != nil:
                  let r = eng.execute(cmd.forBody, depth + 1)
                  if r == "QUIT" or eng.quitAll:
                    quitFor = true
                    break forArgs
                elif eng.quitAll:
                  quitFor = true
                  break forArgs
                continue
              let step = if spec.stepE != nil:
                parseFloat(eng.evaluator[].eval(spec.stepE))
              else: 1.0
              let limit = if spec.hasLimit:
                parseFloat(eng.evaluator[].eval(spec.limitE))
              else: 0.0
              var current = init
              while true:
                if spec.hasLimit:
                  if not ((step > 0 and current <= limit) or
                          (step < 0 and current >= limit)):
                    break
                eng.globals[].setLocalDirect(cmd.forSpec.varName,
                                             formatNumber(current))
                if cmd.forBody != nil:
                  let r = eng.execute(cmd.forBody, depth + 1)
                  if r == "QUIT" or eng.quitAll:
                    quitFor = true
                    break forArgs
                elif eng.quitAll:
                  quitFor = true
                  break forArgs
                if not spec.hasLimit and step == 0.0:
                  break
                current += step
          discard quitFor

      of CmdKind.cQuit:
        # Unwind NEW scopes created since frame entry (or all at top level)
        while eng.globals[].scopes.len > 1:
          eng.globals[].popScope()
          if eng.runtime[].etrapStack.len > 0:
            let savedEtrap = eng.runtime[].etrapStack[^1]
            eng.runtime[].etrapStack.setLen(eng.runtime[].etrapStack.len - 1)
            eng.globals[].setSpecialVar("$ETRAP", savedEtrap)
        if cmd.quitVal != nil:
          discard eng.evaluator[].eval(cmd.quitVal)
        if eng.doDepth == 0:
          # Top-level QUIT: terminate execution entirely (ANSI/ISO 10.3)
          eng.quitAll = true
          return ""
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

      of CmdKind.cKillExcept:
        # Exclusive KILL (A,B): kill everything except listed vars.
        # Per ANSI/ISO 12.2 this spans locals AND globals; a global named in
        # the keep list survives, otherwise all globals are deleted.
        var keep: seq[string] = @[]
        for keepRef in cmd.killKeep:
          if keepRef.kind == eVar:
            keep.add(keepRef.vname)
        eng.globals[].killAllExceptLocal(keep)
        eng.globals[].killAllGlobalsExcept(keep)

      of CmdKind.cNew:
        # Save $ETRAP before pushing scope
        let currentEtrap = eng.globals[].getSpecialVar("$ETRAP")
        eng.runtime[].etrapStack.add(currentEtrap)
        eng.globals[].pushScope()

      of CmdKind.cNewExcept:
        # Exclusive NEW (A,B): listed vars stay visible, all others cleared
        # within the new scope; popScope restores them (§7.2.12)
        let currentEtrap = eng.globals[].getSpecialVar("$ETRAP")
        eng.runtime[].etrapStack.add(currentEtrap)
        eng.globals[].pushScope()
        eng.globals[].killAllExceptLocal(cmd.newKeep)

      of CmdKind.cDo:
        for arg in cmd.doArgs:
          # §7.2.5: DO entryref — label in current routine or label^routine (#288)
          let label = if arg.kind == eEntryRef: arg.entryLabel
                      elif arg.kind == eVar: arg.vname
                      else: continue
          let routine = if arg.kind == eEntryRef and arg.entryRoutine.len > 0:
                          arg.entryRoutine
                        else:
                          eng.runtime[].currentRoutine
          if routine.len > 0 and label.len > 0:
            # Push call stack frame for introspection
            let frame = StackFrame(routine: routine, label: label, line: 0, variables: initTable[string, string]())
            eng.callStack.add(frame)
            pushStack()
            eng.doDepth.inc
            var offset = 0
            while true:
              let gotLine = eng.runtime[].getLine(routine, label, offset)
              if gotLine.len == 0:
                break
              let parsed = eng.cachedParseLine(stripLabel(gotLine))
              if parsed != nil and parsed.cmds.len > 0:
                let r = eng.execute(parsed, depth + 1)
                if r == "QUIT" or eng.quitAll:
                  break
              offset.inc
            eng.doDepth.dec
            popStack()
            # Pop call stack frame
            if eng.callStack.len > 0:
              discard eng.callStack.pop()

      of CmdKind.cDoInline:
        # Inline DO: execute the body directly
        if cmd.doInlineBody != nil:
          eng.doDepth.inc
          result = eng.execute(cmd.doInlineBody, depth + 1)
          eng.doDepth.dec

      of CmdKind.cGoto:
        if cmd.gotoExpr != nil:
          let label = if cmd.gotoExpr.kind == eEntryRef: cmd.gotoExpr.entryLabel
                      elif cmd.gotoExpr.kind == eVar: cmd.gotoExpr.vname
                      else: ""
          let routine = if cmd.gotoExpr.kind == eEntryRef and cmd.gotoExpr.entryRoutine.len > 0:
                          cmd.gotoExpr.entryRoutine
                        else:
                          eng.runtime[].currentRoutine
          if label.len > 0 and routine.len > 0:
            # §7.2.4: GOTO transfers control to the label; execution
            # continues forward until QUIT or end of routine (#287).
            var offset = 0
            while true:
              let gotLine = eng.runtime[].getLine(routine, label, offset)
              if gotLine.len == 0:
                break
              let parsed = eng.cachedParseLine(stripLabel(gotLine))
              if parsed != nil and parsed.cmds.len > 0:
                result = eng.execute(parsed, depth + 1)
                if result == "QUIT" or eng.quitAll:
                  break
              offset.inc

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
              var hitEof = false
              while true:
                let n = posix.read(handle.fd, addr ch[0], 1)
                if n <= 0:
                  # EOF reached
                  hitEof = true
                  eng.globals[].setSpecialVar("$ZEOF", "1")
                  break
                bytesRead += 1
                if ch[0] == '\n':
                  break
                val.add(ch[0])
              if bytesRead > 0 and not hitEof:
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

      of CmdKind.cLock:
        # LOCK [+|-]ref[,(+|-)ref]... — resource locks (#278).
        # Single-process semantics: held names are recorded in a process-
        # local table; $DATA(^$LOCK("name")) reads it back. Bare LOCK
        # releases everything. The parser folds "+" into ePos and "-" into
        # eNeg, so unwrap those to recover the lock operator, then use the
        # argument's NAME (not its value).
        if cmd.lockRefs.len == 0:
          eng.globals[].releaseAllLocks()
        else:
          for refExpr in cmd.lockRefs:
            var op = "+"
            var inner = refExpr
            while inner.kind in {ePos, eNeg}:
              if inner.kind == eNeg: op = "-"
              inner = inner.operand
            let lname = eng.evaluator[].lockRefName(inner)
            if lname.len > 0:
              if op == "-": eng.globals[].releaseLock(lname)
              else: eng.globals[].acquireLock(lname)
        eng.testValue = true

      of CmdKind.cMerge:
        # MERGE dest=src — Copy entire variable trees
        for pair in cmd.mergePairs:
          let destName = pair[0]
          let srcName = pair[1]
          # Copy the root value (if any)
          let rootVal = eng.globals[].get(srcName)
          if rootVal.len > 0:
            eng.globals[].set(destName, @[], rootVal)
          # Copy all subscripts
          let allSubs = eng.globals[].listSubs(srcName)
          for subs in allSubs:
            let val = eng.globals[].get(srcName, subs)
            eng.globals[].set(destName, subs, val)
        eng.testValue = true

      of CmdKind.cBreak:
        # BREAK — Enter interactive debugger
        eng.writeln("BREAK")
        # Use global engine reference for debugger evalProc closure
        if globalEngine != nil:
          let evalProc = proc(cmd: string): string =
            try:
              # Try as variable expression first (for debugger print command)
              if cmd.len > 0 and cmd[0] in {'A'..'Z', 'a'..'z', '^', '$'}:
                # Use evaluator to get variable value
                let varExpr = Expr(kind: eVar, vname: cmd.toUpperAscii(), subs: @[])
                return globalEngine.evaluator[].eval(varExpr)
              # Try as full command
              let parsed = parseLine(cmd)
              if parsed != nil and parsed.cmds.len > 0:
                return globalEngine.execute(parsed, depth + 1)
            except:
              discard
            return ""
          eng.debugger.debugPromptLoop(evalProc)
        else:
          # Fallback: enter step mode
          eng.debugger.setStepMode("into")
          eng.writeln("Stepping enabled. Use ZCONTINUE to resume.")

      of CmdKind.cXecute:
        if cmd.xecExpr != nil:
          let code = eng.evaluator[].eval(cmd.xecExpr)
          eng.doDepth.inc
          result = eng.execute(eng.cachedParseLine(code), depth + 1)
          eng.doDepth.dec

      of CmdKind.cJob:
        # JOB entryref[:timeout] — start new process to run routine
        if cmd.jobEntry != nil:
          let entry = eng.evaluator[].eval(cmd.jobEntry)
          let currentFile = eng.runtime[].currentFile
          var timeout = 0
          if cmd.jobTimeout != nil:
            try:
              timeout = parseInt(eng.evaluator[].eval(cmd.jobTimeout))
            except:
              discard

          try:
            let dbPath = eng.globals[].dbPath
            let parentJobNum = parseInt(eng.globals[].getSpecialVar("$JOB"))
            let jobNum = eng.jobTable.spawnJob(entry, currentFile, dbPath, parentJobNum, timeout)
            eng.globals[].setLocal("$JOB", @[], $jobNum)
            # $TEST semantics: with timeout, always 1; without timeout, unchanged
            if timeout > 0:
              eng.testValue = true
          except:
            # JOB failed — $TEST = 0 only with timeout
            if timeout > 0:
              eng.testValue = false
        else:
          if cmd.jobTimeout != nil:
            eng.testValue = false

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
              eng.runtime[].currentFile = routineName
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
        # ZBREAK [label] — Set/remove/list breakpoints
        if cmd.zbreakExpr != nil:
          let arg = eng.evaluator[].eval(cmd.zbreakExpr)
          let routine = eng.runtime[].currentRoutine
          if arg == "-L" or arg == "-l":
            # List breakpoints
            eng.debugger.listBreakpoints()
          elif arg == "-C" or arg == "-c":
            # Clear all breakpoints
            eng.debugger.clearBreakpoints()
          elif arg == "-N" or arg == "-n":
            # Remove breakpoint at current routine
            if routine.len > 0:
              eng.debugger.removeBreakpoint(routine, 0)
          elif arg.startsWith("-"):
            eng.writeln("ZBREAK: Unknown option " & arg)
          else:
            # Set breakpoint at label
            if routine.len > 0:
              eng.debugger.setBreakpoint(routine, 0)
        else:
          # ZBREAK with no args — list breakpoints
          eng.debugger.listBreakpoints()

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

      of CmdKind.cZgoto:
        # ZGOTO label — Transfer control (Z-version of GOTO)
        if cmd.zgotoExpr != nil:
          let label = if cmd.zgotoExpr.kind == eEntryRef: cmd.zgotoExpr.entryLabel
                      elif cmd.zgotoExpr.kind == eVar: cmd.zgotoExpr.vname
                      else: ""
          let routine = if cmd.zgotoExpr.kind == eEntryRef and cmd.zgotoExpr.entryRoutine.len > 0:
                          cmd.zgotoExpr.entryRoutine
                        else:
                          eng.runtime[].currentRoutine
          if label.len > 0 and routine.len > 0:
            var offset = 0
            while true:
              let gotLine = eng.runtime[].getLine(routine, label, offset)
              if gotLine.len == 0:
                break
              let parsed = eng.cachedParseLine(stripLabel(gotLine))
              if parsed != nil and parsed.cmds.len > 0:
                result = eng.execute(parsed, depth + 1)
                if result == "QUIT" or eng.quitAll:
                  break
              offset.inc

      of CmdKind.cZquit:
        # ZQUIT — Exit with value (Z-version of QUIT)
        return "QUIT"

      of CmdKind.cZedit:
        # ZEDIT routine — Open routine in external editor
        if cmd.zeditExpr != nil:
          let routineName = eng.evaluator[].eval(cmd.zeditExpr)
          let currentFile = eng.runtime[].currentFile
          if currentFile.len > 0:
            let editor = getEnv("EDITOR", "vi")
            discard execShellCmd(editor & " " & currentFile)

      of CmdKind.cZlink:
        # ZLINK routine — Reload routine from disk
        if cmd.zlinkExpr != nil:
          let routineName = eng.evaluator[].eval(cmd.zlinkExpr)
          let currentFile = eng.runtime[].currentFile
          if currentFile.len > 0:
            try:
              let routine = eng.runtime[].loadRoutine(currentFile)
              eng.runtime[].currentRoutine = routine.name
            except:
              discard
          else:
            discard

      of CmdKind.cView:
        # VIEW expr — View/modify system parameters (#308)
        # Read-only: VIEW 0..7 returns introspection values
        # Read-write: VIEW 10:val sets runtime flags
        if cmd.viewExpr != nil:
          let arg = eng.evaluator[].eval(cmd.viewExpr)
          # Check for expr:expr form (read-write)
          let colonPos = arg.find(':')
          if colonPos >= 0:
            let codeStr = arg[0..<colonPos]
            let valStr = arg[colonPos+1..^1]
            try:
              let code = parseInt(codeStr)
              let val = parseInt(valStr)
              case code
              of 10: eng.runtime[].tracingEnabled = (val != 0)
              of 11: eng.debugger.debugPrompt = (val != 0)
              else: discard
            except:
              discard
          else:
            # Read-only — labeled output (#310)
            try:
              let code = parseInt(arg)
              case code
              of 0: eng.writeln("doDepth: " & $eng.doDepth)
              of 1: eng.writeln("tlevel: " & $eng.globals[].txn.levels.len)
              of 2: eng.writeln("locks: 0")
              of 3: eng.writeln("varHistory: " & $eng.inspector.variableHistory.len)
              of 4: eng.writeln("commands: " & $eng.inspector.stats.commandsExecuted)
              of 5: eng.writeln("funcCalls: " & $eng.inspector.stats.functionCalls)
              of 6: eng.writeln("varAccesses: " & $eng.inspector.stats.variableAccesses)
              of 7: eng.writeln("routine: " & eng.runtime[].currentRoutine)
              else: discard
            except:
              # String arg — RSM-compatible, labeled
              let s = arg.toUpperAscii
              case s
              of "BLKSIZE": eng.writeln("blksize: 4096")
              of "DBFILE": eng.writeln("dbfile: " & eng.globals[].dbPath)
              else: discard

      of CmdKind.cZallocate:
        # ZALLOCATE ^global — Pre-allocate global storage (no-op in nimm)
        discard

      of CmdKind.cZdeallocate:
        # ZDEALLOCATE ^global — Deallocate global storage (no-op in nimm)
        discard

      of CmdKind.cZstack:
        # ZSTACK — Display call stack for introspection
        eng.writeln("Call Stack:")
        if eng.callStack.len == 0:
          eng.writeln("  (empty)")
        else:
          for i, frame in eng.callStack:
            eng.writeln("  " & $i & ": " & frame.routine & ":" & frame.label)

      of CmdKind.cZstats:
        # ZSTATS — Display runtime statistics for introspection
        eng.inspector.updateStats()
        eng.writeln(eng.inspector.formatStats())

      of CmdKind.cZvhistory:
        # ZVHISTORY — Display variable access history for introspection
        let history = eng.inspector.getVariableHistory()
        if history.len == 0:
          eng.writeln("No variable accesses recorded")
        else:
          eng.writeln("Variable History (last " & $min(history.len, 20) & "):")
          for i in max(0, history.len - 20)..<history.len:
            let (name, value, ts) = history[i]
            eng.writeln("  " & name & " = \"" & value & "\"")

      of CmdKind.cTstart:
        # TSTART — begin transaction (§11.1)
        eng.globals[].tstart()

      of CmdKind.cTcommit:
        # TCOMMIT — commit transaction (§11.2)
        eng.globals[].tcommit()

      of CmdKind.cTrollback:
        # TROLLBACK — rollback transaction (§11.3)
        eng.globals[].trollback()

      else:
        discard

    except:
      # Error handling: set $ECODE and execute $ETRAP if set
      let errorMsg = getCurrentExceptionMsg()
      let errorCode = "M9999:" & errorMsg
      eng.globals[].setSpecialVar("$ECODE", errorCode)

      # §11.4: implicit rollback on unhandled error inside transaction
      if eng.globals[].inTransaction():
        eng.globals[].trollback()

      # Check if $ETRAP is set
      let etrap = eng.globals[].getSpecialVar("$ETRAP")
      if etrap.len > 0:
        try:
          discard eng.execute(eng.cachedParseLine(etrap), depth + 1)
        except:
          eng.output.add("Error in $ETRAP: " & getCurrentExceptionMsg() & "\n")
      else:
        eng.output.add("Error: " & errorMsg & "\n")

      return "Error"

proc parseLine*(code: string): Line =
  ## Parse a line of M code (Line is ref object)
  var p = newParser(code)
  return p.parseLine()

proc cachedParseLine*(eng: var Engine, code: string): Line =
  ## Parse with cache lookup. Reuses AST for repeated identical source lines.
  if code in eng.runtime[].parseCache:
    return eng.runtime[].parseCache[code]
  let parsed = parseLine(code)
  eng.runtime[].parseCache[code] = parsed
  return parsed
