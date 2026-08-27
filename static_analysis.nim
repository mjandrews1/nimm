# static_analysis.nim — Static analysis for nimm (ZANALYZE / --lint)
# Detects unused variables, undefined/unused labels, unreachable code,
# and operator-precedence hazards.

import strutils
import tables
import parser  # isCommandKeyword for label-vs-command distinction

type
  AnalysisResult* = object
    kind*: string       # "warning", "error", "info"
    line*: int          # 1-based line number (0 = whole-routine)
    column*: int
    message*: string
    code*: string       # error code

  AnalysisReport* = object
    results*: seq[AnalysisResult]
    errorCount*: int
    warningCount*: int
    infoCount*: int

proc newAnalysisReport*(): AnalysisReport =
  result.results = @[]
  result.errorCount = 0
  result.warningCount = 0
  result.infoCount = 0

proc addResult*(report: var AnalysisReport, kind: string, line: int, column: int,
                message: string, code: string = "") =
  let r = AnalysisResult(kind: kind, line: line, column: column,
                         message: message, code: code)
  report.results.add(r)
  case kind
  of "error": inc report.errorCount
  of "warning": inc report.warningCount
  of "info": inc report.infoCount
  else: discard

# --- helpers -------------------------------------------------------------

proc stripComment(line: string): string =
  ## Strip a trailing `;` comment (first `;` not inside a quoted string).
  var inStr = false
  for i in 0..<line.len:
    if line[i] == '"': inStr = not inStr
    elif line[i] == ';' and not inStr:
      return line[0..<i]
  return line

proc leadingWord(line: string): string =
  ## First identifier token of a stripped line, or "".
  let t = line.strip()
  if t.len == 0: return ""
  if t[0] notin {'A'..'Z', 'a'..'z', '%', '0'..'9'}: return ""
  var i = 0
  var tok = ""
  if t[0] in {'A'..'Z', 'a'..'z', '%'}:
    while i < t.len and t[i] in {'A'..'Z', 'a'..'z', '0'..'9', '%', '_'}:
      tok.add(t[i]); inc i
  else:  # numeric label
    while i < t.len and t[i] in {'0'..'9'}:
      tok.add(t[i]); inc i
  if i < t.len and t[i] notin {' ', '\t', '('}: return ""
  return tok

proc isLabelLine(line: string): bool =
  ## True if the line's leading token is a label (identifier that is NOT a
  ## command keyword, terminated by whitespace/EOL/'(').
  let tok = leadingWord(line)
  return tok.len > 0 and not isCommandKeyword(tok)

proc collectLabels(lines: seq[string]): Table[string, int] =
  ## label name -> 0-based line index
  for i, line in lines:
    let t = stripComment(line)
    if t.strip().len == 0: continue
    let tok = leadingWord(t)
    if tok.len > 0 and not isCommandKeyword(tok):
      result[tok.toUpperAscii()] = i

# --- checks --------------------------------------------------------------

proc analyzeUnusedVariables(lines: seq[string]): seq[AnalysisResult] =
  ## W001 — variables SET but never referenced later.
  result = @[]
  var defined = initTable[string, seq[int]]()  # var -> line numbers
  var used = initTable[string, bool]()

  for i, line in lines:
    let t = stripComment(line).strip()
    if t.len == 0: continue
    # SET var=... (and S var=...)
    var rest = ""
    if t.startsWith("SET ") or t.startsWith("set "): rest = t[4..^1].strip()
    elif t.startsWith("S ") or t.startsWith("s "): rest = t[2..^1].strip()
    else: continue
    var name = ""
    for ch in rest:
      if ch == '=' or ch == '(' or ch == ' ': break
      name.add(ch)
    name = name.strip()
    if name.len > 0 and name[0] in {'A'..'Z', 'a'..'z', '%'}:
      if name notin defined: defined[name] = @[]
      defined[name].add(i)

  for varName, defLines in defined:
    # A variable is "used" if it appears on any other line as a bare word.
    for j, line in lines:
      if j in defLines: continue
      let t = stripComment(line)
      # crude word-boundary scan
      var k = 0
      while k < t.len:
        if t[k] in {'A'..'Z', 'a'..'z', '%', '0'..'9', '_'}:
          var w = ""
          while k < t.len and t[k] in {'A'..'Z', 'a'..'z', '%', '0'..'9', '_'}:
            w.add(t[k]); inc k
          if w == varName:
            used[varName] = true
            break
        else:
          inc k
      if used.getOrDefault(varName, false): break

  for varName, defLines in defined:
    if not used.getOrDefault(varName, false):
      result.add(AnalysisResult(
        kind: "warning", line: defLines[0] + 1, column: 0,
        message: "Variable '" & varName & "' is defined but never used",
        code: "W001"))

proc analyzeUnreachableCode(lines: seq[string]): seq[AnalysisResult] =
  ## W002 — code after an unconditional QUIT/GOTO that is not a label.
  result = @[]
  for i in 0..<lines.len:
    let t = stripComment(lines[i]).strip()
    if t == "QUIT" or t == "quit" or t == "GOTO" or t == "goto":
      if i + 1 < lines.len:
        let next = stripComment(lines[i + 1]).strip()
        if next.len > 0 and not isLabelLine(next):
          result.add(AnalysisResult(
            kind: "warning", line: i + 2, column: 0,
            message: "Unreachable code after " & t.toUpperAscii(),
            code: "W002"))
          # Stop after first (a single QUIT dominates the rest of the block)
          break

proc analyzeLabels(lines: seq[string]): seq[AnalysisResult] =
  ## W003 (undefined label) + W004 (unused label).
  result = @[]
  let labels = collectLabels(lines)

  # Collect DO/GOTO label references (crude: word after DO/GOTO)
  var refs = initTable[string, int]()  # label -> first referencing line
  for i, line in lines:
    let t = stripComment(line)
    var pos = 0
    while pos < t.len:
      # find "DO" or "GOTO" keyword boundary
      let doIdx = t.find("DO", pos)
      let goIdx = t.find("GOTO", pos)
      var idx = -1
      var kwLen = 0
      if doIdx >= 0 and (goIdx < 0 or doIdx < goIdx):
        idx = doIdx; kwLen = 2
      elif goIdx >= 0:
        idx = goIdx; kwLen = 4
      else:
        break
      # must be a word boundary
      let before = if idx > 0: t[idx - 1] else: ' '
      let after = if idx + kwLen < t.len: t[idx + kwLen] else: ' '
      if before in {' ', '\t', '('} and after in {' ', '\t'}:
        # read the label word after the keyword
        var k = idx + kwLen
        while k < t.len and t[k] in {' ', '\t'}: inc k
        var w = ""
        while k < t.len and t[k] in {'A'..'Z', 'a'..'z', '%', '0'..'9', '_'}:
          w.add(t[k]); inc k
        w = w.toUpperAscii()
        if w.len > 0 and w notin ["0", "1"]:  # DO 0 / DO 1? ignore numeric
          if w notin refs: refs[w] = i
      pos = idx + kwLen

  # W003 — referenced but undefined (skip intrinsic/common words)
  let common = ["QUIT", "RETURN"]
  for label, _ in refs:
    if label notin labels and label notin common:
      result.add(AnalysisResult(
        kind: "warning", line: refs[label] + 1, column: 0,
        message: "Label '" & label & "' not found in current routine",
        code: "W003"))

  # W004 — defined but never referenced (skip the entry-point label: the
  # first label is conventionally the routine's external entry, not dead).
  var entryLine = high(int)
  for _, lineIdx in labels:
    if lineIdx < entryLine: entryLine = lineIdx
  for label, lineIdx in labels:
    if label notin refs and lineIdx != entryLine:
      result.add(AnalysisResult(
        kind: "warning", line: lineIdx + 1, column: 0,
        message: "Label '" & label & "' is defined but never called",
        code: "W004"))

proc isBinarySign(t: string, j: int): bool =
  ## The +/- at index j is binary (not unary) if an operand precedes it.
  var k = j - 1
  while k >= 0 and t[k] in {' ', '\t'}: dec k
  if k < 0: return false
  return t[k] in {'0'..'9', 'A'..'Z', 'a'..'z', '%', ')', '"'}

proc analyzePrecedence(lines: seq[string]): seq[AnalysisResult] =
  ## W006 — binary + / - followed by * / in one expression.
  ## Left-to-right M evaluation differs from PEMDAS here.
  result = @[]
  for i, line in lines:
    let t = stripComment(line)
    var j = 0
    while j < t.len:
      if (t[j] == '+' or t[j] == '-') and isBinarySign(t, j):
        var k = j + 1
        while k < t.len:
          let c = t[k]
          if c == '*' or c == '/':
            result.add(AnalysisResult(
              kind: "info", line: i + 1, column: j + 1,
              message: "Mixed +- and */ precedence: M evaluates left-to-right, PEMDAS does not",
              code: "W006"))
            break
          if c == '=' or c == ',' or c == ';': break
          inc k
      inc j

proc analyzeLines*(lines: seq[string]): AnalysisReport =
  var report = newAnalysisReport()
  for r in analyzeUnusedVariables(lines):
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  for r in analyzeUnreachableCode(lines):
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  for r in analyzeLabels(lines):
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  for r in analyzePrecedence(lines):
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  return report

proc analyzeRoutine*(code: string): AnalysisReport =
  analyzeLines(code.splitLines())

proc formatReport*(report: AnalysisReport): string =
  result = ""
  for r in report.results:
    result.add(r.kind.toUpperAscii())
    if r.line > 0:
      result.add(":" & $r.line)
    if r.code.len > 0:
      result.add(" [" & r.code & "]")
    result.add(": " & r.message)
    result.add("\n")
  result.add("\nSummary: ")
  result.add($report.errorCount & " errors, ")
  result.add($report.warningCount & " warnings, ")
  result.add($report.infoCount & " info")
