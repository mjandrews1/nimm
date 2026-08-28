# test_mode.nim — Test mode system (Strict/RSM/nimm)

import ../runtime
import os

proc main() =
  echo "Testing mode system..."
  
  # Test Strict mode
  var rtStrict = newRuntime(Strict)
  assert rtStrict.mode == Strict
  assert rtStrict.config.allowExtensions == false
  assert rtStrict.config.allowLowercase == false
  echo "✓ Strict mode configured"
  
  # Test RSM mode
  var rtRSM = newRuntime(RSM)
  assert rtRSM.mode == RSM
  assert rtRSM.config.allowExtensions == false
  assert rtRSM.config.allowLowercase == true
  echo "✓ RSM mode configured"
  
  # Test nimm mode
  var rtNimm = newRuntime(nimm)
  assert rtNimm.mode == nimm
  assert rtNimm.config.allowExtensions == true
  assert rtNimm.config.allowLowercase == true
  echo "✓ nimm mode configured"
  
  # Test default mode (should be nimm)
  var rtDefault = newRuntime()
  assert rtDefault.mode == nimm
  echo "✓ Default mode is nimm"
  
  # Test mode affects routine loading
  let testFile = "/tmp/test_mode.m"
  let f = open(testFile, fmWrite)
  f.writeLine("TEST")
  f.writeLine(" WRITE \"Hello\"")
  f.writeLine(" QUIT")
  f.close()
  
  let routine = rtNimm.loadRoutine(testFile)
  assert routine.name == "TEST_MODE", "Expected 'TEST_MODE', got '" & routine.name & "'"
  assert routine.lines.len == 3
  echo "✓ Routine loading works in nimm mode"
  
  # Cleanup
  removeFile(testFile)
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
