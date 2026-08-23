# debugger.nim — Debugger infrastructure for nimm
# Implements ZBREAK, ZSTEP, ZCONTINUE

import strutils
import tables
import os

type
  Debugger* = ref object
    ## Debugger state
    breakpoints*: Table[string, seq[int]]  # routine -> [line numbers]
    stepMode*: string       # off, into, over, out
    stepping*: bool         # Currently stepping
    debugPrompt*: bool      # Show debug prompt
    lastCommand*: string    # Last debug command
    currentLine*: int       # Current source line (#326)
    currentCol*: int        # Current source column (#326)

proc newDebugger*(): Debugger =
  new(result)
  result.breakpoints = initTable[string, seq[int]]()
  result.stepMode = "off"
  result.stepping = false
  result.debugPrompt = false
  result.lastCommand = ""

proc setBreakpoint*(dbg: var Debugger, routine: string, line: int) =
  ## Set a breakpoint at a specific line
  if routine notin dbg.breakpoints:
    dbg.breakpoints[routine] = @[]
  if line notin dbg.breakpoints[routine]:
    dbg.breakpoints[routine].add(line)
    echo "Breakpoint set at ", routine, ":", line

proc removeBreakpoint*(dbg: var Debugger, routine: string, line: int) =
  ## Remove a breakpoint
  if routine in dbg.breakpoints:
    let idx = dbg.breakpoints[routine].find(line)
    if idx >= 0:
      dbg.breakpoints[routine].delete(idx)
      echo "Breakpoint removed at ", routine, ":", line

proc clearBreakpoints*(dbg: var Debugger, routine: string = "") =
  ## Clear all breakpoints
  if routine.len > 0:
    if routine in dbg.breakpoints:
      dbg.breakpoints.del(routine)
      echo "Breakpoints cleared for ", routine
  else:
    dbg.breakpoints.clear()
    echo "All breakpoints cleared"

proc listBreakpoints*(dbg: Debugger) =
  ## List all breakpoints
  if dbg.breakpoints.len == 0:
    echo "No breakpoints set"
    return
  echo "Breakpoints:"
  for routine, lines in dbg.breakpoints:
    for line in lines:
      echo "  ", routine, ":", line

proc shouldBreak*(dbg: Debugger, routine: string, line: int): bool =
  ## Check if we should break at this point
  if dbg.stepping:
    return true
  if routine in dbg.breakpoints:
    if line in dbg.breakpoints[routine]:
      return true
  return false

proc setStepMode*(dbg: var Debugger, mode: string) =
  ## Set step mode: off, into, over, out
  dbg.stepMode = mode
  if mode != "off":
    dbg.stepping = true
  else:
    dbg.stepping = false
  echo "Step mode: ", mode

proc continueExecution*(dbg: var Debugger) =
  ## Continue execution after breakpoint
  dbg.stepping = false
  dbg.debugPrompt = false
  echo "Continuing..."

proc debugPromptLoop*(dbg: var Debugger, evalProc: proc(cmd: string): string) =
  ## Interactive debug prompt
  dbg.debugPrompt = true
  echo ""
  echo "Debugger (type 'help' for commands)"
  
  while dbg.debugPrompt:
    stdout.write("dbg> ")
    stdout.flushFile()
    
    var line: string
    try:
      line = stdin.readLine()
    except EOFError:
      dbg.debugPrompt = false
      break
    except:
      continue
    
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    
    case trimmed.toLowerAscii
    of "help", "h":
      echo "Debugger commands:"
      echo "  continue, c  - Continue execution"
      echo "  step, s      - Step into"
      echo "  next, n      - Step over"
      echo "  print, p VAR - Print variable value"
      echo "  break, b LOC - Set breakpoint"
      echo "  delete, d LOC - Delete breakpoint"
      echo "  list, l      - List breakpoints"
      echo "  stack, k     - Show call stack"
      echo "  vars, v      - List local variables"
      echo "  source, src  - Show current source position"
      echo "  quit, q      - Quit debugger"
    of "continue", "c":
      dbg.continueExecution()
    of "step", "s":
      dbg.setStepMode("into")
      dbg.debugPrompt = false
    of "next", "n":
      dbg.setStepMode("over")
      dbg.debugPrompt = false
    of "quit", "q":
      dbg.debugPrompt = false
      dbg.stepping = false
    of "list", "l":
      dbg.listBreakpoints()
    of "stack", "k":
      # Show call stack — requires engine reference
      echo "Call stack: (use ZSTACK for detailed view)"
    of "vars", "v":
      # List local variables — requires engine reference
      echo "Variables: (use ZWRITE for detailed view)"
    of "source", "src":
      if dbg.currentLine > 0:
        echo "Line ", dbg.currentLine, ", Col ", dbg.currentCol
      else:
        echo "No source position available"
    else:
      if trimmed.startsWith("print ") or trimmed.startsWith("p "):
        let varName = if trimmed.startsWith("print "): trimmed[6..^1].strip() else: trimmed[2..^1].strip()
        let result = evalProc(varName)
        echo varName, " = ", result
      elif trimmed.startsWith("break ") or trimmed.startsWith("b "):
        let loc = if trimmed.startsWith("break "): trimmed[6..^1].strip() else: trimmed[2..^1].strip()
        echo "Breakpoint at: ", loc
      elif trimmed.startsWith("delete ") or trimmed.startsWith("d "):
        let loc = if trimmed.startsWith("delete "): trimmed[7..^1].strip() else: trimmed[2..^1].strip()
        echo "Delete breakpoint at: ", loc
      else:
        echo "Unknown command: ", trimmed
