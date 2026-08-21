# test_conformance.nim — Conformance tests for nimm
# Tests against ANSI/ISO M standard
# These are the CORRECT expected values per the standard
# Failing tests indicate bugs in nimm, not test issues

import os
import strutils
import osproc

type
  TestResult = object
    name: string
    passed: bool
    message: string
    category: string

proc runMCode(code: string, expected: string, category: string = ""): TestResult =
  result.name = code[0..min(50, code.len-1)] & "..."
  result.passed = false
  result.category = category
  
  putEnv("DYLD_LIBRARY_PATH", "/usr/local/lib")
  let output = execProcess("./nimm", args = @["-x", code], options = {poStdErrToStdOut})
  
  # Only strip trailing newline, not spaces
  var actual = output
  while actual.len > 0 and actual[^1] == '\n':
    actual = actual[0..^2]
  
  if actual == expected:
    result.passed = true
    result.message = "OK"
  else:
    result.message = "Expected: '" & expected & "', Got: '" & actual & "'"

proc main() =
  echo "=== nimm Conformance Tests ==="
  echo "Tests against ANSI/ISO M standard"
  echo "Failing tests indicate BUGS in nimm, not test issues"
  echo ""
  
  var results: seq[TestResult] = @[]
  
  # ==========================================
  # 1. Arithmetic Operations (per RFC: left-to-right, integer results)
  # ==========================================
  results.add(runMCode("WRITE 1+2", "3", "Arithmetic"))
  results.add(runMCode("WRITE 5-3", "2", "Arithmetic"))
  results.add(runMCode("WRITE 2*3", "6", "Arithmetic"))
  results.add(runMCode("WRITE 10/2", "5", "Arithmetic"))
  results.add(runMCode("WRITE 10#3", "1", "Arithmetic"))
  results.add(runMCode("WRITE 2**3", "8", "Arithmetic"))
  results.add(runMCode("WRITE -5", "-5", "Arithmetic"))
  results.add(runMCode("WRITE +5", "5", "Arithmetic"))
  results.add(runMCode("WRITE 1+2*3", "9", "Arithmetic"))
  results.add(runMCode("WRITE (1+2)*3", "9", "Arithmetic"))
  results.add(runMCode("WRITE 1E2", "100", "Arithmetic"))
  results.add(runMCode("WRITE 1.5E2", "150", "Arithmetic"))
  
  # ==========================================
  # 2. String Operations
  # ==========================================
  results.add(runMCode("WRITE \"hello\"_\"world\"", "helloworld", "String"))
  results.add(runMCode("WRITE \"abc\"=\"abc\"", "1", "String"))
  results.add(runMCode("WRITE \"abc\"=\"def\"", "0", "String"))
  results.add(runMCode("WRITE \"abc\"'=\\\"def\\\"", "1", "String"))
  results.add(runMCode("WRITE \"abc\"<\"def\"", "1", "String"))
  results.add(runMCode("WRITE \"abc\">\"def\"", "0", "String"))
  results.add(runMCode("WRITE \"abc\"]\"ab\"", "1", "String"))
  results.add(runMCode("WRITE \"abc\"[\"bc\"", "1", "String"))
  
  # ==========================================
  # 3. Variable Operations
  # ==========================================
  results.add(runMCode("SET X=42 WRITE X", "42", "Variable"))
  results.add(runMCode("SET X=\"hello\" WRITE X", "hello", "Variable"))
  results.add(runMCode("SET X=1,Y=2 WRITE X+Y", "3", "Variable"))
  results.add(runMCode("SET A(1)=\"one\" WRITE A(1)", "one", "Variable"))
  results.add(runMCode("SET A(1,2)=\"nested\" WRITE A(1,2)", "nested", "Variable"))
  results.add(runMCode("SET X=42 KILL X WRITE $DATA(X)", "0", "Variable"))
  
  # ==========================================
  # 4. Pattern Matching (BUG if failing)
  # ==========================================
  # Per M standard: 1L.L means "one letter, then zero or more letters"
  # "hello" should match this pattern
  results.add(runMCode("WRITE \"hello\"?1L.L", "1", "Pattern"))
  results.add(runMCode("WRITE \"Hello\"?1U.L", "1", "Pattern"))
  results.add(runMCode("WRITE \"123\"?3N", "1", "Pattern"))
  results.add(runMCode("WRITE \"abc123\"?3L3N", "1", "Pattern"))
  
  # ==========================================
  # 5. $JUSTIFY (BUG if failing)
  # ==========================================
  # Per M standard: $JUSTIFY(expr,width) right-justifies to width
  results.add(runMCode("WRITE $JUSTIFY(42,10)", "        42", "JUSTIFY"))
  results.add(runMCode("WRITE $JUSTIFY(42,0)", "42", "JUSTIFY"))
  results.add(runMCode("WRITE $JUSTIFY(3.14159,10,2)", "      3.14", "JUSTIFY"))
  
  # ==========================================
  # 6. $FNUMBER (BUG if failing)
  # ==========================================
  # Per M standard: $FNUMBER(num,format,precision) with "," adds thousand separators
  results.add(runMCode("WRITE $FNUMBER(1234.567,\"\",2)", "1234.57", "FNUMBER"))
  results.add(runMCode("WRITE $FNUMBER(1234.567,\",\",2)", "1,234.57", "FNUMBER"))
  results.add(runMCode("WRITE $FNUMBER(-1234.567,\"P\",2)", "(1234.57)", "FNUMBER"))
  
  # ==========================================
  # 7. IF/ELSE (BUG if failing)
  # ==========================================
  # Per M standard: ELSE executes when IF condition is false
  results.add(runMCode("SET X=1 IF X=1 WRITE \"yes\"", "yes", "IF"))
  results.add(runMCode("SET X=0 IF X=1 WRITE \"yes\"", "", "IF"))
  results.add(runMCode("SET X=1 IF X=1 WRITE \"yes\" ELSE WRITE \"no\"", "yes", "IF"))
  results.add(runMCode("SET X=0 IF X=1 WRITE \"yes\" ELSE WRITE \"no\"", "no", "IF"))
  
  # ==========================================
  # 8. FOR Loop (BUG if failing)
  # ==========================================
  # Per M standard: FOR var=init:step:limit
  results.add(runMCode("FOR I=1:1:3 WRITE I", "123", "FOR"))
  results.add(runMCode("FOR I=1:2:5 WRITE I", "135", "FOR"))
  results.add(runMCode("FOR I=3:-1:1 WRITE I", "321", "FOR"))
  
  # ==========================================
  # 9. NEW/QUIT Scoping (BUG if failing)
  # ==========================================
  # Per M standard: NEW creates new scope, QUIT restores
  results.add(runMCode("SET X=1 NEW SET X=2 QUIT WRITE X", "1", "NEW"))
  results.add(runMCode("SET X=1 NEW X SET X=2 QUIT WRITE X", "1", "NEW"))
  
  # ==========================================
  # 10. KILL (BUG if failing)
  # ==========================================
  # Per M standard: KILL without args kills all local variables
  # Note: KILL X treats X as variable (not XECUTE command)
  results.add(runMCode("SET X=42 KILL X WRITE $DATA(X)", "0", "KILL"))
  results.add(runMCode("SET A(1)=1,A(2)=2 KILL A(1) WRITE $DATA(A(1))", "0", "KILL"))
  results.add(runMCode("SET A(1)=1,A(2)=2 KILL A(1) WRITE $DATA(A(2))", "1", "KILL"))
  
  # ==========================================
  # 11. DO Command (BUG if failing)
  # ==========================================
  # Per M standard: DO executes a block
  results.add(runMCode("DO WRITE \"hello\"", "hello", "DO"))
  results.add(runMCode("SET X=42 DO WRITE X", "42", "DO"))
  
  # ==========================================
  # 12. Special Variables
  # ==========================================
  results.add(runMCode("WRITE $SYSTEM", "nimm/1.0", "Special"))
  results.add(runMCode("WRITE $IO", "stdout", "Special"))
  results.add(runMCode("WRITE $PRINCIPAL", "stdin", "Special"))
  results.add(runMCode("WRITE $STORAGE", "17179869184", "Special"))
  results.add(runMCode("WRITE $STACK", "0", "Special"))
  results.add(runMCode("WRITE $TEST", "1", "Special"))
  results.add(runMCode("SET $X=10 WRITE $X", "10", "Special"))
  results.add(runMCode("SET $Y=20 WRITE $Y", "20", "Special"))
  results.add(runMCode("WRITE $HOROLOG?5N 1\",\"5N", "1", "Special"))
  results.add(runMCode("WRITE $JOB?1.N", "1", "Special"))
  
  # ==========================================
  # Print Results
  # ==========================================
  echo ""
  echo "=== Test Results ==="
  echo ""
  
  var passed = 0
  var failed = 0
  var bugs: seq[string] = @[]
  var categories: seq[string] = @[]
  
  for r in results:
    if r.category notin categories:
      categories.add(r.category)
  
  for cat in categories:
    echo "--- " & cat & " ---"
    for r in results:
      if r.category == cat:
        if r.passed:
          echo "  ✓ " & r.name
          inc passed
        else:
          echo "  ✗ " & r.name
          echo "    " & r.message
          inc failed
          if cat notin bugs:
            bugs.add(cat)
    echo ""
  
  echo "=== Summary ==="
  echo "Passed: " & $passed
  echo "Failed: " & $failed
  echo "Total: " & $(passed + failed)
  echo "Conformance: " & $(passed * 100 div (passed + failed)) & "%"
  
  if bugs.len > 0:
    echo ""
    echo "=== BUGS FOUND ==="
    for b in bugs:
      echo "  - " & b & " implementation incorrect"
  
  if failed > 0:
    quit(1)

when isMainModule:
  main()
