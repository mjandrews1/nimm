# test_globals.nim — Test global/local variable storage

import ../globals
import tables

proc main() =
  echo "Testing globals..."
  
  # Test with no LMDB (local vars only)
  var g = newGlobals()
  
  # Test set/get local variable
  g.set("X", @[], "hello")
  assert g.get("X", @[]) == "hello"
  echo "✓ Set/get local variable"
  
  # Test subscripts
  g.set("ARR", @["a"], "1")
  g.set("ARR", @["b"], "2")
  assert g.get("ARR", @["a"]) == "1"
  assert g.get("ARR", @["b"]) == "2"
  echo "✓ Subscripts"
  
  # Test $DATA
  assert g.data("X", @[]) == 1
  assert g.data("ARR", @[]) == 10  # descendants only
  assert g.data("ARR", @["a"]) == 1
  assert g.data("UNDEF", @[]) == 0
  echo "✓ $DATA"
  
  # Test $ORDER
  let keys = @["a", "b", "c"]
  for k in keys:
    g.set("ORD", @[k], k)
  assert g.orderLocal("ORD", @[], true) == "a"
  assert g.orderLocal("ORD", @["a"], true) == "b"
  assert g.orderLocal("ORD", @["c"], false) == "b"
  echo "✓ $ORDER"
  
  # Test KILL
  g.kill("X")
  assert g.get("X", @[]) == ""
  echo "✓ KILL"
  
  # Test KILL subscript
  g.kill("ARR", @["a"])
  assert g.get("ARR", @["a"]) == ""
  assert g.get("ARR", @["b"]) == "2"
  echo "✓ KILL subscript"
  
  # Test NEW/QUIT scoping (§7.2.11/7.2.12)
  # Without NEW: writes persist after popScope (COW write-through)
  g.set("Y", @[], "outer")
  g.pushScope()
  assert g.get("Y", @[]) == "outer"  # visible in new scope (COW read)
  g.set("Y", @[], "inner")
  assert g.get("Y", @[]) == "inner"
  g.popScope()
  assert g.get("Y", @[]) == "inner"  # persists — Y was NOT NEW'd
  echo "✓ NEW/QUIT scoping (non-NEW'd write persists)"
  
  # Test scope depth
  assert g.scopeDepth() == 1
  g.pushScope()
  assert g.scopeDepth() == 2
  g.popScope()
  assert g.scopeDepth() == 1
  echo "✓ Scope depth"
  
  # Test special variables
  var testVal = "test_value"
  g.registerSpecialVar("$TEST", proc(): string = testVal)
  assert g.getSpecialVar("$TEST") == "test_value"
  echo "✓ Special variables"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
