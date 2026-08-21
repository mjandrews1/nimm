# evaluator.nim — Expression evaluator for nimm
# Evaluates M/MUMPS expressions using the AST from parser.nim

import strutils
import tables
import math
import random
import os
import times
import ast
import globals
import value
import pattern
import unicode_utils
import ni_functions
import data_structures
import runtime

type
  Evaluator* = object
    ## Expression evaluator
    globals*: ptr Globals
    runtime*: ptr Runtime
    mode*: string

# Global storage for data structures
var niArrays: Table[string, NiArray] = initTable[string, NiArray]()
var niObjects: Table[string, NiObject] = initTable[string, NiObject]()
var niStacks: Table[string, NiStack] = initTable[string, NiStack]()
var niQueues: Table[string, NiQueue] = initTable[string, NiQueue]()
var niSets: Table[string, NiSet] = initTable[string, NiSet]()
var niMaps: Table[string, NiMap] = initTable[string, NiMap]()
var niSorted: Table[string, NiSorted] = initTable[string, NiSorted]()
var niDeques: Table[string, NiDeque] = initTable[string, NiDeque]()
var niBags: Table[string, NiBag] = initTable[string, NiBag]()

# $ZDATETIME cache (keyed by horolog string, 1-second TTL)
var zdtCacheHorolog: string = ""
var zdtCacheYear, zdtCacheMonth, zdtCacheDay: int
var zdtCacheHour, zdtCacheMinute, zdtCacheSecond: int
var zdtCacheTime: int64 = 0

# $ZHOROLOG cache (1-second TTL)
var zhorologCache: string = ""
var zhorologCacheTime: int64 = 0

proc newEvaluator*(globals: var Globals, runtime: var Runtime, mode: string = "nimm"): Evaluator =
  result.globals = globals.addr
  result.runtime = runtime.addr
  result.mode = mode

proc eval*(ev: var Evaluator, expr: Expr): string
proc callFunction*(ev: var Evaluator, name: string, args: seq[string]): string

proc eval*(ev: var Evaluator, expr: Expr): string =
  ## Evaluate an expression and return string result
  case expr.kind
  of numLit:
    # Normalize number to canonical M form
    if expr.hasCachedFloat:
      return formatNumber(expr.cachedFloat)
    try:
      let v = parseFloat(expr.sval)
      return formatNumber(v)
    except:
      return expr.sval
  of eStr:
    return expr.sval
  of eVar:
    if expr.subs.len == 0:
      if expr.vname == "^":
        if ev.globals[].nakedGlobal.len == 0: return ""
        return ev.globals[].get(ev.globals[].nakedGlobal, ev.globals[].nakedSubs)
      return ev.globals[].getLocalDirect(expr.vname)
    var subs: seq[string] = @[]
    for sub in expr.subs:
      subs.add(ev.eval(sub))
    # Handle naked references: ^ with no name uses last global reference
    if expr.vname == "^":
      if ev.globals[].nakedGlobal.len == 0: return ""
      var allSubs = ev.globals[].nakedSubs
      for sub in subs:
        allSubs.add(sub)
      return ev.globals[].get(ev.globals[].nakedGlobal, allSubs)
    return ev.globals[].get(expr.vname, subs)
  of eFunc:
    # Special handling for functions that need variable references
    if expr.fname in ["INCREMENT", "INCR"]:
      # $INCREMENT needs the variable name, not its value
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      let increment = if expr.fargs.len > 1:
        parseFloat(ev.eval(expr.fargs[1]))
      else: 1.0
      let current = ev.globals[].get(varName)
      var num = 0.0
      try: num = parseFloat(current)
      except: discard
      let newVal = num + increment
      ev.globals[].set(varName, @[], formatNumber(newVal))
      return formatNumber(newVal)
    # Special handling for $GET — needs variable name, not value
    if expr.fname in ["GET", "G"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      let val = ev.globals[].get(varName)
      if val.len > 0: return val
      if expr.fargs.len > 1: return ev.eval(expr.fargs[1])
      return ""
    # Special handling for $DATA — needs variable name, not value
    if expr.fname in ["DATA", "D"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      var subs: seq[string] = @[]
      for sub in varExpr.subs:
        subs.add(ev.eval(sub))
      return $ev.globals[].data(varName, subs)
    # Special handling for $ORDER — needs variable reference, not value
    if expr.fname in ["ORDER", "O"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      var subs: seq[string] = @[]
      for sub in varExpr.subs:
        subs.add(ev.eval(sub))
      let forward = if expr.fargs.len > 1:
        parseInt(ev.eval(expr.fargs[1])) >= 0
      else: true
      return ev.globals[].order(varName, subs, forward)
    # Special handling for $ZORDER — forward traversal (alias for $ORDER)
    if expr.fname in ["ZORDER"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      var subs: seq[string] = @[]
      for sub in varExpr.subs:
        subs.add(ev.eval(sub))
      return ev.globals[].order(varName, subs, true)
    # Special handling for $ZPREVIOUS — backward traversal
    if expr.fname in ["ZPREVIOUS"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      var subs: seq[string] = @[]
      for sub in varExpr.subs:
        subs.add(ev.eval(sub))
      return ev.globals[].order(varName, subs, false)
    # Special handling for $QUERY — needs variable reference, not value
    # $QUERY returns the next node in the entire array (any depth), unlike $ORDER
    if expr.fname in ["QUERY", "Q"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      var subs: seq[string] = @[]
      for sub in varExpr.subs:
        subs.add(ev.eval(sub))
      let forward = if expr.fargs.len > 1:
        parseInt(ev.eval(expr.fargs[1])) >= 0
      else: true
      # Get the next node (any depth)
      let nextSubs = ev.globals[].query(varName, subs, forward)
      if nextSubs.len == 0: return ""
      # Construct full variable reference
      var result = varName & "("
      for i, sub in nextSubs:
        if i > 0: result.add(",")
        result.add(sub)
      result.add(")")
      return result
    var args = newSeq[string](expr.fargs.len)
    for i, arg in expr.fargs:
      args[i] = ev.eval(arg)
    return ev.callFunction(expr.fname, args)
  of eSvar:
    let sv = ev.globals[].getSpecialVar("$" & expr.sname)
    if sv.len > 0: return sv
    # If not found as special var, try as function (e.g. $ZHOROLOG)
    return ev.callFunction(expr.sname, @[])
  of eNeg:
    if expr.operand.kind == numLit and expr.operand.hasCachedFloat:
      return formatNumber(-expr.operand.cachedFloat)
    let val = ev.eval(expr.operand)
    try:
      return formatNumber(-parseFloat(val))
    except:
      return "0"
  of eNot:
    let val = ev.eval(expr.operand)
    if val == "0" or val == "":
      return "1"
    return "0"
  of eBinary:
    # Short-circuit evaluation for & (AND) and ! (OR)
    if expr.op == bAnd:
      let left = ev.eval(expr.left)
      if left == "0" or left == "":
        return "0"
      return ev.eval(expr.right)
    if expr.op == bOr:
      let left = ev.eval(expr.left)
      if left != "0" and left != "":
        return "1"
      return ev.eval(expr.right)
    let left = ev.eval(expr.left)
    let right = ev.eval(expr.right)
    case expr.op
    of bAdd:
      try: return formatNumber(parseFloat(left) + parseFloat(right))
      except: return "0"
    of bSub:
      try: return formatNumber(parseFloat(left) - parseFloat(right))
      except: return "0"
    of bMul:
      try: return formatNumber(parseFloat(left) * parseFloat(right))
      except: return "0"
    of bDiv:
      try:
        let r = parseFloat(right)
        if r == 0.0: return "0"
        return formatNumber(parseFloat(left) / r)
      except: return "0"
    of bIntDiv:
      try:
        let r = parseFloat(right)
        if r == 0.0: return "0"
        return formatNumber(float(int(parseFloat(left) / r)))
      except: return "0"
    of bMod:
      try:
        let r = parseFloat(right)
        if r == 0.0: return "0"
        let l = parseFloat(left)
        return formatNumber(l - r * floor(l / r))
      except: return "0"
    of bPow:
      try: return formatNumber(pow(parseFloat(left), parseFloat(right)))
      except: return "0"
    of bConcat:
      return left & right
    of bEql:
      try:
        if parseFloat(left) == parseFloat(right): return "1"
        return "0"
      except:
        if left == right: return "1"
        return "0"
    of bNeql:
      try:
        if parseFloat(left) != parseFloat(right): return "1"
        return "0"
      except:
        if left != right: return "1"
        return "0"
    of bLt:
      try:
        if parseFloat(left) < parseFloat(right): return "1"
        return "0"
      except:
        if left < right: return "1"
        return "0"
    of bGt:
      try:
        if parseFloat(left) > parseFloat(right): return "1"
        return "0"
      except:
        if left > right: return "1"
        return "0"
    of bNlt:
      try:
        if parseFloat(left) >= parseFloat(right): return "1"
        return "0"
      except:
        if left >= right: return "1"
        return "0"
    of bNgt:
      try:
        if parseFloat(left) <= parseFloat(right): return "1"
        return "0"
      except:
        if left <= right: return "1"
        return "0"
    of bFollows:
      if left > right: return "1"
      return "0"
    of bNotFollows:
      if left <= right: return "1"
      return "0"
    of bContains:
      if right in left: return "1"
      return "0"
    of bNotContains:
      if right notin left: return "1"
      return "0"
    of bAnd:
      if left != "0" and left != "" and right != "0" and right != "":
        return "1"
      return "0"
    of bOr:
      if (left != "0" and left != "") or (right != "0" and right != ""):
        return "1"
      return "0"
    of bSortAfter:
      if left > right: return "1"
      return "0"
  of ePattern:
    let lhs = ev.eval(expr.patLhs)
    if matchPattern(lhs, expr.atoms):
      return "1"
    return "0"
  of eIndirect:
    # Indirection: @expr — expr evaluates to a variable name
    let varName = ev.eval(expr.indirectExpr)
    if varName.len == 0: return ""
    # Evaluate subscripts if present
    var subs: seq[string] = @[]
    for sub in expr.indirectSubs:
      subs.add(ev.eval(sub))
    # Get the variable value
    return ev.globals[].get(varName, subs)

proc callFunction*(ev: var Evaluator, name: string, args: seq[string]): string =
  ## Call an intrinsic function
  case name
  of "ASCII", "A":
    if args.len < 1: return ""
    if args[0].len == 0: return ""
    return $int(uint8(args[0][0]))
  of "CHAR", "C":
    var result = ""
    for a in args:
      try: result.add(char(parseInt(a)))
      except: discard
    return result
  of "DATA", "D":
    if args.len < 1: return ""
    return $ev.globals[].data(args[0])
  of "EXTRACT", "E":
    if args.len < 1: return ""
    let s = args[0]
    if s.len == 0: return ""
    var start = 0
    var length = s.len
    if args.len > 1:
      try: start = parseInt(args[1]) - 1
      except: discard
    if args.len > 2:
      try: length = parseInt(args[2]) - start
      except: discard
    if start < 0: start = 0
    if start >= s.len: return ""
    let endIdx = min(start + length, s.len)
    return s[start..<endIdx]
  of "FIND", "F":
    if args.len < 2: return ""
    let s = args[0]
    let f = args[1]
    let start = if args.len > 2: parseInt(args[2]) else: 0
    let pos = s.find(f, start)
    if pos >= 0: return $(pos + f.len + 1)
    return "0"
  of "GET", "G":
    if args.len < 1: return ""
    let val = ev.globals[].get(args[0])
    if val.len > 0: return val
    if args.len > 1: return args[1]
    return ""
  of "JUSTIFY", "J":
    if args.len < 2: return ""
    let s = args[0]
    let width = parseInt(args[1])
    if args.len > 2:
      let precision = parseInt(args[2])
      try:
        let num = parseFloat(s)
        let formatted = formatFloat(num, ffDecimal, precision)
        return formatted.align(width)
      except:
        return s.align(width)
    else:
      return s.align(width)
  of "LENGTH", "L":
    if args.len < 1: return ""
    if args.len > 1:
      let s = args[0]
      let d = args[1]
      if d.len == 0: return $(s.len + 1)
      var count = 0
      var pos = 0
      while true:
        let found = s.find(d, pos)
        if found < 0: break
        count.inc
        pos = found + d.len
      return $(count + 1)
    return $args[0].len
  of "ORDER", "O":
    if args.len < 1: return ""
    let forward = if args.len > 1: parseInt(args[1]) >= 0 else: true
    return ev.globals[].order(args[0], @[], forward)
  of "PIECE", "P":
    if args.len < 2: return ""
    let s = args[0]
    let d = args[1]
    let start = if args.len > 2: parseInt(args[2]) else: 1
    let stop = if args.len > 3: parseInt(args[3]) else: start
    if d.len == 0: return s
    var pieces: seq[string] = @[]
    var current = ""
    for ch in s:
      if ch == d[0]:
        pieces.add(current)
        current = ""
      else:
        current.add(ch)
    pieces.add(current)
    var result = ""
    for i in start..stop:
      if i > 0 and i <= pieces.len:
        if result.len > 0: result.add(d)
        result.add(pieces[i - 1])
    return result
  of "RANDOM", "R":
    if args.len < 1: return "0"
    try:
      let n = parseInt(args[0])
      if n <= 0: return "0"
      return $(rand(n))
    except:
      return "0"
  of "REVERSE", "REV":
    if args.len < 1: return ""
    return utf8Reverse(args[0])
  of "SELECT", "SEL":
    # $SELECT(cond1:val1,cond2:val2,...) is flattened to [cond1, val1, cond2, val2, ...]
    var i = 0
    while i < args.len - 1:
      let cond = args[i]
      let val = args[i + 1]
      if cond != "0" and cond.len > 0:
        return val
      i += 2
    # If no condition matched, return last arg if odd number
    if args.len mod 2 == 1:
      return args[^1]
    return ""
  of "STACK", "ST":
    return $ev.globals[].scopeDepth()
  of "TRANSLATE", "TR":
    if args.len < 2: return args[0]
    let s = args[0]
    let fromChars = args[1]
    let toChars = if args.len > 2: args[2] else: ""
    var result = ""
    for ch in s:
      let pos = fromChars.find(ch)
      if pos >= 0:
        if pos < toChars.len:
          result.add(toChars[pos])
      else:
        result.add(ch)
    return result
  of "CASE", "CAS":
    # $CASE(expr, val1:result1, val2:result2, ..., :default)
    # Flattened to [expr, val1, result1, val2, result2, ...]
    if args.len < 3: return ""
    let expr = args[0]
    var i = 1
    while i < args.len - 1:
      let val = args[i]
      let res = args[i + 1]
      if expr == val:
        return res
      i += 2
    # Check for default (last arg if odd number after expr)
    if (args.len - 1) mod 2 == 1:
      return args[^1]
    return ""
  of "FNUMBER", "FN":
    if args.len < 1: return ""
    let num = parseFloat(args[0])
    let format = if args.len > 1: args[1] else: ""
    let precision = if args.len > 2: parseInt(args[2]) else: 0
    var s = ""
    if precision > 0:
      s = formatFloat(num, ffDecimal, precision)
    else:
      if num == float(int(num)):
        s = $int(num)
      else:
        s = $num
    # Apply sign
    if '+' in format and num >= 0:
      s = "+" & s
    elif 'P' in format and num < 0:
      s = "(" & s[1..^1] & ")"
    # Apply comma separator
    if ',' in format:
      # Split into integer and decimal parts
      let dotPos = s.find('.')
      var intPart: string
      var decPart: string
      if dotPos >= 0:
        intPart = s[0..<dotPos]
        decPart = s[dotPos..^1]
      else:
        intPart = s
        decPart = ""
      # Handle negative sign
      var sign = ""
      if intPart.startsWith("-"):
        sign = "-"
        intPart = intPart[1..^1]
      # Add commas
      var result = ""
      for i, ch in intPart:
        if i > 0 and (intPart.len - i) mod 3 == 0:
          result.add(',')
        result.add(ch)
      s = sign & result & decPart
    return s
  of "TEXT", "T":
    # $TEXT(label+offset^routine) - Returns source line
    if args.len < 1: return ""
    let spec = args[0]
    # Use runtime to get the source line
    if ev.runtime != nil:
      return ev.runtime[].getLine(spec)
    return ""
  # M Standard Name Functions
  of "NAME", "N":
    # $NAME(expr) — Returns canonical name of variable
    if args.len < 1: return ""
    # For now, return the argument as-is (basic implementation)
    return args[0]
  of "QLENGTH", "QL":
    # $QLENGTH(expr) — Returns number of subscripts in a qualified name
    if args.len < 1: return "0"
    let name = args[0]
    let openParen = name.find('(')
    if openParen < 0: return "0"
    let closeParen = name.rfind(')')
    if closeParen < 0: return "0"
    let subStr = name[openParen+1..<closeParen]
    if subStr.len == 0: return "0"
    # Count commas + 1
    var count = 1
    for ch in subStr:
      if ch == ',': count += 1
    return $count
  of "QSUBSCRIPT", "QS":
    # $QSUBSCRIPT(expr, n) — Returns nth subscript from a qualified name
    if args.len < 2: return ""
    let name = args[0]
    let n = parseInt(args[1])
    let openParen = name.find('(')
    if openParen < 0: return ""
    let closeParen = name.rfind(')')
    if closeParen < 0: return ""
    let subStr = name[openParen+1..<closeParen]
    if subStr.len == 0: return ""
    # Split by comma
    var subs: seq[string] = @[]
    var current = ""
    for ch in subStr:
      if ch == ',':
        subs.add(current)
        current = ""
      else:
        current.add(ch)
    subs.add(current)
    # Return nth subscript (1-based)
    if n >= 1 and n <= subs.len:
      return subs[n-1]
    return ""
  # RSM Math Functions
  of "ZABS":
    if args.len < 1: return ""
    try: return formatNumber(abs(parseFloat(args[0])))
    except: return "0"
  of "ZARCCOS":
    if args.len < 1: return ""
    try: return formatNumber(arccos(parseFloat(args[0])))
    except: return "0"
  of "ZARCSIN":
    if args.len < 1: return ""
    try: return formatNumber(arcsin(parseFloat(args[0])))
    except: return "0"
  of "ZARCTAN":
    if args.len < 1: return ""
    try: return formatNumber(arctan(parseFloat(args[0])))
    except: return "0"
  of "ZCOS":
    if args.len < 1: return ""
    try: return formatNumber(cos(parseFloat(args[0])))
    except: return "0"
  of "ZEXP":
    if args.len < 1: return ""
    try: return formatNumber(exp(parseFloat(args[0])))
    except: return "0"
  of "ZLN":
    if args.len < 1: return ""
    try: return formatNumber(ln(parseFloat(args[0])))
    except: return "0"
  of "ZPOWER":
    if args.len < 2: return ""
    try: return formatNumber(pow(parseFloat(args[0]), parseFloat(args[1])))
    except: return "0"
  of "ZSIN":
    if args.len < 1: return ""
    try: return formatNumber(sin(parseFloat(args[0])))
    except: return "0"
  of "ZSQRT":
    if args.len < 1: return ""
    try: return formatNumber(sqrt(parseFloat(args[0])))
    except: return "0"
  of "ZTAN":
    if args.len < 1: return ""
    try: return formatNumber(tan(parseFloat(args[0])))
    except: return "0"
  # RSM Date/Time/String Functions
  of "ZDATE":
    # $ZDATE(horolog) - Format date from $HOROLOG
    if args.len < 1: return ""
    let parts = args[0].split(",")
    if parts.len < 2: return ""
    try:
      let days = parseInt(parts[0])
      # Days since Dec 31, 1840
      let base = 693594  # Days from 0001-01-01 to 1840-12-31
      let totalDays = base + days
      # Simple date calculation
      var year = 1
      var dayOfYear = totalDays
      while true:
        let daysInYear = if year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0): 366 else: 365
        if dayOfYear <= daysInYear: break
        dayOfYear -= daysInYear
        year.inc
      let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
      var month = 1
      for md in monthDays:
        let daysInMonth = if month == 2 and year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0): 29 else: md
        if dayOfYear <= daysInMonth: break
        dayOfYear -= daysInMonth
        month.inc
      return $year & "-" & align($month, 2, '0') & "-" & align($dayOfYear, 2, '0')
    except:
      return ""
  of "ZTIME":
    # $ZTIME(horolog) - Format time from $HOROLOG
    if args.len < 1: return ""
    let parts = args[0].split(",")
    if parts.len < 2: return ""
    try:
      let seconds = parseInt(parts[1])
      let hours = seconds div 3600
      let minutes = (seconds mod 3600) div 60
      let secs = seconds mod 60
      return align($hours, 2, '0') & ":" & align($minutes, 2, '0') & ":" & align($secs, 2, '0')
    except:
      return ""
  of "ZHOROLOG":
    # $ZHOROLOG - Get current date/time in $HOROLOG format
    # Cache with 1-second TTL (same pattern as $HOROLOG)
    let now = getTime()
    let epochSec = now.toUnix()
    if epochSec == zhorologCacheTime and zhorologCache.len > 0:
      return zhorologCache
    let nowTime = times.now()
    # Days from 1840-12-31 to now
    let year = nowTime.year
    let month = nowTime.month.ord
    let day = nowTime.monthday
    var days = 0
    for y in 1840..<year:
      if y mod 4 == 0 and (y mod 100 != 0 or y mod 400 == 0):
        days += 366
      else:
        days += 365
    let monthDays = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    for m in 1..<month:
      days += monthDays[m]
      if m == 2 and year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0):
        days.inc
    days += day
    let seconds = nowTime.hour * 3600 + nowTime.minute * 60 + nowTime.second
    zhorologCache = $days & "," & $seconds
    zhorologCacheTime = epochSec
    return zhorologCache
  of "ZDATETIME":
    # $ZDATETIME(horolog, format) - Format $HOROLOG with format string
    # Format tokens: YYYY, YY, MM, DD, HH, MI, SS, 12h, AM, nn (AM/PM lowercase)
    if args.len < 1: return ""
    let horolog = args[0]
    let parts = horolog.split(",")
    if parts.len < 2: return ""
    var year, month, day, hour, minute, second: int
    try:
      let now = getTime()
      let epochSec = now.toUnix()
      if horolog == zdtCacheHorolog and epochSec == zdtCacheTime:
        year = zdtCacheYear
        month = zdtCacheMonth
        day = zdtCacheDay
        hour = zdtCacheHour
        minute = zdtCacheMinute
        second = zdtCacheSecond
      else:
        let days = parseInt(parts[0])
        let secs = parseInt(parts[1])
        # Convert days since 1840-12-31 to date
        let baseYear = 1840
        var remaining = days
        year = baseYear
        while true:
          let daysInYear = if year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0): 366 else: 365
          if remaining < daysInYear: break
          remaining -= daysInYear
          year.inc
        let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        month = 1
        for md in monthDays:
          let daysInMonth = if month == 2 and year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0): 29 else: md
          if remaining < daysInMonth: break
          remaining -= daysInMonth
          month.inc
        day = remaining + 1
        # Convert seconds to time
        hour = secs div 3600
        minute = (secs mod 3600) div 60
        second = secs mod 60
        # Update cache
        zdtCacheHorolog = horolog
        zdtCacheYear = year
        zdtCacheMonth = month
        zdtCacheDay = day
        zdtCacheHour = hour
        zdtCacheMinute = minute
        zdtCacheSecond = second
        zdtCacheTime = epochSec
    except:
      return ""
    # If no format string, return default ISO format
    if args.len < 2:
      return align($year, 4, '0') & "-" & align($month, 2, '0') & "-" & align($day, 2, '0') & " " &
             align($hour, 2, '0') & ":" & align($minute, 2, '0') & ":" & align($second, 2, '0')
    let fmt = args[1]
    var result = ""
    var i = 0
    while i < fmt.len:
      if i + 3 < fmt.len and fmt[i..i+3] == "YYYY":
        result.add(align($year, 4, '0'))
        i += 4
      elif i + 1 < fmt.len and fmt[i..i+1] == "YY":
        result.add(align($(year mod 100), 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "MM":
        result.add(align($month, 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "DD":
        result.add(align($day, 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "HH":
        result.add(align($hour, 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "MI":
        result.add(align($minute, 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "SS":
        result.add(align($second, 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "12":
        let h12 = if hour == 0: 12 elif hour > 12: hour - 12 else: hour
        result.add(align($h12, 2, '0'))
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "AM":
        result.add(if hour < 12: "AM" else: "PM")
        i += 2
      elif i + 1 < fmt.len and fmt[i..i+1] == "nn":
        result.add(if hour < 12: "am" else: "pm")
        i += 2
      else:
        result.add(fmt[i])
        i.inc
    return result
  of "ZCONVERT":
    # $ZCONVERT(expr, type) - Convert string case
    if args.len < 2: return args[0]
    let s = args[0]
    let t = args[1].toLowerAscii
    case t
    of "u": return s.toUpperAscii
    of "l": return s.toLowerAscii
    else: return s
  of "ZWIDTH":
    # $ZWIDTH(expr) - Get display width (simplified: just string length)
    if args.len < 1: return "0"
    return $args[0].len
  of "ZBIT":
    # $ZBIT(expr, bit) - Get bit value
    if args.len < 2: return "0"
    try:
      let n = parseInt(args[0])
      let b = parseInt(args[1])
      if (n and (1 shl b)) != 0: return "1"
      return "0"
    except:
      return "0"
  of "ZSYSTEM", "ZSY":
    if args.len < 1: return ""
    return $execShellCmd(args[0])
  of "ZSTRIP":
    # $ZSTRIP(string, code) - Strip characters
    # Codes: "<" = leading, ">" = trailing, "*" = both
    # Optional third arg = specific characters to strip (default: whitespace)
    if args.len < 2: return args[0]
    let s = args[0]
    let code = args[1].toUpperAscii
    let charsToStrip = if args.len > 2: args[2] else: " \t\r\n"
    var stripLeading = false
    var stripTrailing = false
    for ch in code:
      case ch
      of '<': stripLeading = true
      of '>': stripTrailing = true
      of '*': stripLeading = true; stripTrailing = true
      else: discard
    if not stripLeading and not stripTrailing: return s
    var start = 0
    var finish = s.len
    if stripLeading:
      while start < finish and s[start] in charsToStrip:
        start.inc
    if stripTrailing:
      while finish > start and s[finish - 1] in charsToStrip:
        finish.dec
    return s[start..<finish]
  of "ZSUBSTR":
    # $ZSUBSTR(string, start [, length]) - Extract substring (1-based)
    if args.len < 2: return ""
    let s = args[0]
    let startPos = parseInt(args[1])
    let length = if args.len > 2: parseInt(args[2]) else: s.len - startPos + 1
    if startPos < 1 or startPos > s.len: return ""
    let startIdx = startPos - 1  # M is 1-based
    let ending = min(startIdx + length, s.len)
    if startIdx >= ending: return ""
    return s[startIdx..<ending]
  of "ZPIECE":
    # $ZPIECE(string, delimiter, from [, to]) - Same as $PIECE
    if args.len < 3: return ""
    let s = args[0]
    let d = args[1]
    let start = parseInt(args[2])
    let stop = if args.len > 3: parseInt(args[3]) else: start
    if d.len == 0: return s
    var pieces: seq[string] = @[]
    var current = ""
    for ch in s:
      if ch == d[0]:
        pieces.add(current)
        current = ""
      else:
        current.add(ch)
    pieces.add(current)
    var result = ""
    for i in start..stop:
      if i > 0 and i <= pieces.len:
        if result.len > 0: result.add(d)
        result.add(pieces[i - 1])
    return result
  of "NI_HTTP":
    # $NI_HTTP(method, url, body) — HTTP client
    if args.len < 2: return ""
    let httpMethod = args[0]
    let url = args[1]
    let body = if args.len > 2: args[2] else: ""
    return niHttp(httpMethod, url, body)
  of "NI_JSON":
    # $NI_JSON(action, data) — JSON parse/stringify
    if args.len < 2: return ""
    let action = args[0]
    let data = args[1]
    return niJson(action, data)
  of "NI_UUID":
    # $NI_UUID — Generate UUID v4
    return niUuid()
  of "NI_SLEEP":
    # $NI_SLEEP(seconds) — Sleep
    if args.len < 1: return ""
    try:
      niSleep(parseFloat(args[0]))
    except:
      discard
    return ""
  of "NI_ARRAY":
    # $NI_ARRAY(action, id, ...) — Array operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niArrays[id] = newArray()
      return id
    of "add":
      if args.len < 3: return ""
      if id notin niArrays: return ""
      niArrays[id].add(args[2])
      return $niArrays[id].len
    of "get":
      if args.len < 3: return ""
      if id notin niArrays: return ""
      try:
        return niArrays[id].get(parseInt(args[2]))
      except:
        return ""
    of "set":
      if args.len < 4: return ""
      if id notin niArrays: return ""
      try:
        niArrays[id].set(parseInt(args[2]), args[3])
        return "1"
      except:
        return "0"
    of "len":
      if id notin niArrays: return "0"
      return $niArrays[id].len
    of "clear":
      if id notin niArrays: return ""
      niArrays[id].clear()
      return "1"
    of "destroy":
      if id in niArrays:
        niArrays.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_OBJECT":
    # $NI_OBJECT(action, id, ...) — Object operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niObjects[id] = newObject()
      return id
    of "set":
      if args.len < 4: return ""
      if id notin niObjects: return ""
      niObjects[id].set(args[2], args[3])
      return "1"
    of "get":
      if args.len < 3: return ""
      if id notin niObjects: return ""
      return niObjects[id].get(args[2])
    of "has":
      if args.len < 3: return ""
      if id notin niObjects: return "0"
      if niObjects[id].has(args[2]): return "1"
      return "0"
    of "del":
      if args.len < 3: return ""
      if id notin niObjects: return ""
      niObjects[id].del(args[2])
      return "1"
    of "len":
      if id notin niObjects: return "0"
      return $niObjects[id].len
    of "clear":
      if id notin niObjects: return ""
      niObjects[id].clear()
      return "1"
    of "destroy":
      if id in niObjects:
        niObjects.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_STACK":
    # $NI_STACK(action, id, ...) — Stack operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niStacks[id] = newStack()
      return id
    of "push":
      if args.len < 3: return ""
      if id notin niStacks: return ""
      niStacks[id].push(args[2])
      return $niStacks[id].len
    of "pop":
      if id notin niStacks: return ""
      return niStacks[id].pop()
    of "peek":
      if id notin niStacks: return ""
      return niStacks[id].peek()
    of "len":
      if id notin niStacks: return "0"
      return $niStacks[id].len
    of "destroy":
      if id in niStacks:
        niStacks.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_QUEUE":
    # $NI_QUEUE(action, id, ...) — Queue operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niQueues[id] = newQueue()
      return id
    of "enqueue", "push":
      if args.len < 3: return ""
      if id notin niQueues: return ""
      niQueues[id].enqueue(args[2])
      return $niQueues[id].len
    of "dequeue", "pop":
      if id notin niQueues: return ""
      return niQueues[id].dequeue()
    of "peek":
      if id notin niQueues: return ""
      return niQueues[id].peek()
    of "len":
      if id notin niQueues: return "0"
      return $niQueues[id].len
    of "destroy":
      if id in niQueues:
        niQueues.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_SET":
    # $NI_SET(action, id, ...) — Set operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niSets[id] = newSet()
      return id
    of "add":
      if args.len < 3: return ""
      if id notin niSets: return ""
      niSets[id].add(args[2])
      return $niSets[id].len
    of "has", "contains":
      if args.len < 3: return ""
      if id notin niSets: return "0"
      if niSets[id].contains(args[2]): return "1"
      return "0"
    of "del", "remove":
      if args.len < 3: return ""
      if id notin niSets: return ""
      niSets[id].remove(args[2])
      return "1"
    of "len":
      if id notin niSets: return "0"
      return $niSets[id].len
    of "destroy":
      if id in niSets:
        niSets.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_MAP":
    # $NI_MAP(action, id, ...) — Map operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niMaps[id] = newMap()
      return id
    of "set":
      if args.len < 4: return ""
      if id notin niMaps: return ""
      niMaps[id].set(args[2], args[3])
      return "1"
    of "get":
      if args.len < 3: return ""
      if id notin niMaps: return ""
      return niMaps[id].get(args[2])
    of "has":
      if args.len < 3: return ""
      if id notin niMaps: return "0"
      if niMaps[id].has(args[2]): return "1"
      return "0"
    of "del":
      if args.len < 3: return ""
      if id notin niMaps: return ""
      niMaps[id].del(args[2])
      return "1"
    of "len":
      if id notin niMaps: return "0"
      return $niMaps[id].len
    of "keys":
      if id notin niMaps: return ""
      return niMaps[id].keys().join(",")
    of "values":
      if id notin niMaps: return ""
      return niMaps[id].values().join(",")
    of "destroy":
      if id in niMaps:
        niMaps.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_SORTED":
    # $NI_SORTED(action, id, ...) — Sorted collection operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niSorted[id] = newSorted()
      return id
    of "add":
      if args.len < 3: return ""
      if id notin niSorted: return ""
      niSorted[id].add(args[2])
      return $niSorted[id].len
    of "has", "contains":
      if args.len < 3: return ""
      if id notin niSorted: return "0"
      if niSorted[id].contains(args[2]): return "1"
      return "0"
    of "del", "remove":
      if args.len < 3: return ""
      if id notin niSorted: return ""
      niSorted[id].remove(args[2])
      return "1"
    of "len":
      if id notin niSorted: return "0"
      return $niSorted[id].len
    of "toseq", "toSeq":
      if id notin niSorted: return ""
      return niSorted[id].toSeq().join(",")
    of "destroy":
      if id in niSorted:
        niSorted.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_DEQUE":
    # $NI_DEQUE(action, id, ...) — Deque operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niDeques[id] = newDeque()
      return id
    of "addfirst", "pushfirst":
      if args.len < 3: return ""
      if id notin niDeques: return ""
      niDeques[id].pushFront(args[2])
      return $niDeques[id].len
    of "addlast", "pushlast":
      if args.len < 3: return ""
      if id notin niDeques: return ""
      niDeques[id].pushBack(args[2])
      return $niDeques[id].len
    of "popfirst":
      if id notin niDeques: return ""
      return niDeques[id].popFront()
    of "poplast":
      if id notin niDeques: return ""
      return niDeques[id].popBack()
    of "peekfirst":
      if id notin niDeques: return ""
      return niDeques[id].peekFront()
    of "peeklast":
      if id notin niDeques: return ""
      return niDeques[id].peekBack()
    of "len":
      if id notin niDeques: return "0"
      return $niDeques[id].len
    of "destroy":
      if id in niDeques:
        niDeques.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_BAG":
    # $NI_BAG(action, id, ...) — Bag (multiset) operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niBags[id] = newBag()
      return id
    of "add":
      if args.len < 3: return ""
      if id notin niBags: return ""
      niBags[id].add(args[2])
      return $niBags[id].count(args[2])
    of "count":
      if args.len < 3: return ""
      if id notin niBags: return "0"
      return $niBags[id].count(args[2])
    of "del", "remove":
      if args.len < 3: return ""
      if id notin niBags: return ""
      niBags[id].remove(args[2])
      return "1"
    of "len":
      if id notin niBags: return "0"
      return $niBags[id].len
    of "destroy":
      if id in niBags:
        niBags.del(id)
        return "1"
      return "0"
    else:
      return ""
  else:
    return ""
