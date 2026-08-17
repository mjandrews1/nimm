# test_text.nim — Test $TEXT implementation

import ../runtime
import os
import tables

proc main() =
  echo "Testing $TEXT implementation..."
  
  # Create a test routine file
  let testFile = "/tmp/test_routine.m"
  let f = open(testFile, fmWrite)
  f.writeLine("MAIN")
  f.writeLine(" WRITE \"Hello\"")
  f.writeLine(" QUIT")
  f.writeLine("SUB")
  f.writeLine(" WRITE \"World\"")
  f.writeLine(" QUIT")
  f.writeLine("OTHER")
  f.writeLine(" SET X=1")
  f.writeLine(" SET Y=2")
  f.writeLine(" WRITE X+Y")
  f.writeLine(" QUIT")
  f.close()
  
  var rt = newRuntime()
  let routine = rt.loadRoutine(testFile)
  
  echo "✓ Loaded routine: " & routine.name
  echo "  Lines: " & $routine.lines.len
  echo "  Labels: " & $len(routine.labels)
  
  # Test $TEXT
  let line1 = rt.getLine("TEST_ROUTINE", "MAIN", 0)
  assert line1 == "MAIN", "Expected 'MAIN', got '" & line1 & "'"
  echo "✓ $TEXT(MAIN) = '" & line1 & "'"
  
  let line2 = rt.getLine("TEST_ROUTINE", "MAIN", 1)
  assert line2 == "WRITE \"Hello\"", "Expected 'WRITE \"Hello\"', got '" & line2 & "'"
  echo "✓ $TEXT(MAIN+1) = '" & line2 & "'"
  
  let line3 = rt.getLine("TEST_ROUTINE", "SUB", 0)
  assert line3 == "SUB", "Expected 'SUB', got '" & line3 & "'"
  echo "✓ $TEXT(SUB) = '" & line3 & "'"
  
  let line4 = rt.getLine("TEST_ROUTINE", "SUB", 1)
  assert line4 == "WRITE \"World\"", "Expected 'WRITE \"World\"', got '" & line4 & "'"
  echo "✓ $TEXT(SUB+1) = '" & line4 & "'"
  
  # Test with routine spec
  let spec1 = rt.getLine("SUB^TEST_ROUTINE")
  assert spec1 == "SUB", "Expected 'SUB', got '" & spec1 & "'"
  echo "✓ $TEXT(SUB^TEST_ROUTINE) = '" & spec1 & "'"
  
  let spec2 = rt.getLine("SUB+1^TEST_ROUTINE")
  assert spec2 == "WRITE \"World\"", "Expected 'WRITE \"World\"', got '" & spec2 & "'"
  echo "✓ $TEXT(SUB+1^TEST_ROUTINE) = '" & spec2 & "'"
  
  # Test edge cases
  let empty = rt.getLine("NONEXISTENT", "MAIN", 0)
  assert empty == "", "Expected empty for nonexistent routine"
  echo "✓ $TEXT(NONEXISTENT:MAIN) = '' (empty)"
  
  let outOfRange = rt.getLine("MAIN", "MAIN", 100)
  assert outOfRange == "", "Expected empty for out of range"
  echo "✓ $TEXT(MAIN+100) = '' (out of range)"
  
  # Cleanup
  removeFile(testFile)
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
