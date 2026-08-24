# runtime.nim — nimm M/MUMPS runtime
# Provides routine loading, $TEXT support, and mode system

import os
import strutils
import tables
import ast
import parser
import bytecode

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
    filePath*: string            # Source file path (#304)
    bytecodeCache*: seq[Bytecode] # Compiled bytecode per line (nil = not compiled) (#342)
    bytecodeReady*: bool          # True when all lines compiled (#342)

  Runtime* = object
    routines*: Table[string, Routine]
    currentRoutine*: string
    currentFile*: string
    currentLine*: int
    mode*: Mode
    config*: ModeConfig
    # Error handling
    ecode*: string          # $ECODE - error code
    etrap*: string          # $ETRAP - error trap expression
    etrapStack*: seq[string] # Error trap stack for NEW/QUIT scoping
    zstatus*: string        # $ZSTATUS - error status
    zerror*: string         # $ZERROR - error message
    errorStack*: seq[string] # Error propagation stack
    # Tracing
    tracingEnabled*: bool   # ZTRACE on/off
    traceLog*: seq[string]  # Trace log entries
    traceMaxEntries*: int   # Max trace log size
    # Debugging
    breakpoints*: Table[string, seq[int]]  # routine -> [line numbers]
    stepMode*: string       # ZSTEP mode: off, into, over, out
    stepping*: bool         # Currently stepping
    debugOutput*: seq[string] # Debug output buffer
    # Parser cache: source line -> parsed AST
    parseCache*: Table[string, Line]

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
  result.etrapStack = @[]
  result.zstatus = ""
  result.zerror = ""
  result.errorStack = @[]
  result.tracingEnabled = false
  result.traceLog = @[]
  result.traceMaxEntries = 10000
  result.breakpoints = initTable[string, seq[int]]()
  result.stepMode = "off"
  result.stepping = false
  result.debugOutput = @[]

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

proc stripLabel*(line: string): string =
  ## Strip a leading entry label from a stored routine line for execution
  ## (§7.1). Stored lines keep their label verbatim so $TEXT stays exact;
  ## feeding the label token to the command parser instead makes a labeled
  ## block opener parse as an empty line, so the whole block never runs (#283).
  ##
  ## A leading token counts as a label only if it matches label syntax
  ## (letter/%-led identifier, or unsigned integer), terminates at
  ## whitespace or end-of-line, and is NOT itself a command keyword —
  ## "SET X=1" keeps its command; "LOOP FOR I=1:1:3 DO" drops "LOOP".
  ## (Labels that spell a reserved command word are unrepresentable here,
  ## matching standard practice.)
  var i = 0
  while i < line.len and line[i] in {' ', '\t'}: inc i
  if i >= line.len: return line
  var tok = ""
  if line[i] in {'A'..'Z', 'a'..'z', '%'}:
    while i < line.len and line[i] in {'A'..'Z', 'a'..'z', '0'..'9', '%'}:
      tok.add(line[i]); inc i
  elif line[i] in {'0'..'9'}:
    # Numeric entry label (§7.1)
    while i < line.len and line[i] in {'0'..'9'}:
      tok.add(line[i]); inc i
  else:
    return line
  if tok.len == 0: return line
  # A label must end at whitespace or EOL — "X(1)=..." is not one
  if i < line.len and line[i] notin {' ', '\t'}: return line
  if isCommandKeyword(tok): return line
  while i < line.len and line[i] in {' ', '\t'}: inc i
  return line[i..^1]

proc stripMComment(line: string): string =
  ## Strip M-style comments from a line.
  ## In M, `;` starts a comment to end of line, but NOT inside string literals.
  result = ""
  var inString = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '"':
      inString = not inString
      result.add(c)
    elif c == ';' and not inString:
      break
    else:
      result.add(c)
    inc i

proc filterRoutineLines(lines: var seq[string]) =
  ## Strip comments and blank lines from routine source.
  ## Must be called after mergeDotContinuations and before parseLabels.
  var filtered: seq[string] = @[]
  for line in lines:
    let stripped = stripMComment(line).strip()
    if stripped.len > 0:
      filtered.add(stripped)
  lines = filtered

proc isBlockOpener(content: string): bool =
  ## True when a (dot-stripped, comment-stripped) line opens an implicit
  ## block that source-line boundaries must close: IF/ELSE/FOR always scope
  ## to end-of-line or dot-block; DO only when bare (#282).
  var i = 0
  while i < content.len and content[i] in {' ', '\t'}: inc i
  var w = ""
  while i < content.len and content[i] in {'a'..'z', 'A'..'Z'}:
    w.add(content[i]); inc i
  case w.toUpperAscii
  of "IF", "I", "ELSE", "E", "FOR", "F":
    result = true
  of "DO", "D":
    # Bare DO opens a block; DO label^routine / DO entry:(args) do not.
    # Skip postconditional chain (":expr" — exprs contain no spaces except
    # inside quotes), then the opener is bare iff nothing remains.
    while i < content.len and content[i] in {' ', '\t'}: inc i
    var inStr = false
    while i < content.len and content[i] == ':':
      inc i
      while i < content.len:
        let c = content[i]
        if c == '"': inStr = not inStr
        elif not inStr and c == ' ': break
        inc i
      while i < content.len and content[i] in {' ', '\t'}: inc i
    result = i >= content.len
  else:
    result = false

proc firstCommandWord(content: string): string =
  ## First whitespace-delimited word, uppercased ("" if none).
  var i = 0
  while i < content.len and content[i] in {' ', '\t'}: inc i
  while i < content.len and content[i] != ' ' and content[i] != '\t':
    result.add(content[i]); inc i
  result = result.toUpperAscii

proc trailingBareDo(content: string): bool =
  ## True when the line's final token is a bare DO/D (optionally carrying a
  ## leading postcondition like "DO:X>5"), making any dot-children an
  ## inline-DO body that captures one extra parser frame (#282).
  var i = content.len
  while i > 0 and content[i-1] in {' ', '\t'}: dec i
  if i == 0: return false
  var j = i
  while j > 0 and content[j-1] notin {' ', '\t'}: dec j
  let tok = content[j..i-1].toUpperAscii
  if tok == "DO" or tok == "D":
    return true
  # Postcondition attached to a trailing bare DO (e.g. "DO:X>5").
  if tok.startsWith("DO:") or tok.startsWith("D:"):
    return true
  return false

proc appendLineWithMarkers(outp: var string, content, childBlob: string) =
  ## Append one logical line (its own text + merged children) to outp,
  ## inserting one blockSep per parser frame the line opens (#282).
  if outp.len > 0: outp.add(" ")
  outp.add(content)
  if childBlob.len > 0:
    outp.add(" ")
    outp.add(childBlob)
  let fw = firstCommandWord(content)
  let isOpen = fw in ["IF", "I", "ELSE", "E", "FOR", "F"]
  if isOpen:
    outp.add(" " & blockSep)
  if trailingBareDo(content) and childBlob.len > 0:
    outp.add(" " & blockSep)
  elif not isOpen and fw in ["DO", "D"] and childBlob.len > 0:
    outp.add(" " & blockSep)

proc mergeGroup(lines: seq[string], startIdx: int, depth: int, outp: var string): int =
  ## Render all sibling lines at `depth` (and their nested children) into
  ## outp, inserting blockSep markers so each parsed body closes exactly at
  ## its source-line boundary (#282). Returns the next unconsumed index.
  ##
  ## Marker rules, mirroring parser frame semantics:
  ##   - A line starting with IF/ELSE/FOR opens one body frame -> one marker
  ##     after its full logical extent (own text + merged children).
  ##   - A line ending in bare DO whose children exist opens the inline-DO
  ##     frame -> one more marker.
  ##   - Plain lines add no markers; deeper orphans are absorbed recursively.
  var i = startIdx
  while i < lines.len:
    let raw = lines[i].strip()
    var d = 0
    while d < raw.len and raw[d] == '.': inc d
    if d < depth: break
    if d > depth:
      # Malformed jump past the expected child depth — absorb recursively.
      i = mergeGroup(lines, i, d, outp)
      continue
    let content = stripMComment(raw[d..^1]).strip()
    i.inc
    if content.len == 0: continue
    var childBlob = ""
    i = mergeGroup(lines, i, depth + 1, childBlob)
    appendLineWithMarkers(outp, content, childBlob)
  return i

proc mergeDotContinuations(lines: var seq[string]) =
  ## Merge dot-continuation lines into parent lines, preserving block
  ## structure with parser.blockSep markers (#282).
  ##
  ## The old plain space-join let a mid-block IF/FOR swallow its trailing
  ## siblings as part of its own rest-of-line body. Now each logical group
  ## (a top-level line plus its dotted descendants) is rendered by
  ## mergeGroup, which inserts one blockSep per opened parser frame so body
  ## scopes end where their source lines did. Callers MUST run
  ## filterRoutineLines BEFORE this proc.
  var merged: seq[string] = @[]
  var i = 0
  while i < lines.len:
    let raw = lines[i].strip()
    var d = 0
    while d < raw.len and raw[d] == '.': inc d
    if d > 0:
      # Dots with no preceding top-level line: absorb into a synthetic group.
      var buf = ""
      i = mergeGroup(lines, i, d, buf)
      if buf.len > 0: merged.add(buf)
      continue
    let content = stripMComment(raw).strip()
    i.inc
    if content.len == 0: continue
    var childBlob = ""
    i = mergeGroup(lines, i, 1, childBlob)
    var buf = ""
    appendLineWithMarkers(buf, content, childBlob)
    merged.add(buf)
  lines = merged

proc loadRoutine*(rt: var Runtime, filepath: string): Routine =
  ## Load a routine from a file
  let name = extractFilename(filepath).splitFile().name.toUpperAscii()
  
  var routine = Routine(name: name, filePath: filepath)
  
  # Read lines
  let f = open(filepath)
  defer: f.close()
  
  var line: string
  while f.readLine(line):
    # Remove trailing whitespace
    routine.lines.add(line.strip(trailing = true))
  
  # Strip comments and blank lines FIRST — mergeDotContinuations needs
  # clean source lines so comment text can't swallow blockSep markers
  # and blank lines can't break depth tracking (#282)
  filterRoutineLines(routine.lines)

  # Merge dot-continuation lines
  mergeDotContinuations(routine.lines)

  # Parse labels
  parseLabels(routine)
  
  rt.routines[name] = routine
  return routine

proc loadRoutineFromString*(rt: var Runtime, name: string, code: string): Routine =
  ## Load a routine from a string
  var routine = Routine(name: name.toUpperAscii())
  
  for line in code.splitLines():
    routine.lines.add(line.strip(trailing = true))
  
  # Same ordering as loadRoutine: filter, then merge (#282)
  filterRoutineLines(routine.lines)
  mergeDotContinuations(routine.lines)
  
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

proc collectDotBody*(rt: Runtime, routineName: string, label: string, startOffset: int): tuple[body: string, linesConsumed: int] =
  ## Collect dot-continuation lines after a bare DO/FOR/IF
  ## Returns the concatenated body (dots stripped) and how many lines were consumed
  let name = routineName.toUpperAscii()
  let lbl = label.toUpperAscii()
  result.body = ""
  result.linesConsumed = 0
  
  if name notin rt.routines:
    return
  
  let routine = rt.routines[name]
  
  if lbl notin routine.labels:
    return
  
  var offset = startOffset
  while true:
    let lineIdx = routine.labels[lbl] + offset
    if lineIdx < 0 or lineIdx >= routine.lines.len:
      break
    
    let srcLine = routine.lines[lineIdx]
    let trimmed = srcLine.strip()
    
    if trimmed.len == 0 or trimmed[0] != '.':
      break
    
    # Strip the dot prefix and any leading whitespace
    let bodyLine = trimmed[1..^1].strip()
    if result.body.len > 0:
      result.body.add(" ")
    result.body.add(bodyLine)
    
    offset.inc
    result.linesConsumed.inc

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

proc pushEtrap*(rt: var Runtime) =
  ## Push current $ETRAP onto stack (called on NEW)
  rt.etrapStack.add(rt.etrap)

proc popEtrap*(rt: var Runtime) =
  ## Pop $ETRAP from stack (called on QUIT)
  if rt.etrapStack.len > 0:
    rt.etrap = rt.etrapStack[^1]
    rt.etrapStack.setLen(rt.etrapStack.len - 1)
  else:
    rt.etrap = ""

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
  ## Note: $ETRAP execution is handled by the engine's error handler
  rt.setError(code, message)

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

# --- Debugging (ZBREAK/ZSTEP) ---

proc addBreakpoint*(rt: var Runtime, routine: string, line: int) =
  ## Add a breakpoint
  let r = routine.toUpperAscii()
  if r notin rt.breakpoints:
    rt.breakpoints[r] = @[]
  if line notin rt.breakpoints[r]:
    rt.breakpoints[r].add(line)

proc removeBreakpoint*(rt: var Runtime, routine: string, line: int) =
  ## Remove a breakpoint
  let r = routine.toUpperAscii()
  if r in rt.breakpoints:
    var newLines: seq[int] = @[]
    for l in rt.breakpoints[r]:
      if l != line:
        newLines.add(l)
    rt.breakpoints[r] = newLines
    if rt.breakpoints[r].len == 0:
      rt.breakpoints.del(r)

proc clearBreakpoints*(rt: var Runtime) =
  ## Remove all breakpoints
  rt.breakpoints.clear()

proc hasBreakpoint*(rt: Runtime, routine: string, line: int): bool =
  ## Check if there's a breakpoint at routine:line
  let r = routine.toUpperAscii()
  if r in rt.breakpoints:
    for l in rt.breakpoints[r]:
      if l == line:
        return true
  return false

proc getBreakpoints*(rt: Runtime): Table[string, seq[int]] =
  ## Get all breakpoints
  return rt.breakpoints

proc breakpointCount*(rt: Runtime): int =
  ## Get total number of breakpoints
  result = 0
  for lines in rt.breakpoints.values:
    result += lines.len

proc setStepMode*(rt: var Runtime, mode: string) =
  ## Set step mode: off, into, over, out
  rt.stepMode = mode.toLowerAscii()
  rt.stepping = (rt.stepMode != "off")

proc getStepMode*(rt: Runtime): string =
  ## Get current step mode
  return rt.stepMode

proc isStepping*(rt: Runtime): bool =
  ## Check if currently stepping
  return rt.stepping

proc shouldBreak*(rt: Runtime, routine: string, line: int): bool =
  ## Check if execution should break at this point
  if rt.hasBreakpoint(routine, line):
    return true
  if rt.stepping:
    return true
  return false

proc addDebugOutput*(rt: var Runtime, msg: string) =
  ## Add debug output
  rt.debugOutput.add(msg)

proc getDebugOutput*(rt: Runtime): seq[string] =
  ## Get debug output
  return rt.debugOutput

proc clearDebugOutput*(rt: var Runtime) =
  ## Clear debug output
  rt.debugOutput.setLen(0)
