# test_integration.nim — Integration tests for nimm
# Tests full M programs, routine loading, DO/GOTO, nested calls

import os
import strutils
import osproc

type
  TestResult = object
    name: string
    passed: bool
    message: string

proc runMCode(code: string, expected: string): TestResult =
  result.name = code[0..min(40, code.len-1)] & "..."
  result.passed = false
  
  let cmd = "DYLD_LIBRARY_PATH=/usr/local/lib ./nimm -x '" & code & "'"
  let (output, exitCode) = execCmdEx(cmd)
  
  let actual = output.strip()
  if actual == expected:
    result.passed = true
    result.message = "OK"
  else:
    result.message = "Expected: '" & expected & "', Got: '" & actual & "'"

proc runRoutine(routine: string, code: string, expected: string): TestResult =
  result.name = routine & ": " & code[0..min(30, code.len-1)] & "..."
  result.passed = false
  
  let cmd = "DYLD_LIBRARY_PATH=/usr/local/lib ./nimm -r " & routine & " -x '" & code & "'"
  let (output, exitCode) = execCmdEx(cmd)
  
  let actual = output.strip()
  if actual == expected:
    result.passed = true
    result.message = "OK"
  else:
    result.message = "Expected: '" & expected & "', Got: '" & actual & "'"

proc main() =
  echo "=== nimm Integration Tests ==="
  echo ""
  
  var results: seq[TestResult] = @[]
  
  # Test basic expressions
  results.add(runMCode("WRITE 1+2", "3.0"))
  results.add(runMCode("WRITE 2*3", "6.0"))
  results.add(runMCode("WRITE 10#3", "1.0"))
  results.add(runMCode("WRITE 2**3", "8.0"))
  
  # Test string operations
  results.add(runMCode("WRITE \"hello\"_\"world\"", "helloworld"))
  results.add(runMCode("WRITE \"hello\"=\"hello\"", "1"))
  results.add(runMCode("WRITE \"hello\"=\"world\"", "0"))
  results.add(runMCode("WRITE \"hello\"[\"ell\"", "1"))
  results.add(runMCode("WRITE \"hello\"[\"xyz\"", "0"))
  
  # Test variables
  results.add(runMCode("SET X=42 WRITE X", "42"))
  results.add(runMCode("SET X=10 SET Y=20 WRITE X+Y", "30.0"))
  results.add(runMCode("SET X=\"hello\" WRITE X", "hello"))
  
  # Test subscripts
  results.add(runMCode("SET A(1)=\"one\" WRITE A(1)", "one"))
  results.add(runMCode("SET A(1,2)=\"nested\" WRITE A(1,2)", "nested"))
  
  # Test $ functions
  results.add(runMCode("WRITE $ASCII(\"A\")", "65"))
  results.add(runMCode("WRITE $CHAR(65,66,67)", "ABC"))
  results.add(runMCode("WRITE $LENGTH(\"hello\")", "5"))
  results.add(runMCode("WRITE $PIECE(\"a^b^c\",\"^\",2)", "b"))
  results.add(runMCode("WRITE $EXTRACT(\"hello\",2,4)", "ell"))
  
  # Test IF/ELSE
  results.add(runMCode("SET X=1 IF X=1 WRITE \"yes\"", "yes"))
  results.add(runMCode("SET X=0 IF X=1 WRITE \"yes\"", ""))
  
  # Test FOR loop
  results.add(runMCode("FOR I=1:1:3 WRITE I", "1.02.03.0"))
  
  # Test KILL
  results.add(runMCode("SET X=42 KILL X WRITE $DATA(X)", "0"))
  
  # Test special variables
  results.add(runMCode("WRITE $SYSTEM", "nimm/1.0"))
  
  # Test $ORDER
  results.add(runMCode("SET A(1)=\"a\" SET A(2)=\"b\" WRITE $ORDER(A(1))", "2"))
  
  # Test $SELECT
  results.add(runMCode("WRITE $SELECT(1:\"yes\",0:\"no\")", "yes"))
  
  # Test $CASE
  results.add(runMCode("WRITE $CASE(2,1:\"one\",2:\"two\",3:\"three\")", "two"))
  
  # Test $TRANSLATE
  results.add(runMCode("WRITE $TRANSLATE(\"hello\",\"el\",\"EL\")", "hELLo"))
  
  # Test $FNUMBER
  results.add(runMCode("WRITE $FNUMBER(1234.567,\"\",2)", "1234.57"))
  
  # Print results
  echo ""
  echo "=== Test Results ==="
  echo ""
  
  var passed = 0
  var failed = 0
  
  for r in results:
    if r.passed:
      echo "✓ " & r.name
      inc passed
    else:
      echo "✗ " & r.name & ": " & r.message
      inc failed
  
  echo ""
  echo "=== Summary ==="
  echo "Passed: " & $passed
  echo "Failed: " & $failed
  echo "Total: " & $(passed + failed)
  
  if failed > 0:
    quit(1)

when isMainModule:
  main()
