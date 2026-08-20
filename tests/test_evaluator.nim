# test_evaluator.nim — Test expression evaluator

import ../evaluator
import ../globals
import ../runtime
import ../ast

proc main() =
  echo "Testing evaluator..."
  
  var g = newGlobals()
  var rt = newRuntime()
  var ev = newEvaluator(g, rt)
  
  # Test numeric literals
  let numExpr = Expr(kind: numLit, sval: "42")
  assert ev.eval(numExpr) == "42"
  echo "OK Numeric literal"
  
  # Test string literals
  let strExpr = Expr(kind: eStr, sval: "hello")
  assert ev.eval(strExpr) == "hello"
  echo "OK String literal"
  
  # Test variable reference
  g.set("X", @[], "world")
  let varExpr = Expr(kind: eVar, vname: "X")
  assert ev.eval(varExpr) == "world"
  echo "OK Variable reference"
  
  # Test arithmetic
  let addExpr = Expr(kind: eBinary, op: bAdd,
    left: Expr(kind: numLit, sval: "3"),
    right: Expr(kind: numLit, sval: "4"))
  assert ev.eval(addExpr) == "7"
  echo "OK Addition"
  
  let mulExpr = Expr(kind: eBinary, op: bMul,
    left: Expr(kind: numLit, sval: "3"),
    right: Expr(kind: numLit, sval: "4"))
  assert ev.eval(mulExpr) == "12"
  echo "OK Multiplication"
  
  # Test string concatenation
  let concatExpr = Expr(kind: eBinary, op: bConcat,
    left: Expr(kind: eStr, sval: "hello"),
    right: Expr(kind: eStr, sval: " world"))
  assert ev.eval(concatExpr) == "hello world"
  echo "OK Concatenation"
  
  # Test comparison
  let eqlExpr = Expr(kind: eBinary, op: bEql,
    left: Expr(kind: numLit, sval: "5"),
    right: Expr(kind: numLit, sval: "5"))
  assert ev.eval(eqlExpr) == "1"
  echo "OK Equality"
  
  # Test logical NOT
  let notExpr = Expr(kind: eNot, operand: Expr(kind: numLit, sval: "0"))
  assert ev.eval(notExpr) == "1"
  echo "OK NOT"
  
  # Test LENGTH function
  let lenExpr = Expr(kind: eFunc, fname: "LENGTH", fargs: @[Expr(kind: eStr, sval: "hello")])
  assert ev.eval(lenExpr) == "5"
  echo "OK LENGTH"
  
  # Test EXTRACT function
  let extExpr = Expr(kind: eFunc, fname: "EXTRACT", fargs: @[
    Expr(kind: eStr, sval: "hello"),
    Expr(kind: numLit, sval: "2"),
    Expr(kind: numLit, sval: "4")
  ])
  assert ev.eval(extExpr) == "ell"
  echo "OK EXTRACT"
  
  # Test CHAR function
  let charExpr = Expr(kind: eFunc, fname: "CHAR", fargs: @[Expr(kind: numLit, sval: "65")])
  assert ev.eval(charExpr) == "A"
  echo "OK CHAR"
  
  # Test TRANSLATE function
  let trExpr = Expr(kind: eFunc, fname: "TRANSLATE", fargs: @[
    Expr(kind: eStr, sval: "hello"),
    Expr(kind: eStr, sval: "eo"),
    Expr(kind: eStr, sval: "EO")
  ])
  assert ev.eval(trExpr) == "hEllO"
  echo "OK TRANSLATE"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
