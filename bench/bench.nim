# bench/bench.nim — In-process nimm micro-benchmarks
#
# Measures real interpreter performance without OS process spawn overhead.
# Usage: nim c -d:release -r bench/bench.nim [--iterations=N]

import std/[times, os, strutils, monotimes]

import ../globals
import ../evaluator
import ../runtime
import ../engine
import ../parser
import ../special_vars

type
  BenchResult = object
    name: string
    iterations: int
    totalUs: float64
    perCallUs: float64
    opsPerSec: float64

var
  g: Globals
  rt: Runtime
  ev: Evaluator
  eng: Engine

proc initComponents() =
  g = newGlobals()
  g.registerAllSpecialVars()
  rt = newRuntime(nimm)
  ev = newEvaluator(g, rt)
  eng = newEngine(g, ev, rt)

proc teardownComponents() =
  g.close()

proc bench(name: string, code: string, iterations: int): BenchResult =
  ## Benchmark a single M code expression by parsing+executing N times.
  # Warm up: parse + execute once
  eng.clearOutput()
  let warmup = parseLine(code)
  discard eng.execute(warmup)

  # Timed run
  let t0 = getMonoTime()
  for i in 1..iterations:
    eng.clearOutput()
    let line = parseLine(code)
    discard eng.execute(line)
  let elapsed = getMonoTime() - t0
  let totalUs = elapsed.inMicroseconds.float64
  let perCallUs = totalUs / iterations.float64
  let opsPerSec = 1_000_000.0 / perCallUs

  BenchResult(name: name, iterations: iterations, totalUs: totalUs,
              perCallUs: perCallUs, opsPerSec: opsPerSec)

proc benchEval(name: string, code: string, iterations: int): BenchResult =
  ## Benchmark by evaluating the same pre-parsed AST N times.
  eng.clearOutput()
  let ast = parseLine(code)

  let t0 = getMonoTime()
  for i in 1..iterations:
    discard eng.execute(ast)
  let elapsed = getMonoTime() - t0
  let totalUs = elapsed.inMicroseconds.float64
  let perCallUs = totalUs / iterations.float64
  let opsPerSec = 1_000_000.0 / perCallUs

  BenchResult(name: name, iterations: iterations, totalUs: totalUs,
              perCallUs: perCallUs, opsPerSec: opsPerSec)

proc printResult(r: BenchResult) =
  let padName = r.name.alignLeft(35)
  let padUs = formatFloat(r.perCallUs, ffDecimal, 3).alignLeft(12)
  let padOps = formatFloat(r.opsPerSec, ffDecimal, 0).alignLeft(12)
  echo padName, padUs, " us/call   ", padOps, " ops/sec"

proc printCategory(catName: string, results: seq[BenchResult]) =
  echo ""
  echo "=== ", catName, " ==="
  echo "Operation".alignLeft(35), "Time".alignLeft(12), "Throughput"
  echo "-".repeat(62)
  for r in results:
    printResult(r)

proc parseCliIterations(): int =
  result = 100_000  # default
  let args = commandLineParams()
  for arg in args:
    if arg.startsWith("--iterations="):
      try:
        result = parseInt(arg.split("=")[1])
      except:
        discard

proc main() =
  let iterations = parseCliIterations()

  echo "nimm In-Process Benchmark"
  echo "========================="
  echo "Iterations per test: ", iterations
  echo ""

  initComponents()

  # -------------------------------------------------------------------
  # Category 1: Parse + Execute (full pipeline)
  # -------------------------------------------------------------------
  var catParseExec: seq[BenchResult]
  catParseExec.add bench("WRITE 1+2",           "WRITE 1+2",           iterations)
  catParseExec.add bench("WRITE 5-3",           "WRITE 5-3",           iterations)
  catParseExec.add bench("WRITE 2*3",           "WRITE 2*3",           iterations)
  catParseExec.add bench("WRITE 10/2",          "WRITE 10/2",          iterations)
  catParseExec.add bench("WRITE 10#3",          "WRITE 10#3",          iterations)
  catParseExec.add bench("WRITE 2**3",          "WRITE 2**3",          iterations)
  catParseExec.add bench("SET X=42 WRITE X",   "SET X=42 WRITE X",   iterations)
  catParseExec.add bench("SET X=1,Y=2 WRITE X+Y", "SET X=1,Y=2 WRITE X+Y", iterations)
  printCategory("Parse + Execute (full pipeline)", catParseExec)

  # -------------------------------------------------------------------
  # Category 2: Execute only (pre-parsed AST)
  # -------------------------------------------------------------------
  var catExec: seq[BenchResult]
  catExec.add benchEval("WRITE 1+2 (exec)",      "WRITE 1+2",      iterations)
  catExec.add benchEval("SET X=42 WRITE X (exec)", "SET X=42 WRITE X", iterations)
  catExec.add benchEval("IF 1 WRITE yes (exec)", "IF 1 WRITE yes", iterations)
  catExec.add benchEval("IF 0 WRITE no (exec)",  "IF 0 WRITE no",  iterations)
  printCategory("Execute Only (pre-parsed AST)", catExec)

  # -------------------------------------------------------------------
  # Category 3: Intrinsic functions
  # -------------------------------------------------------------------
  var catFunc: seq[BenchResult]
  catFunc.add bench("WRITE $ASCII(\"A\")",         "WRITE $ASCII(\"A\")",         iterations)
  catFunc.add bench("WRITE $CHAR(65)",              "WRITE $CHAR(65)",              iterations)
  catFunc.add bench("WRITE $LENGTH(\"hello\")",     "WRITE $LENGTH(\"hello\")",     iterations)
  catFunc.add bench("WRITE $EXTRACT(\"hello\",2,4)","WRITE $EXTRACT(\"hello\",2,4)",iterations)
  catFunc.add bench("WRITE $FIND(\"hello\",\"l\")", "WRITE $FIND(\"hello\",\"l\")", iterations)
  catFunc.add bench("WRITE $REVERSE(\"hello\")",    "WRITE $REVERSE(\"hello\")",    iterations)
  catFunc.add bench("WRITE $TRANSLATE(\"hello\",\"el\",\"EL\")",
                    "WRITE $TRANSLATE(\"hello\",\"el\",\"EL\")", iterations)
  catFunc.add bench("WRITE $JUSTIFY(42,10)",        "WRITE $JUSTIFY(42,10)",        iterations)
  catFunc.add bench("WRITE $SELECT(1:\"yes\",0:\"no\")",
                    "WRITE $SELECT(1:\"yes\",0:\"no\")", iterations)
  catFunc.add bench("WRITE $PIECE(\"a^b^c\",\"^\",2)",
                    "WRITE $PIECE(\"a^b^c\",\"^\",2)", iterations)
  printCategory("Intrinsic Functions", catFunc)

  # -------------------------------------------------------------------
  # Category 4: Comparison operators
  # -------------------------------------------------------------------
  var catCmp: seq[BenchResult]
  catCmp.add bench("WRITE 1=1",    "WRITE 1=1",    iterations)
  catCmp.add bench("WRITE 1=2",    "WRITE 1=2",    iterations)
  catCmp.add bench("WRITE 1'=2",   "WRITE 1'=2",   iterations)
  catCmp.add bench("WRITE 1<2",    "WRITE 1<2",    iterations)
  catCmp.add bench("WRITE 2>1",    "WRITE 2>1",    iterations)
  catCmp.add bench("WRITE \"abc\"=\"abc\"", "WRITE \"abc\"=\"abc\"", iterations)
  catCmp.add bench("WRITE \"abc\"=\"def\"", "WRITE \"abc\"=\"def\"", iterations)
  printCategory("Comparison Operators", catCmp)

  # -------------------------------------------------------------------
  # Category 5: Variable operations (local)
  # -------------------------------------------------------------------
  var catVar: seq[BenchResult]
  catVar.add bench("SET X=1",                       "SET X=1",                       iterations)
  catVar.add bench("SET X=1 WRITE X",               "SET X=1 WRITE X",               iterations)
  catVar.add bench("SET X=1 SET Y=X WRITE Y",       "SET X=1 SET Y=X WRITE Y",       iterations)
  catVar.add bench("SET X=1 WRITE $DATA(X)",        "SET X=1 WRITE $DATA(X)",        iterations)
  catVar.add bench("SET X=1 WRITE $GET(X)",         "SET X=1 WRITE $GET(X)",         iterations)
  catVar.add bench("SET X=1 KILL X WRITE $DATA(X)", "SET X=1 KILL X WRITE $DATA(X)", iterations)
  printCategory("Variable Operations (local)", catVar)

  # -------------------------------------------------------------------
  # Category 6: Pattern matching
  # -------------------------------------------------------------------
  var catPat: seq[BenchResult]
  catPat.add bench("WRITE \"Hello\"?1U.L",    "WRITE \"Hello\"?1U.L",    iterations)
  catPat.add bench("WRITE \"hello\"?1L.L",    "WRITE \"hello\"?1L.L",    iterations)
  catPat.add bench("WRITE \"123\"?3N",         "WRITE \"123\"?3N",         iterations)
  catPat.add bench("WRITE \"abc123\"?1.L1.N", "WRITE \"abc123\"?1.L1.N", iterations)
  printCategory("Pattern Matching", catPat)

  # -------------------------------------------------------------------
  # Category 7: FOR loop
  # -------------------------------------------------------------------
  var catFor: seq[BenchResult]
  catFor.add bench("FOR I=1:1:10 SET X=I",   "FOR I=1:1:10 SET X=I",   max(1, iterations div 10))
  catFor.add bench("FOR I=1:1:100 SET X=I",  "FOR I=1:1:100 SET X=I",  max(1, iterations div 100))
  catFor.add bench("FOR I=1:1:1000 SET X=I", "FOR I=1:1:1000 SET X=I", max(1, iterations div 1000))
  printCategory("FOR Loop", catFor)

  # -------------------------------------------------------------------
  # Category 8: Z-commands (RSM extensions)
  # -------------------------------------------------------------------
  var catZ: seq[BenchResult]
  catZ.add bench("WRITE $ZABS(-5)",         "WRITE $ZABS(-5)",         iterations)
  catZ.add bench("WRITE $ZSQRT(16)",        "WRITE $ZSQRT(16)",        iterations)
  catZ.add bench("WRITE $ZSIN(0)",          "WRITE $ZSIN(0)",          iterations)
  catZ.add bench("WRITE $ZCOS(0)",          "WRITE $ZCOS(0)",          iterations)
  catZ.add bench("WRITE $ZCONVERT(\"hello\",\"U\")",
                 "WRITE $ZCONVERT(\"hello\",\"U\")", iterations)
  catZ.add bench("WRITE $ZHOROLOG",         "WRITE $ZHOROLOG",         iterations)
  printCategory("RSM Z-Functions", catZ)

  # -------------------------------------------------------------------
  # Category 9: Special variables
  # -------------------------------------------------------------------
  var catSvar: seq[BenchResult]
  catSvar.add bench("WRITE $HOROLOG",  "WRITE $HOROLOG",  iterations)
  catSvar.add bench("WRITE $H",        "WRITE $H",        iterations)
  catSvar.add bench("WRITE $IO",       "WRITE $IO",       iterations)
  catSvar.add bench("WRITE $TEST",     "WRITE $TEST",     iterations)
  catSvar.add bench("WRITE $JOB",      "WRITE $JOB",      iterations)
  catSvar.add bench("WRITE $SYSTEM",   "WRITE $SYSTEM",   iterations)
  printCategory("Special Variables", catSvar)

  # -------------------------------------------------------------------
  # Category 10: nimm extensions
  # -------------------------------------------------------------------
  var catNimm: seq[BenchResult]
  catNimm.add bench("WRITE $NI_UUID",         "WRITE $NI_UUID",         iterations)
  catNimm.add bench("WRITE $NI_SYSTEM",       "WRITE $NI_SYSTEM",       iterations)
  catNimm.add bench("WRITE $ZDATETIME($HOROLOG,\"YYYY-MM-DD HH:MI:SS\")",
                    "WRITE $ZDATETIME($HOROLOG,\"YYYY-MM-DD HH:MI:SS\")", iterations)
  catNimm.add bench("WRITE $ZSTRIP(\"  hello  \",\"*\")",
                    "WRITE $ZSTRIP(\"  hello  \",\"*\")", iterations)
  catNimm.add bench("WRITE $ZSUBSTR(\"hello\",2,3)",
                    "WRITE $ZSUBSTR(\"hello\",2,3)", iterations)
  printCategory("nimm Extensions", catNimm)

  # -------------------------------------------------------------------
  # Summary
  # -------------------------------------------------------------------
  echo ""
  echo "=== Benchmark Complete ==="
  echo "Note: Times include parse + AST allocation + execute + GC."
  echo "For execute-only times, see 'Execute Only' category above."

  teardownComponents()

when isMainModule:
  main()
