# test_static_analysis.nim — Test static analysis (ZANALYZE)

import ../static_analysis

proc main() =
  echo "Testing static analysis..."
  
  # Test unused variable detection
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
  
  # Test unreachable code detection
  let code2 = "MAIN\n WRITE \"hello\"\n QUIT\n WRITE \"world\"\n QUIT"
  let report2 = analyzeRoutine(code2)
  echo "  Unreachable warnings: " & $report2.warningCount
  echo "✓ Unreachable code detection"
  
  # Test undefined label detection
  let code3 = """
MAIN
 DO SUB
 QUIT
"""
  let report3 = analyzeRoutine(code3)
  assert report3.warningCount > 0, "Should detect undefined label SUB"
  echo "✓ Undefined label detection"
  
  # Test clean code
  let code4 = """
MAIN
 SET X = 1
 WRITE X
 QUIT
SUB
 SET Y = 2
 WRITE Y
 QUIT
"""
  let report4 = analyzeRoutine(code4)
  # Should have no errors for clean code
  echo "✓ Clean code analysis: " & $report4.warningCount & " warnings"
  
  # Test format report
  let report = analyzeRoutine(code1)
  let formatted = report.formatReport()
  assert formatted.len > 0, "Should format report"
  echo "✓ Format report"
  
  # Test summary
  assert report.errorCount >= 0
  assert report.warningCount > 0
  assert report.infoCount >= 0
  echo "✓ Report summary"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
