# test_static_analysis.nim — Test static analysis (ZANALYZE / --lint)

import ../static_analysis

proc main() =
  echo "Testing static analysis..."

  # Test unused variable detection (W001)
  let code1 = """
MAIN
 SET X = 1
 SET Y = 2
 WRITE X
 QUIT
"""
  let report1 = analyzeRoutine(code1)
  assert report1.warningCount > 0, "Should detect unused variable Y"
  echo "✓ Unused variable detection"

  # Test unreachable code detection (W002)
  let code2 = "MAIN\n WRITE \"hello\"\n QUIT\n WRITE \"world\"\n QUIT"
  let report2 = analyzeRoutine(code2)
  assert report2.warningCount > 0, "Should detect unreachable code after QUIT"
  echo "✓ Unreachable code detection"

  # Test undefined label detection (W003)
  let code3 = """
MAIN
 DO SUB
 QUIT
"""
  let report3 = analyzeRoutine(code3)
  assert report3.warningCount > 0, "Should detect undefined label SUB"
  echo "✓ Undefined label detection"

  # Test unused label detection (W004)
  let code4 = """
MAIN
 WRITE "hi"
 QUIT
DEAD
 QUIT
"""
  let report4 = analyzeRoutine(code4)
  assert report4.warningCount > 0, "Should detect unused label DEAD"
  echo "✓ Unused label detection"

  # Test precedence hazard (W006)
  let code5 = "MAIN\n SET A = 1 + 2 * 3\n WRITE A\n QUIT"
  let report5 = analyzeRoutine(code5)
  assert report5.infoCount > 0, "Should flag mixed +-/* precedence"
  echo "✓ Precedence hazard detection"

  # Test clean code (no warnings)
  let code6 = """
MAIN
 SET X = 1
 WRITE X
 QUIT
"""
  let report6 = analyzeRoutine(code6)
  assert report6.warningCount == 0, "Clean code should have 0 warnings, got " &
         $report6.warningCount
  echo "✓ Clean code has 0 warnings"

  # Test format report
  let formatted = analyzeRoutine(code1).formatReport()
  assert formatted.len > 0, "Should format report"
  echo "✓ Format report"

  # Test summary fields
  assert report1.errorCount >= 0
  assert report1.warningCount > 0
  assert report1.infoCount >= 0
  echo "✓ Report summary"

  echo "\nAll tests passed!"

when isMainModule:
  main()
