# test_error_handling.nim — Test error handling ($ECODE/$ETRAP)

import ../runtime

proc main() =
  echo "Testing error handling..."
  
  var rt = newRuntime()
  
  # Test initial state
  assert rt.hasError() == false
  assert rt.ecode == ""
  assert rt.zstatus == ""
  assert rt.zerror == ""
  assert rt.etrap == ""
  echo "✓ Initial state clean"
  
  # Test setError
  rt.setError("M6", "Undefined variable")
  assert rt.hasError() == true
  assert rt.ecode == "M6"
  assert rt.zerror == "Undefined variable"
  assert rt.zstatus == "M6:Undefined variable"
  echo "✓ setError works"
  
  # Test getLastError
  let last = rt.getLastError()
  assert last == "M6:Undefined variable"
  echo "✓ getLastError works"
  
  # Test error stack
  rt.setError("M7", "Type mismatch")
  assert rt.errorStack.len == 2
  echo "✓ Error stack accumulates"
  
  # Test popError
  let popped = rt.popError()
  assert popped == "M7:Type mismatch"
  assert rt.errorStack.len == 1
  echo "✓ popError works"
  
  # Test clearError
  rt.clearError()
  assert rt.hasError() == false
  assert rt.ecode == ""
  assert rt.zstatus == ""
  echo "✓ clearError works"
  
  # Test $ETRAP
  rt.setEtrap("WRITE !,\"Error: \",$ZERROR")
  assert rt.getEtrap() == "WRITE !,\"Error: \",$ZERROR"
  echo "✓ $ETRAP set/get works"
  
  # Test reset
  rt.setError("M9", "Test error")
  rt.setEtrap("QUIT")
  rt.reset()
  assert rt.hasError() == false
  assert rt.etrap == ""
  assert rt.errorStack.len == 0
  echo "✓ reset works"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
