# test_engine.nim — Test command dispatch engine

import ../engine
import ../globals
import ../evaluator
import ../runtime
import ../ast
import ../parser

proc main() =
  echo "Testing engine..."

  var g = newGlobals()
  var rt = newRuntime()
  var ev = newEvaluator(g, rt)
  var eng = newEngine(g, ev, rt)

  # Test SET
  let setLine = parseLine("SET X = 42")
  discard eng.execute(setLine)
  assert g.get("X") == "42"
  echo "OK SET"

  # Test WRITE
  eng.clearOutput()
  let writeLine = parseLine("WRITE \"hello\"")
  discard eng.execute(writeLine)
  assert eng.getOutput() == "hello"
  echo "OK WRITE"

  # Test SET + WRITE
  eng.clearOutput()
  let setWrite = parseLine("SET Y = \"world\" WRITE Y")
  discard eng.execute(setWrite)
  assert eng.getOutput() == "world"
  echo "OK SET + WRITE"

  # Test arithmetic
  eng.clearOutput()
  let arith = parseLine("SET Z = 2 + 3 WRITE Z")
  discard eng.execute(arith)
  assert eng.getOutput() == "5"
  echo "OK Arithmetic"

  # Test KILL
  g.set("K", @[], "value")
  let killLine = parseLine("KILL K")
  discard eng.execute(killLine)
  assert g.get("K") == ""
  echo "OK KILL"

  echo "\nAll tests passed!"

when isMainModule:
  main()
