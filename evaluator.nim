# evaluator.nim — Expression evaluator for nimm
# Evaluates M/MUMPS expressions using the AST from parser.nim

import strutils
import tables
import math
import random
import os
import ast
import globals
import value
import pattern
import unicode_utils
import ni_functions

type
  Evaluator* = object
    ## Expression evaluator
    globals*: ptr Globals
    mode*: string

proc newEvaluator*(globals: var Globals, mode: string = "nimm"): Evaluator =
  result.globals = globals.addr
  result.mode = mode

proc eval*(ev: var Evaluator, expr: Expr): string
proc callFunction*(ev: var Evaluator, name: string, args: seq[string]): string

proc eval*(ev: var Evaluator, expr: Expr): string =
  ## Evaluate an expression and return string result
  case expr.kind
  of numLit:
    return expr.sval
  of eStr:
    return expr.sval
  of eVar:
    var subs: seq[string] = @[]
    for sub in expr.subs:
      subs.add(ev.eval(sub))
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
      ev.globals[].set(varName, @[], $newVal)
      return $newVal
    var args: seq[string] = @[]
    for arg in expr.fargs:
      args.add(ev.eval(arg))
    return ev.callFunction(expr.fname, args)
  of eSvar:
    return ev.globals[].getSpecialVar("$" & expr.sname)
  of eNeg:
    let val = ev.eval(expr.operand)
    try:
      return $(-parseFloat(val))
    except:
      return "0"
  of eNot:
    let val = ev.eval(expr.operand)
    if val == "0" or val == "":
      return "1"
    return "0"
  of eBinary:
    let left = ev.eval(expr.left)
    let right = ev.eval(expr.right)
    case expr.op
    of bAdd:
      try: return $(parseFloat(left) + parseFloat(right))
      except: return "0"
    of bSub:
      try: return $(parseFloat(left) - parseFloat(right))
      except: return "0"
    of bMul:
      try: return $(parseFloat(left) * parseFloat(right))
      except: return "0"
    of bDiv:
      try:
        let r = parseFloat(right)
        if r == 0.0: return "0"
        return $(parseFloat(left) / r)
      except: return "0"
    of bIntDiv:
      try:
        let r = parseFloat(right)
        if r == 0.0: return "0"
        return $(int(parseFloat(left) / r))
      except: return "0"
    of bMod:
      try:
        let r = parseFloat(right)
        if r == 0.0: return "0"
        let l = parseFloat(left)
        return $(l - r * floor(l / r))
      except: return "0"
    of bPow:
      try: return $(pow(parseFloat(left), parseFloat(right)))
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
    if pos >= 0: return $(pos + 1)
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
        return formatFloat(num, ffDecimal, precision)
      except:
        return s
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
    return ev.globals[].orderLocal(args[0], @[], forward)
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
    if '+' in format and num >= 0:
      s = "+" & s
    elif 'P' in format and num < 0:
      s = "(" & s[1..^1] & ")"
    return s
  of "QUERY", "Q":
    if args.len < 1: return ""
    # $QUERY returns next subscripted variable in collation order
    # For local variables, use orderLocal
    let varName = args[0]
    let forward = if args.len > 1: parseInt(args[1]) >= 0 else: true
    return ev.globals[].orderLocal(varName, @[], forward)
  of "TEXT", "T":
    if args.len < 1: return ""
    # $TEXT returns a line of source code
    # Format: label+offset^routine
    # For now, return empty - needs runtime integration
    return ""
  of "ZSYSTEM", "ZSY":
    if args.len < 1: return ""
    return $execShellCmd(args[0])
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
  else:
    return ""

proc matchPattern*(s: string, atoms: seq[PatternAtom]): bool =
  var pos = 0
  for atom in atoms:
    var count = 0
    let maxCount = if atom.orMore: s.len - pos else: atom.count
    while count < maxCount and pos < s.len:
      if matchesCode(s[pos], atom.code):
        pos.inc
        count.inc
      else:
        break
    if count < atom.count:
      return false
  return pos == s.len
