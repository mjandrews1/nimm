# test_for_quit.nim — Diagnostic test for FOR+QUIT bug (#196)
#
# Diagnostics:
#   1. AST Dump — verify parsing of problem patterns
#   4. Minimal Test Harness — execute and report results
#   5. Side-by-side comparison — QUIT:X>3 vs IF X>3 QUIT

import strutils
import times
import ast
import parser
import globals
import evaluator
import runtime
import engine
import special_vars

proc dumpExpr(e: Expr, indent: int = 0): string =
  let pad = "  ".repeat(indent)
  case e.kind
  of numLit: result = pad & "NumLit(\"" & e.sval & "\")"
  of eStr: result = pad & "StrLit(\"" & e.sval & "\")"
  of eVar:
    result = pad & "Var(\"" & e.vname & "\""
    if e.subs.len > 0:
      result &= ", subs=["
      for i, sub in e.subs:
        if i > 0: result &= ", "
        result &= dumpExpr(sub, 0)
      result &= "]"
    result &= ")"
  of eBinary:
    let opStr = case e.op
      of bAdd: "+"
      of bSub: "-"
      of bMul: "*"
      of bDiv: "/"
      of bIntDiv: "\\"
      of bMod: "#"
      of bPow: "**"
      of bConcat: "_"
      of bEql: "="
      of bNeql: "'="
      of bLt: "<"
      of bGt: ">"
      of bNlt: "'<"
      of bNgt: "'>"
      of bFollows: "["
      of bSortAfter: "]"
      of bContains: "["
      of bNotFollows: "'["
      of bNotContains: "']"
      of bAnd: "&"
      of bOr: "!"
    result = pad & "Binary(" & opStr & ", " & dumpExpr(e.left, 0) & ", " & dumpExpr(e.right, 0) & ")"
  of eNot:
    result = pad & "Not(" & dumpExpr(e.operand, 0) & ")"
  of eFunc:
    result = pad & "Func(" & e.fname & ", args=["
    for i, arg in e.fargs:
      if i > 0: result &= ", "
      result &= dumpExpr(arg, 0)
    result &= "])"
  else:
    result = pad & "Expr(kind=" & $e.kind & ")"

proc dumpCmd(node: CommandNode, indent: int = 0): string =
  let pad = "  ".repeat(indent)
  result = pad & "CmdNode("
  if node.postcond != nil:
    result &= "postcond=" & dumpExpr(node.postcond, 0) & ", "
  let cmd = node.cmd
  case cmd.kind
  of cQuit:
    result &= "QUIT"
    if cmd.quitVal != nil:
      result &= ", quitVal=" & dumpExpr(cmd.quitVal, 0)
    else:
      result &= ", quitVal=nil"
  of cSet:
    result &= "SET ["
    for i, item in cmd.setItems:
      if i > 0: result &= ", "
      case item.target.kind
      of stVar:
        result &= item.target.tname
        if item.target.tsubs.len > 0:
          result &= "("
          for j, s in item.target.tsubs:
            if j > 0: result &= ","
            result &= dumpExpr(s, 0)
          result &= ")"
      of stPiece:
        result &= "$PIECE(" & item.target.targetVar & ",...)"
      of stExtract:
        result &= "$EXTRACT(" & item.target.targetVar & ",...)"
      of stIndirect:
        result &= "@(...)"
      result &= "=" & dumpExpr(item.value, 0)
    result &= "]"
  of cWrite:
    result &= "WRITE"
  of cIf:
    result &= "IF " & dumpExpr(cmd.ifCond, 0)
    if cmd.ifBody != nil:
      result &= " body=["
      for i, n in cmd.ifBody.cmds:
        if i > 0: result &= ", "
        result &= dumpCmd(n, 0)
      result &= "]"
    else:
      result &= " body=nil"
  of cFor:
    if cmd.forSpec.varName == "":
      result &= "FOR (argumentless)"
    else:
      result &= "FOR " & cmd.forSpec.varName & "=" & dumpExpr(cmd.forSpec.initE, 0)
    if cmd.forBody != nil:
      result &= " body=["
      for i, n in cmd.forBody.cmds:
        if i > 0: result &= ", "
        result &= dumpCmd(n, 0)
      result &= "]"
  of cRead:
    result &= "READ"
    for v in cmd.readVars:
      result &= " " & dumpExpr(v, 0)
  of cOpen:
    result &= "OPEN"
  of cUse:
    result &= "USE"
  of cClose:
    result &= "CLOSE"
  of cKill:
    result &= "KILL"
  of cNew:
    result &= "NEW"
  of cDo:
    result &= "DO"
  of cDoInline:
    result &= "DO INLINE"
    if cmd.doInlineBody != nil:
      result &= " body=["
      for i, n in cmd.doInlineBody.cmds:
        if i > 0: result &= ", "
        result &= dumpCmd(n, 0)
      result &= "]"
  else:
    result &= "Cmd(kind=" & $cmd.kind & ")"
  result &= ")"

proc dumpLine(line: Line, indent: int = 0): string =
  if line == nil: return "nil"
  let pad = "  ".repeat(indent)
  result = pad & "Line(cmds=[\n"
  for i, node in line.cmds:
    if i > 0: result &= ",\n"
    result &= dumpCmd(node, indent + 1)
  result &= "\n" & pad & "])"

proc testPattern(name: string, code: string, maxIter: int = 20) =
  echo "\n" & "=".repeat(60)
  echo "TEST: ", name
  echo "CODE: ", code
  echo "=".repeat(60)

  # --- Diagnostic 1: AST Dump ---
  echo "\n--- AST Dump ---"
  let line = parseLine(code)
  echo dumpLine(line)

  # --- Diagnostic 4: Execute ---
  echo "\n--- Execution ---"
  var g = newGlobals()
  registerAllSpecialVars(g)
  var rt = newRuntime()
  var ev = newEvaluator(g, rt)
  var eng = newEngine(g, ev, rt)

  let startTime = cpuTime()
  eng.clearOutput()

  # We can't easily run with a timeout, but we can set up and execute
  let execResult = eng.execute(line)
  let elapsed = cpuTime() - startTime

  echo "Execute returned: \"", execResult, "\""
  echo "Output: ", eng.output
  echo "Elapsed: ", formatFloat(elapsed, ffDecimal, 4), "s"

  # Show variable state
  echo "X = \"", g.get("X"), "\""
  echo "$ZEOF = \"", g.getSpecialVar("$ZEOF"), "\""

proc main() =
  echo "NimM FOR+QUIT Diagnostic Suite"
  echo "=============================="

  # --- Diagnostic 5: Side-by-side comparison ---

  # Pattern A: Counted FOR with QUIT postconditional (known WORKING)
  testPattern(
    "A: Counted FOR + QUIT:X>3",
    "SET X=0 FOR I=1:1:10 SET X=X+1 QUIT:X>3 WRITE X,! "
  )

  # Pattern B: Argumentless FOR + QUIT postconditional
  testPattern(
    "B: Argumentless FOR + QUIT:X>3",
    "SET X=0 FOR  SET X=X+1 QUIT:X>3 WRITE X,! "
  )

  # Pattern C: Argumentless FOR + IF X>3 QUIT (the BROKEN one)
  testPattern(
    "C: Argumentless FOR + IF X>3 QUIT",
    "SET X=0 FOR  SET X=X+1 IF X>3 QUIT WRITE X,! "
  )

  # Pattern D: Argumentless FOR + bare QUIT (should NOT hang)
  testPattern(
    "D: Argumentless FOR + bare QUIT after 3",
    "SET X=0 FOR  SET X=X+1 IF X=3 QUIT WRITE X,! "
  )

  # Pattern E: Bare QUIT in argumentless FOR (should exit immediately)
  testPattern(
    "E: Argumentless FOR + immediate QUIT",
    "SET X=0 FOR  SET X=X+1 QUIT WRITE X,! "
  )

  # --- Diagnostic 5 continued: File I/O + READ + QUIT:$ZEOF ---

  # Pattern F: ERIC loader pattern — file I/O with READ + QUIT:$ZEOF
  echo "\n" & "=".repeat(60)
  echo "TEST: F: File I/O + READ + QUIT:$ZEOF (ERIC pattern)"
  echo "=".repeat(60)

  var g2 = newGlobals()
  registerAllSpecialVars(g2)
  var rt2 = newRuntime()
  var ev2 = newEvaluator(g2, rt2)
  var eng2 = newEngine(g2, ev2, rt2)

  # M code with proper line breaks (FOR body should NOT include CLOSE/USE)
  # In M, everything after FOR until EOL is the FOR body.
  # So CLOSE/USE must be on a separate line.
  let fileCode = "OPEN 1:(\"/tmp/eric_test/test_data.txt\":\"READ\") USE 1 READ HEADER SET COUNT=0\nFOR  READ LINE QUIT:$ZEOF  SET COUNT=COUNT+1 WRITE LINE,!\nCLOSE 1 USE 0 WRITE \"DONE:\",COUNT,!"
  echo "CODE (with line breaks):"
  echo fileCode
  echo "---"

  # Parse as multi-line: split on newlines and execute each line
  let fileLines = fileCode.split("\n")
  echo "\n--- AST Dump ---"
  for i, lineStr in fileLines:
    let parsed = parseLine(lineStr)
    echo "Line ", i, ": ", dumpLine(parsed)

  echo "\n--- Execution ---"
  eng2.clearOutput()
  for lineStr in fileLines:
    let parsed = parseLine(lineStr)
    discard eng2.execute(parsed)
  echo "Output:"
  echo eng2.output
  echo "COUNT = \"", g2.get("COUNT"), "\""

  # Pattern G: Minimal ERIC pattern — just READ + QUIT:$ZEOF
  echo "\n" & "=".repeat(60)
  echo "TEST: G: Minimal READ + QUIT:$ZEOF"
  echo "=".repeat(60)

  var g3 = newGlobals()
  registerAllSpecialVars(g3)
  var rt3 = newRuntime()
  var ev3 = newEvaluator(g3, rt3)
  var eng3 = newEngine(g3, ev3, rt3)

  let miniCode = "OPEN 1:(\"/tmp/eric_test/test_data.txt\":\"READ\") USE 1 READ HEADER\nFOR  READ LINE QUIT:$ZEOF  WRITE LINE,!\nCLOSE 1 USE 0"
  echo "CODE (with line breaks):"
  echo miniCode
  echo "---"

  let miniLines = miniCode.split("\n")
  echo "\n--- AST Dump ---"
  for i, lineStr in miniLines:
    let parsed = parseLine(lineStr)
    echo "Line ", i, ": ", dumpLine(parsed)

  echo "\n--- Execution ---"
  eng3.clearOutput()
  for lineStr in miniLines:
    let parsed = parseLine(lineStr)
    discard eng3.execute(parsed)
  echo "Output:"
  echo eng3.output

  # Pattern H: FOR + DO + IF — ERIC loader LOADTH pattern
  echo "\n" & "=".repeat(60)
  echo "TEST: H: FOR + READ + QUIT:$ZEOF + DO (ERIC LOADTH)"
  echo "=".repeat(60)

  var g4 = newGlobals()
  registerAllSpecialVars(g4)
  var rt4 = newRuntime()
  var ev4 = newEvaluator(g4, rt4)
  var eng4 = newEngine(g4, ev4, rt4)

  let ericCode = "OPEN 1:(\"/tmp/eric_test/test_data.txt\":\"READ\") USE 1 READ HEADER SET COUNT=0\nFOR  READ LINE QUIT:$ZEOF  DO\n. SET NAME=$PIECE(LINE,\"|\",1)\n. SET COUNT=COUNT+1\nCLOSE 1 USE 0 WRITE \"Loaded:\",COUNT,!"
  echo "CODE (with line breaks):"
  echo ericCode
  echo "---"

  let ericLines = ericCode.split("\n")
  echo "\n--- AST Dump ---"
  for i, lineStr in ericLines:
    let parsed = parseLine(lineStr)
    echo "Line ", i, ": ", dumpLine(parsed)

  echo "\n--- Execution ---"
  eng4.clearOutput()
  for lineStr in ericLines:
    let parsed = parseLine(lineStr)
    discard eng4.execute(parsed)
  echo "Output:"
  echo eng4.output
  echo "NAME = \"", g4.get("NAME"), "\""
  echo "COUNT = \"", g4.get("COUNT"), "\""

when isMainModule:
  main()
