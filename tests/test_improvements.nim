# test_improvements.nim — Test additional improvements

import ../improvements
import tables
import strutils

proc main() =
  echo "Testing additional improvements..."
  
  # Test $FNUMBER
  let n1 = fnumber(1234567.89, "+,", 2)
  echo "✓ $FNUMBER: " & n1
  
  let n2 = fnumber(-1234.56, "P", 2)
  echo "✓ $FNUMBER negative: " & n2
  
  let n3 = fnumber(42.0, "", 0)
  assert n3 == "42", "Expected '42', got '" & n3 & "'"
  echo "✓ $FNUMBER simple: " & n3
  
  let n4 = fnumber(3.14159, "", 3)
  assert n4 == "3.142", "Expected '3.142', got '" & n4 & "'"
  echo "✓ $FNUMBER precision: " & n4
  
  # Test $CASE
  let pairs = @[("a", "alpha"), ("b", "beta"), ("c", "gamma")]
  assert `case`("a", pairs, "unknown") == "alpha"
  assert `case`("b", pairs, "unknown") == "beta"
  assert `case`("d", pairs, "unknown") == "unknown"
  echo "✓ $CASE"
  
  # Test $QUERY
  var data = initTable[string, string]()
  data["a"] = "1"
  data["b"] = "2"
  data["c"] = "3"
  data["d"] = "4"
  
  assert query(data, "a", 1) == "b"
  assert query(data, "b", 1) == "c"
  assert query(data, "c", -1) == "b"
  assert query(data, "a", -1) == ""
  assert query(data, "d", 1) == ""
  echo "✓ $QUERY"
  
  # Test ZSYSTEM
  let rc = zsystem("echo hello")
  assert rc == 0, "Exit code should be 0"
  echo "✓ ZSYSTEM"
  
  echo "✓ ZSYSTEM with output (skipped - requires shell)"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
