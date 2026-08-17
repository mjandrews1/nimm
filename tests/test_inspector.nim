# test_inspector.nim — Test inspector (ZINSPECT/ZSTACK/ZSTATS)

import ../inspector

proc main() =
  echo "Testing inspector..."
  
  var insp = newInspector()
  
  # Test ZINSPECT - variable inspection
  let info1 = inspectVariable("X", "42")
  assert info1.name == "X"
  assert info1.value == "42"
  assert info1.kind == "local"
  assert info1.dataFlags == 1
  echo "✓ inspectVariable"
  
  let formatted = formatVariable(info1)
  assert formatted == "X=\"42\""
  echo "✓ formatVariable"
  
  # Test variable with subscripts
  let info2 = inspectVariableWithSubs("GLOBAL", @["sub1", "sub2"], "value")
  assert info2.kind == "global"
  assert info2.subscripts.len == 2
  echo "✓ inspectVariableWithSubs"
  
  # Test undefined variable
  let info3 = inspectVariable("Y", "")
  assert info3.dataFlags == 0
  let formatted3 = formatVariable(info3)
  echo "✓ Undefined variable: " & formatted3
  
  # Test recordVariableAccess
  insp.recordVariableAccess("X", "42")
  insp.recordVariableAccess("Y", "hello")
  assert insp.variableHistory.len == 2
  echo "✓ recordVariableAccess"
  
  # Test getVariableHistory
  let history = insp.getVariableHistory()
  assert history.len == 2
  echo "✓ getVariableHistory"
  
  # Test clearHistory
  insp.clearHistory()
  assert insp.variableHistory.len == 0
  echo "✓ clearHistory"
  
  # Test ZSTACK - call stack
  var frames: seq[StackFrame] = @[]
  frames.add(StackFrame(routine: "MAIN", label: "START", line: 1))
  frames.add(StackFrame(routine: "MAIN", label: "SUB", line: 5))
  frames.add(StackFrame(routine: "UTIL", label: "FUNC", line: 10))
  let stackStr = formatStack(frames)
  echo "✓ formatStack"
  
  # Test formatStackFrame
  let frame = StackFrame(routine: "MAIN", label: "TEST", line: 42)
  assert formatStackFrame(frame) == "MAIN:TEST+42"
  echo "✓ formatStackFrame"
  
  # Test ZSTATS - statistics
  insp.recordCommand()
  insp.recordCommand()
  insp.recordFunctionCall()
  assert insp.stats.commandsExecuted == 2
  assert insp.stats.functionCalls == 1
  echo "✓ Stats recording"
  
  let statsStr = formatStats(insp)
  echo "✓ formatStats"
  
  # Test resetStats
  insp.resetStats()
  assert insp.stats.commandsExecuted == 0
  assert insp.stats.functionCalls == 0
  echo "✓ resetStats"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
