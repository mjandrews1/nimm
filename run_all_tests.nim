# run_all_tests.nim — Run all unit tests for nimm
# Runs each test module and reports results

import os
import strutils
import osproc

type
  TestResult = object
    name: string
    passed: bool
    message: string

proc runTest(name: string): TestResult =
  result.name = name
  result.passed = false
  result.message = ""
  
  # Set library path for LMDB
  putEnv("DYLD_LIBRARY_PATH", "/usr/local/lib")
  
  # Compile first
  let compileCmd = "nim c -d:release tests/test_" & name & ".nim"
  let compileExitCode = execCmd(compileCmd)
  if compileExitCode != 0:
    result.message = "Compilation failed with exit code " & $compileExitCode
    return
  
  # Run the test
  let runCmd = "DYLD_LIBRARY_PATH=/usr/local/lib tests/test_" & name
  let exitCode = execCmd(runCmd)
  if exitCode == 0:
    result.passed = true
    result.message = "OK"
  else:
    result.message = "Failed with exit code " & $exitCode

proc main() =
  echo "=== nimm Unit Tests ==="
  echo ""
  
  var results: seq[TestResult] = @[]
  
  # Test globals
  results.add(runTest("globals"))
  
  # Test evaluator
  results.add(runTest("evaluator"))
  
  # Test engine
  results.add(runTest("engine"))
  
  # Test data structures
  results.add(runTest("data_structures"))
  
  # Test advanced structures
  results.add(runTest("advanced_structures"))
  
  # Test new structures
  results.add(runTest("new_structures"))
  
  # Test specialized structures
  results.add(runTest("specialized_structures"))
  
  # Test LMDB
  results.add(runTest("lmdb"))
  
  # Test text
  results.add(runTest("text"))
  
  # Test mode
  results.add(runTest("mode"))
  
  # Test unicode
  results.add(runTest("unicode"))
  
  # Test tracing
  results.add(runTest("tracing"))
  
  # Test debugging
  results.add(runTest("debugging"))
  
  # Test network
  results.add(runTest("network"))
  
  # Test NI functions
  results.add(runTest("ni_functions"))
  
  # Test static analysis
  results.add(runTest("static_analysis"))
  
  # Test inspector
  results.add(runTest("inspector"))
  
  # Test error handling
  results.add(runTest("error_handling"))
  
  # Print results
  echo ""
  echo "=== Test Results ==="
  echo ""
  
  var passed = 0
  var failed = 0
  
  for r in results:
    if r.passed:
      echo "✓ " & r.name & ": " & r.message
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
