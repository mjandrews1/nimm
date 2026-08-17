# runtime.nim — nimm M/MUMPS runtime
# Provides routine loading, $TEXT support, and mode system

import os
import strutils
import tables

type
  Mode* = enum
    Strict,   # ANSI/MDC X11.1-1995 (ISO/IEC 11756:1999)
    RSM,      # RSM-compatible extensions
    nimm      # nimm extensions (data structures, network, $NI functions)

  ModeConfig* = object
    allowExtensions*: bool      # Allow nimm extensions ($NI_, NI commands)
    allowLowercase*: bool       # Allow lowercase identifiers
    maxIdentifierLen*: int      # Max identifier length (0 = unlimited)
    operatorPrecedence*: bool   # Use PEMDAS vs left-to-right

  Routine* = object
    name*: string
    lines*: seq[string]
    labels*: Table[string, int]  # label -> line index

  Runtime* = object
    routines*: Table[string, Routine]
    currentRoutine*: string
    currentLine*: int
    mode*: Mode
    config*: ModeConfig
    # Error handling
    ecode*: string          # $ECODE - error code
    etrap*: string          # $ETRAP - error trap expression
    zstatus*: string        # $ZSTATUS - error status
    zerror*: string         # $ZERROR - error message
    errorStack*: seq[string] # Error propagation stack
    # Tracing
    tracingEnabled*: bool   # ZTRACE on/off
    traceLog*: seq[string]  # Trace log entries
    traceMaxEntries*: int   # Max trace log size

proc getModeConfig*(mode: Mode): ModeConfig =
  ## Get configuration for a mode
  case mode
  of Strict:
    result.allowExtensions = false
    result.allowLowercase = false
    result.maxIdentifierLen = 8
    result.operatorPrecedence = false
  of RSM:
    result.allowExtensions = false
    result.allowLowercase = true
    result.maxIdentifierLen = 32
    result.operatorPrecedence = false
  of nimm:
    result.allowExtensions = true
    result.allowLowercase = true
    result.maxIdentifierLen = 0
    result.operatorPrecedence = true

proc newRuntime*(mode: Mode = nimm): Runtime =
  result.routines = initTable[string, Routine]()
  result.currentRoutine = ""
  result.currentLine = 0
  result.mode = mode
  result.config = getModeConfig(mode)
  result.ecode = ""
  result.etrap = ""
  result.zstatus = ""
  result.zerror = ""
  result.errorStack = @[]
  result.tracingEnabled = false
  result.traceLog = @[]
  result.traceMaxEntries = 10000

proc parseLabels(routine: var Routine) =
  ## Parse labels from routine lines
  for i, line in routine.lines:
    let trimmed = line.strip()
    if trimmed.len > 0 and not trimmed.startsWith(";"):
      # Check if line starts with a label (alphanumeric or %)
      if trimmed[0] in {'A'..'Z', 'a'..'z', '%'}:
        # Find end of label
        var labelEnd = 0
        while labelEnd < trimmed.len and trimmed[labelEnd] in {'A'..'Z', 'a'..'z', '0'..'9', '%'}:
          inc labelEnd
        if labelEnd > 0:
          let label = trimmed[0..<labelEnd].toUpperAscii()
          routine.labels[label] = i

proc loadRoutine*(rt: var Runtime, filepath: string): Routine =
  ## Load a routine from a file
  let name = extractFilename(filepath).splitFile().name.toUpperAscii()
  
  var routine = Routine(name: name)
  
  # Read lines
  let f = open(filepath)
  defer: f.close()
  
  var line: string
  while f.readLine(line):
    # Remove trailing whitespace
    routine.lines.add(line.strip(trailing = true))
  
  # Parse labels
  parseLabels(routine)
  
  rt.routines[name] = routine
  return routine

proc loadRoutineFromString*(rt: var Runtime, name: string, code: string): Routine =
  ## Load a routine from a string
  var routine = Routine(name: name.toUpperAscii())
  
  for line in code.splitLines():
    routine.lines.add(line.strip(trailing = true))
  
  parseLabels(routine)
  
  rt.routines[name] = routine
  return routine

proc getLine*(rt: Runtime, routineName: string, label: string, offset: int = 0): string =
  ## Get source line at label+offset in routine
  ## Implements $TEXT(label+offset^routine)
  let name = routineName.toUpperAscii()
  let lbl = label.toUpperAscii()
  
  if name notin rt.routines:
    return ""
  
  let routine = rt.routines[name]
  
  if lbl notin routine.labels:
    return ""
  
  let lineIdx = routine.labels[lbl] + offset
  
  if lineIdx < 0 or lineIdx >= routine.lines.len:
    return ""
  
  return routine.lines[lineIdx]

proc getLine*(rt: Runtime, spec: string): string =
  ## Parse $TEXT spec: label+offset^routine
  ## Returns the source line
  var label = ""
  var offset = 0
  var routineName = ""
  
  # Split by ^
  let caretPos = spec.find('^')
  if caretPos >= 0:
    routineName = spec[caretPos+1..^1]
    let beforeCaret = spec[0..<caretPos]
    
    # Split by +
    let plusPos = beforeCaret.find('+')
    if plusPos >= 0:
      label = beforeCaret[0..<plusPos]
      try:
        offset = parseInt(beforeCaret[plusPos+1..^1])
      except:
        offset = 0
    else:
      label = beforeCaret
  else:
    # No routine specified, use current
    label = spec
    routineName = rt.currentRoutine
  
  return rt.getLine(routineName, label, offset)

# --- Error handling ---

proc setError*(rt: var Runtime, code: string, message: string = "") =
  ## Set error state
  rt.ecode = code
  rt.zerror = message
  rt.zstatus = code & ":" & message
  rt.errorStack.add(rt.zstatus)

proc clearError*(rt: var Runtime) =
  ## Clear error state
  rt.ecode = ""
  rt.zstatus = ""
  rt.zerror = ""

proc hasError*(rt: Runtime): bool =
  ## Check if error state is set
  return rt.ecode.len > 0

proc getLastError*(rt: Runtime): string =
  ## Get last error from stack
  if rt.errorStack.len > 0:
    return rt.errorStack[^1]
  return ""

proc popError*(rt: var Runtime): string =
  ## Pop last error from stack
  if rt.errorStack.len > 0:
    result = rt.errorStack[^1]
    rt.errorStack.setLen(rt.errorStack.len - 1)
    if rt.errorStack.len > 0:
      rt.zstatus = rt.errorStack[^1]
    else:
      rt.zstatus = ""
  else:
    result = ""

proc setEtrap*(rt: var Runtime, expression: string) =
  ## Set error trap expression
  rt.etrap = expression

proc getEtrap*(rt: Runtime): string =
  ## Get error trap expression
  return rt.etrap

proc handle_error*(rt: var Runtime, code: string, message: string) =
  ## Handle an error: set state and invoke trap if set
  rt.setError(code, message)
  
  # If $ETRAP is set, we would invoke it here
  # For now, just log the error
  if rt.etrap.len > 0:
    # TODO: Execute etrap expression
    discard

proc reset*(rt: var Runtime) =
  ## Reset runtime state
  rt.clearError()
  rt.errorStack.setLen(0)
  rt.etrap = ""
  rt.currentRoutine = ""
  rt.currentLine = 0
  rt.tracingEnabled = false
  rt.traceLog.setLen(0)

# --- Execution tracing (ZTRACE) ---

proc enableTracing*(rt: var Runtime) =
  ## Enable execution tracing
  rt.tracingEnabled = true

proc disableTracing*(rt: var Runtime) =
  ## Disable execution tracing
  rt.tracingEnabled = false

proc isTracing*(rt: Runtime): bool =
  ## Check if tracing is enabled
  return rt.tracingEnabled

proc traceCommand*(rt: var Runtime, routine: string, line: int, command: string) =
  ## Log a command execution
  if not rt.tracingEnabled:
    return
  
  let entry = $line & ":" & routine & ":" & command
  rt.traceLog.add(entry)
  
  # Trim if too large
  if rt.traceLog.len > rt.traceMaxEntries:
    rt.traceLog.delete(0)

proc traceVariable*(rt: var Runtime, name: string, value: string) =
  ## Log a variable access
  if not rt.tracingEnabled:
    return
  
  let entry = "VAR:" & name & "=" & value
  rt.traceLog.add(entry)
  
  if rt.traceLog.len > rt.traceMaxEntries:
    rt.traceLog.delete(0)

proc traceFunction*(rt: var Runtime, name: string, args: string, result: string) =
  ## Log a function call
  if not rt.tracingEnabled:
    return
  
  let entry = "FUNC:" & name & "(" & args & ")=" & result
  rt.traceLog.add(entry)
  
  if rt.traceLog.len > rt.traceMaxEntries:
    rt.traceLog.delete(0)

proc getTraceLog*(rt: Runtime): seq[string] =
  ## Get trace log entries
  return rt.traceLog

proc clearTraceLog*(rt: var Runtime) =
  ## Clear trace log
  rt.traceLog.setLen(0)

proc traceLogLen*(rt: Runtime): int =
  ## Get trace log length
  return rt.traceLog.len
