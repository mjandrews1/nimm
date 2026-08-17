# runtime.nim — nimm M/MUMPS runtime
# Provides routine loading and $TEXT support

import os
import strutils
import tables

type
  Routine* = object
    name*: string
    lines*: seq[string]
    labels*: Table[string, int]  # label -> line index

  Runtime* = object
    routines*: Table[string, Routine]
    currentRoutine*: string
    currentLine*: int

proc newRuntime*(): Runtime =
  result.routines = initTable[string, Routine]()
  result.currentRoutine = ""
  result.currentLine = 0

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
