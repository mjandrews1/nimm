# test_debugging.nim — Test debugging (ZBREAK/ZSTEP/REPL)

import ../runtime
import tables

proc main() =
  echo "Testing debugging..."
  
  var rt = newRuntime()
  
  # Test initial state
  assert rt.breakpointCount() == 0
  assert rt.getStepMode() == "off"
  assert rt.isStepping() == false
  assert rt.getDebugOutput().len == 0
  echo "✓ Initial state clean"
  
  # Test breakpoints
  rt.addBreakpoint("MAIN", 10)
  rt.addBreakpoint("MAIN", 20)
  rt.addBreakpoint("SUB", 5)
  assert rt.breakpointCount() == 3
  assert rt.hasBreakpoint("MAIN", 10) == true
  assert rt.hasBreakpoint("MAIN", 15) == false
  assert rt.hasBreakpoint("SUB", 5) == true
  echo "✓ Breakpoints added"
  
  # Test remove breakpoint
  rt.removeBreakpoint("MAIN", 10)
  assert rt.breakpointCount() == 2
  assert rt.hasBreakpoint("MAIN", 10) == false
  assert rt.hasBreakpoint("MAIN", 20) == true
  echo "✓ Breakpoint removed"
  
  # Test clear breakpoints
  rt.clearBreakpoints()
  assert rt.breakpointCount() == 0
  echo "✓ Clear breakpoints"
  
  # Test getBreakpoints
  rt.addBreakpoint("MAIN", 10)
  rt.addBreakpoint("MAIN", 20)
  let bps = rt.getBreakpoints()
  assert bps.hasKey("MAIN")
  assert bps["MAIN"].len == 2
  echo "✓ getBreakpoints works"
  
  # Test step modes
  rt.setStepMode("into")
  assert rt.getStepMode() == "into"
  assert rt.isStepping() == true
  
  rt.setStepMode("over")
  assert rt.getStepMode() == "over"
  
  rt.setStepMode("off")
  assert rt.isStepping() == false
  echo "✓ Step modes work"
  
  # Test shouldBreak
  rt.clearBreakpoints()
  rt.addBreakpoint("MAIN", 10)
  assert rt.shouldBreak("MAIN", 10) == true
  assert rt.shouldBreak("MAIN", 15) == false
  
  rt.setStepMode("into")
  assert rt.shouldBreak("MAIN", 15) == true  # stepping
  rt.setStepMode("off")
  echo "✓ shouldBreak works"
  
  # Test debug output
  rt.addDebugOutput("Breakpoint hit at MAIN:10")
  rt.addDebugOutput("X = 42")
  assert rt.getDebugOutput().len == 2
  rt.clearDebugOutput()
  assert rt.getDebugOutput().len == 0
  echo "✓ Debug output works"
  
  # Test case insensitivity
  rt.addBreakpoint("main", 5)
  assert rt.hasBreakpoint("MAIN", 5) == true
  assert rt.hasBreakpoint("main", 5) == true
  echo "✓ Case insensitive breakpoints"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
