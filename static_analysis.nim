# static_analysis.nim — Static analysis for nimm (ZANALYZE)
# Detects unused variables, undefined variables, unreachable code

import strutils
import tables
import sequtils

type
  AnalysisResult* = object
    kind*: string       # "warning", "error", "info"
    line*: int
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

proc addResult*(report: var AnalysisReport, kind: string, line: int, column: int, message: string, code: string = "") =
  let r = AnalysisResult(kind: kind, line: line, column: column, message: message, code: code)
  report.results.add(r)
  case kind
  of "error": inc report.errorCount
  of "warning": inc report.warningCount
  of "info": inc report.infoCount
  else: discard

proc analyzeUnusedVariables*(lines: seq[string]): seq[AnalysisResult] =
  ## Detect variables that are set but never used
  result = @[]
  var defined: Table[string, seq[int]]  # variable -> [line numbers]
  var used: Table[string, bool]
  
  for i, line in lines:
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith(";"):
      continue
    
    # Find SET commands
    if trimmed.startsWith("SET ") or trimmed.startsWith("set "):
      let rest = trimmed[4..^1].strip()
      # Parse variable name (simplified)
      let eqPos = rest.find('=')
      if eqPos > 0:
        let varName = rest[0..<eqPos].strip()
        if varName.len > 0 and varName[0] in {'A'..'Z', 'a'..'z', '%'}:
          if varName notin defined:
            defined[varName] = @[]
          defined[varName].add(i)
    
    # Find variable references (simplified)
    for j in 0..<lines.len:
      let l = lines[j].strip()
      for varName in defined.keys:
        if l.contains(varName) and j != defined[varName][0]:
          used[varName] = true
  
  # Report unused variables
  for varName, lineNums in defined:
    if varName notin used:
      result.add(AnalysisResult(
        kind: "warning",
        line: lineNums[0] + 1,
        column: 0,
        message: "Variable '" & varName & "' is defined but never used",
        code: "W001"
      ))

proc analyzeUnreachableCode*(lines: seq[string]): seq[AnalysisResult] =
  ## Detect code after QUIT/GOTO that is unreachable
  result = @[]
  
  var i = 0
  while i < lines.len:
    let trimmed = lines[i].strip()
    
    # Check for unconditional QUIT or GOTO
    if trimmed == "QUIT" or trimmed == "quit":
      # Check if next line is a label, comment, or end
      if i + 1 < lines.len:
        let next = lines[i + 1].strip()
        if next.len > 0 and not next.startsWith(";"):
          # Check if it's a label (starts with letter/%)
          let isLabel = next[0] in {'A'..'Z', 'a'..'z', '%'}
          if not isLabel:
            result.add(AnalysisResult(
              kind: "warning",
              line: i + 2,
              column: 0,
              message: "Unreachable code after QUIT",
              code: "W002"
            ))
    
    inc i

proc analyzeUndefinedLabels*(lines: seq[string]): seq[AnalysisResult] =
  ## Detect references to undefined labels
  result = @[]
  
  # Collect defined labels
  var labels: Table[string, int]
  for i, line in lines:
    let trimmed = line.strip()
    if trimmed.len > 0 and trimmed[0] in {'A'..'Z', 'a'..'z', '%'}:
      var labelEnd = 0
      while labelEnd < trimmed.len and trimmed[labelEnd] in {'A'..'Z', 'a'..'z', '0'..'9', '%'}:
        inc labelEnd
      if labelEnd > 0:
        labels[trimmed[0..<labelEnd].toUpperAscii()] = i
  
  # Check DO and GOTO references
  for i, line in lines:
    let trimmed = line.strip()
    var labelRef = ""
    
    if trimmed.startsWith("DO ") or trimmed.startsWith("do "):
      labelRef = trimmed[3..^1].strip()
    elif trimmed.startsWith("GOTO ") or trimmed.startsWith("goto "):
      labelRef = trimmed[5..^1].strip()
    
    # Extract label name (before ^ or +)
    let caretPos = labelRef.find('^')
    let plusPos = labelRef.find('+')
    var endPos = labelRef.len
    if caretPos >= 0: endPos = min(endPos, caretPos)
    if plusPos >= 0: endPos = min(endPos, plusPos)
    
    let label = labelRef[0..<endPos].strip().toUpperAscii()
    
    if label.len > 0 and label notin labels:
      result.add(AnalysisResult(
        kind: "warning",
        line: i + 1,
        column: 0,
        message: "Label '" & label & "' not found in current routine",
        code: "W003"
      ))

proc analyzeRoutine*(code: string): AnalysisReport =
  ## Analyze M/MUMPS code and return report
  var report = newAnalysisReport()
  let lines = code.splitLines()
  
  # Check unused variables
  let unused = analyzeUnusedVariables(lines)
  for r in unused:
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  
  # Check unreachable code
  let unreachable = analyzeUnreachableCode(lines)
  for r in unreachable:
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  
  # Check undefined labels
  let undefined = analyzeUndefinedLabels(lines)
  for r in undefined:
    report.addResult(r.kind, r.line, r.column, r.message, r.code)
  
  return report

proc formatReport*(report: AnalysisReport): string =
  ## Format analysis report as string
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
