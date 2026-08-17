# test_tracing.nim — Test execution tracing (ZTRACE)

import ../runtime
import strutils

proc main() =
  echo "Testing execution tracing..."
  
  var rt = newRuntime()
  
  # Test initial state
  assert rt.isTracing() == false
  assert rt.getTraceLog().len == 0
  echo "✓ Initial state clean"
  
  # Test enable/disable
  rt.enableTracing()
  assert rt.isTracing() == true
  rt.disableTracing()
  assert rt.isTracing() == false
  echo "✓ Enable/disable works"
  
  # Test tracing commands
  rt.enableTracing()
  rt.traceCommand("MAIN", 1, "SET X=1")
  rt.traceCommand("MAIN", 2, "WRITE X")
  rt.traceCommand("SUB", 1, "QUIT")
  assert rt.getTraceLog().len == 3
  echo "✓ traceCommand logs entries"
  
  # Test tracing variables
  rt.traceVariable("X", "42")
  rt.traceVariable("Y", "hello")
  assert rt.getTraceLog().len == 5
  echo "✓ traceVariable logs entries"
  
  # Test tracing functions
  rt.traceFunction("$LENGTH", "\"hello\"", "5")
  assert rt.getTraceLog().len == 6
  echo "✓ traceFunction logs entries"
  
  # Test log content
  let log = rt.getTraceLog()
  assert log[0] == "1:MAIN:SET X=1"
  assert log[3] == "VAR:X=42"
  assert log[5].startsWith("FUNC:")
  assert log[5].contains("LENGTH")
  echo "✓ Log content correct"
  
  # Test clearTraceLog
  rt.clearTraceLog()
  assert rt.getTraceLog().len == 0
  echo "✓ clearTraceLog works"
  
  # Test traceLogLen
  rt.enableTracing()
  for i in 0..100:
    rt.traceCommand("MAIN", i, "CMD " & $i)
  assert rt.traceLogLen() == 101
  echo "✓ traceLogLen works"
  
  # Test max entries limit
  rt.clearTraceLog()
  rt.traceMaxEntries = 50
  for i in 0..100:
    rt.traceCommand("MAIN", i, "CMD " & $i)
  assert rt.traceLogLen() == 50, "Expected 50, got " & $rt.traceLogLen()
  echo "✓ Max entries limit works"
  
  # Test reset clears tracing
  rt.enableTracing()
  rt.traceCommand("MAIN", 1, "TEST")
  rt.reset()
  assert rt.isTracing() == false
  assert rt.getTraceLog().len == 0
  echo "✓ reset clears tracing"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
