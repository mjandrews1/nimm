# inspector.nim — Inspector for nimm (ZINSPECT/ZSTACK/ZSTATS)
# Provides variable inspection, call stack display, and statistics

import tables
import strutils
import times

type
  VariableInfo* = object
    name*: string
    value*: string
    kind*: string       # "local", "global", "special"
    subscripts*: seq[string]
    dataFlags*: int     # $DATA result

  StackFrame* = object
    routine*: string
    label*: string
    line*: int
    variables*: seq[string]  # pre-formatted "name=value" local snapshots

  RuntimeStats* = object
    commandsExecuted*: int
    functionCalls*: int
    variableAccesses*: int
    startTime*: float
    elapsedTime*: float

  Inspector* = object
    variableHistory*: seq[(string, string, float)]  # (name, value, timestamp)
    maxHistory*: int
    stats*: RuntimeStats

proc newInspector*(): Inspector =
  result.variableHistory = @[]
  result.maxHistory = 10000
  result.stats = RuntimeStats(
    commandsExecuted: 0,
    functionCalls: 0,
    variableAccesses: 0,
    startTime: epochTime(),
    elapsedTime: 0
  )

# --- ZINSPECT: Variable inspection ---

proc inspectVariable*(name: string, value: string, kind: string = "local"): VariableInfo =
  ## Create variable info
  return VariableInfo(
    name: name,
    value: value,
    kind: kind,
    subscripts: @[],
    dataFlags: if value.len > 0: 1 else: 0
  )

proc inspectVariableWithSubs*(name: string, subs: seq[string], value: string, kind: string = "global"): VariableInfo =
  ## Create variable info with subscripts
  return VariableInfo(
    name: name,
    value: value,
    kind: kind,
    subscripts: subs,
    dataFlags: if value.len > 0: 1 else: 0
  )

proc formatVariable*(info: VariableInfo): string =
  ## Format variable info as string
  result = info.name
  if info.subscripts.len > 0:
    result.add("(")
    for i, sub in info.subscripts:
      if i > 0: result.add(",")
      result.add("\"" & sub & "\"")
    result.add(")")
  result.add("=")
  if info.value.len > 0:
    result.add("\"" & info.value & "\"")
  else:
    result.add("UNDEFINED")

proc recordVariableAccess*(insp: var Inspector, name: string, value: string) =
  ## Record variable access in history
  insp.variableHistory.add((name, value, epochTime()))
  if insp.variableHistory.len > insp.maxHistory:
    insp.variableHistory.delete(0)
  insp.stats.variableAccesses += 1

# --- ZSTACK: Call stack display ---

proc formatStackFrame*(frame: StackFrame): string =
  ## Format stack frame as string
  result = frame.routine & ":" & frame.label
  if frame.line > 0:
    result.add("+" & $frame.line)

proc formatStack*(frames: seq[StackFrame]): string =
  ## Format entire call stack, including per-frame locals
  result = "Call Stack:\n"
  for i, frame in frames:
    result.add("  " & $i & ": " & formatStackFrame(frame) & "\n")
    if frame.variables.len > 0:
      result.add("    " & frame.variables.join(", ") & "\n")

# --- ZSTATS: Statistics ---

proc updateStats*(insp: var Inspector) =
  ## Update elapsed time
  insp.stats.elapsedTime = epochTime() - insp.stats.startTime

proc formatStats*(insp: var Inspector): string =
  ## Format statistics as string
  insp.updateStats()
  result = "Runtime Statistics:\n"
  result.add("  Commands executed: " & $insp.stats.commandsExecuted & "\n")
  result.add("  Function calls: " & $insp.stats.functionCalls & "\n")
  result.add("  Variable accesses: " & $insp.stats.variableAccesses & "\n")
  result.add("  Elapsed time: " & $(insp.stats.elapsedTime * 1000).int & "ms\n")

proc recordCommand*(insp: var Inspector) =
  ## Record command execution
  insp.stats.commandsExecuted += 1

proc recordFunctionCall*(insp: var Inspector) =
  ## Record function call
  insp.stats.functionCalls += 1

proc getVariableHistory*(insp: Inspector): seq[(string, string, float)] =
  ## Get variable access history
  return insp.variableHistory

proc clearHistory*(insp: var Inspector) =
  ## Clear variable history
  insp.variableHistory.setLen(0)

proc resetStats*(insp: var Inspector) =
  ## Reset statistics
  insp.stats = RuntimeStats(
    commandsExecuted: 0,
    functionCalls: 0,
    variableAccesses: 0,
    startTime: epochTime(),
    elapsedTime: 0
  )
