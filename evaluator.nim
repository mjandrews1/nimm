# evaluator.nim — Expression evaluator for nimm
# Evaluates M/MUMPS expressions using the AST from parser.nim

import strutils
import tables
import math
import random
import os
import osproc
import times
import posix
import ast
import globals
import value
import pattern
import unicode_utils
import ni_functions
import data_structures
import runtime
import parser
import lexer
import inspector
import special_vars

# Shared empty seq — avoids @[] allocation on every bare variable access (#313)
const emptySubs: seq[string] = @[]

type
  Evaluator* = object
    ## Expression evaluator
    globals*: ptr Globals
    runtime*: ptr Runtime
    inspector*: ptr Inspector

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
var niHeaps: Table[string, NiHeap] = initTable[string, NiHeap]()
var niRings: Table[string, NiRing] = initTable[string, NiRing]()
var niLrus: Table[string, NiLRU] = initTable[string, NiLRU]()
var niBitSets: Table[string, NiBitSet] = initTable[string, NiBitSet]()
var niTries: Table[string, NiTrie] = initTable[string, NiTrie]()
var niGraphs: Table[string, NiGraph] = initTable[string, NiGraph]()
var niMatrices: Table[string, NiMatrix] = initTable[string, NiMatrix]()
var niBlooms: Table[string, NiBloom] = initTable[string, NiBloom]()
var niSkipLists: Table[string, NiSkipList] = initTable[string, NiSkipList]()
var niTreaps: Table[string, NiTreap] = initTable[string, NiTreap]()
var niDisjointSets: Table[string, NiDisjointSet] = initTable[string, NiDisjointSet]()
var niSegTrees: Table[string, NiSegmentTree] = initTable[string, NiSegmentTree]()
var niFenwicks: Table[string, NiFenwickTree] = initTable[string, NiFenwickTree]()
var niSparse: Table[string, NiSparseMatrix] = initTable[string, NiSparseMatrix]()
var niIntervals: Table[string, NiIntervalTree] = initTable[string, NiIntervalTree]()
var niSuffixes: Table[string, NiSuffixArray] = initTable[string, NiSuffixArray]()
var niWavelets: Table[string, NiWaveletTree] = initTable[string, NiWaveletTree]()
var niKdTrees: Table[string, NiKdTree] = initTable[string, NiKdTree]()
var niRopes: Table[string, NiRope] = initTable[string, NiRope]()
var niMerkles: Table[string, NiMerkleTree] = initTable[string, NiMerkleTree]()

# $ZDATETIME cache (keyed by horolog string, 1-second TTL)
var zdtCacheHorolog: string = ""
var zdtCacheYear, zdtCacheMonth, zdtCacheDay: int
var zdtCacheHour, zdtCacheMinute, zdtCacheSecond: int
var zdtCacheTime: int64 = 0

# $ZHOROLOG cache (1-second TTL)
var zhorologCache: string = ""
var zhorologCacheTime: int64 = 0

proc newEvaluator*(globals: var Globals, runtime: var Runtime): Evaluator =
  result.globals = globals.addr
  result.runtime = runtime.addr

proc setInspector*(ev: var Evaluator, insp: var Inspector) =
  ## Wire inspector to evaluator for function call tracking
  ev.inspector = insp.addr

# Recursion depth tracking for stack overflow prevention
var evalDepth: int = 0
const MaxEvalDepth = 500

proc eval*(ev: var Evaluator, expr: Expr): string
proc callFunction*(ev: var Evaluator, name: string, args: seq[string]): string

proc eval*(ev: var Evaluator, expr: Expr): string =
  ## Evaluate an expression and return string result
  inc evalDepth
  if evalDepth > MaxEvalDepth:
    dec evalDepth
    return "0"
  defer: dec evalDepth
  case expr.kind
  of numLit:
    # Normalize number to canonical M form
    # For large integers (>2^53), preserve original string to avoid
    # float64 precision loss (#338)
    if expr.hasCachedFloat:
      if abs(expr.cachedFloat) >= 9007199254740992.0 and expr.sval.len > 0:
        # Check if original string is a pure integer (no decimal, no exponent)
        let s = expr.sval
        var isPureInt = true
        for ch in s:
          if ch notin {'0'..'9', '-', '+'}:
            isPureInt = false
            break
        if isPureInt:
          return s
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
      if expr.vname.startsWith("^"):
        return ev.globals[].get(expr.vname, emptySubs)
      return ev.globals[].getLocalDirect(expr.vname)
    var subs: seq[string] = @[]
    for sub in expr.subs:
      subs.add(ev.eval(sub))
    # Handle naked references: ^ with no name uses last global reference.
    # §2.4.2: the provided subscripts REPLACE the final subscript of the
    # previous reference: after ^G(1,2), ^(3) designates ^G(1,3).
    if expr.vname == "^":
      if ev.globals[].nakedGlobal.len == 0: return ""
      var allSubs =
        if ev.globals[].nakedSubs.len > 0:
          ev.globals[].nakedSubs[0 ..< ^1]
        else:
          @[]
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
      ev.globals[].set(varName, emptySubs, formatNumber(newVal))
      return formatNumber(newVal)
    # Special handling for $GET — needs variable name, not value.
    # ISO §8.4.2: returns the node's value if defined, else the caller's
    # default, else the empty string. A node with descendants but no own
    # value is undefined-for-value purposes (#286; "0" is a $DATA code).
    # Subscripts must be honored — $GET(^G(1)) tests node ^G(1), never
    # the ^G root (#281).
    if expr.fname in ["GET", "G"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      var varName: string
      var subs: seq[string] = @[]
      if varExpr.kind == eVar:
        varName = varExpr.vname
        for sub in varExpr.subs:
          subs.add(ev.eval(sub))
      elif varExpr.kind == eIndirect:
        # $GET(@A(1)) — evaluate indirection to get var name
        varName = ev.eval(varExpr.indirectExpr)
        for sub in varExpr.indirectSubs:
          subs.add(ev.eval(sub))
      else:
        return ""
      let val = ev.globals[].get(varName, subs)
      if val.len > 0: return val
      if expr.fargs.len > 1: return ev.eval(expr.fargs[1])
      return ""
    # Special handling for $DATA — needs variable name, not value
    if expr.fname in ["DATA", "D"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      var varName: string
      var subs: seq[string] = @[]
      if varExpr.kind == eVar:
        varName = varExpr.vname
        for sub in varExpr.subs:
          subs.add(ev.eval(sub))
      elif varExpr.kind == eIndirect:
        varName = ev.eval(varExpr.indirectExpr)
        for sub in varExpr.indirectSubs:
          subs.add(ev.eval(sub))
      else:
        return ""
      return $ev.globals[].data(varName, subs)
    # Special handling for $ORDER — needs variable reference, not value.
    # The form $ORDER(A("",-1)) is ambiguous: grammatically -1 is a second
    # subscript, but convention (and the reference implementations this
    # suite mirrors) reads a trailing numeric-literal subscript as the
    # direction argument, so we pop it off.
    if expr.fname in ["ORDER", "O"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      var varName: string
      var subExprs: seq[Expr] = @[]
      if varExpr.kind == eVar:
        varName = varExpr.vname
        subExprs = varExpr.subs
      elif varExpr.kind == eIndirect:
        # $ORDER(@GLOB@(ID)) — evaluate indirection to get var name (#359)
        varName = ev.eval(varExpr.indirectExpr)
        subExprs = varExpr.indirectSubs
      else:
        return ""
      var hasDir = false
      var dirVal = 0
      if expr.fargs.len == 1 and subExprs.len > 0:
        let lastSub = subExprs[^1]
        # Only a NEGATIVE literal can be a direction argument; a positive
        # literal (e.g. $ORDER(A(1))) is just a plain subscript.
        if lastSub.kind == eNeg and lastSub.operand.kind == numLit:
          dirVal = -parseInt(lastSub.operand.sval)
          hasDir = true
          subExprs = subExprs[0 ..< ^1]
      var subs: seq[string] = @[]
      for sub in subExprs:
        subs.add(ev.eval(sub))
      let forward = if expr.fargs.len > 1:
        parseInt(ev.eval(expr.fargs[1])) >= 0
      elif hasDir:
        dirVal >= 0
      else: true
      return ev.globals[].order(varName, subs, forward)
    # Special handling for $ZORDER — forward traversal (alias for $ORDER)
    if expr.fname in ["ZORDER"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      var varName: string
      var subs: seq[string] = @[]
      if varExpr.kind == eVar:
        varName = varExpr.vname
        for sub in varExpr.subs:
          subs.add(ev.eval(sub))
      elif varExpr.kind == eIndirect:
        varName = ev.eval(varExpr.indirectExpr)
        for sub in varExpr.indirectSubs:
          subs.add(ev.eval(sub))
      else:
        return ""
      return ev.globals[].order(varName, subs, true)
    # Special handling for $ZPREVIOUS — backward traversal
    if expr.fname in ["ZPREVIOUS"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      if varExpr.kind != eVar: return ""
      let varName = varExpr.vname
      var subExprs = varExpr.subs
      # Same trailing-literal-as-direction convention as $ORDER;
      # only negative literals are directions, and $ZPREVIOUS is
      # inherently backward so they are simply dropped.
      if expr.fargs.len == 1 and subExprs.len > 0:
        let lastSub = subExprs[^1]
        if lastSub.kind == eNeg and lastSub.operand.kind == numLit:
          subExprs = subExprs[0 ..< ^1]
      var subs: seq[string] = @[]
      for sub in subExprs:
        subs.add(ev.eval(sub))
      return ev.globals[].order(varName, subs, false)
    # Special handling for $QUERY — needs variable reference, not value
    # $QUERY returns the next node in the entire array (any depth), unlike $ORDER
    if expr.fname in ["QUERY", "Q"]:
      if expr.fargs.len < 1: return ""
      let varExpr = expr.fargs[0]
      var varName = ""
      var subs: seq[string] = @[]
      if varExpr.kind == eVar:
        varName = varExpr.vname
        for sub in varExpr.subs:
          subs.add(ev.eval(sub))
      else:
        # Argument may be a computed reference such as $QUERY($QUERY(^G("")))
        # evaluating to a string like "^G(1,2)"; parse it back apart.
        let s = ev.eval(varExpr)
        if s.len == 0: return ""
        let lp = s.find('(')
        if lp < 0:
          varName = s
        else:
          varName = s[0 ..< lp]
          let inner = s[(lp+1)..^1].strip()
          if inner.len > 1 and inner[^1] == ')':
            for part in inner[0 ..< ^1].split(','):
              subs.add(part.strip())
      let forward = if expr.fargs.len > 1:
        parseInt(ev.eval(expr.fargs[1])) >= 0
      else: true
      # Get the next node (any depth)
      let nextSubs = ev.globals[].query(varName, subs, forward)
      if nextSubs.len == 0: return ""
      # Update the naked indicator to the found reference (§8.5.4)
      if varName.len > 0 and varName[0] == '^':
        ev.globals[].setNaked(varName, nextSubs)
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
    return formatNumber(-numPrefix(val))
  of ePos:
    # Unary plus — full numeric coercion per RSM/RFC consensus (#280):
    # +"2E3"→"2000", +"01.50"→"1.5", +".5"→".5", +"abc"→"0".
    # Lowercase 'e' is NOT an exponent (refs: +"1e2"→"1").
    if expr.operand.kind == numLit and expr.operand.hasCachedFloat:
      return formatNumber(expr.operand.cachedFloat)
    return formatNumber(numPrefix(ev.eval(expr.operand)))
  of eNot:
    let val = ev.eval(expr.operand)
    if truthy(val):
      return "0"
    return "1"
  of eBinary:
    # Short-circuit evaluation for & (AND) and ! (OR)
    if expr.op == bAnd:
      let left = ev.eval(expr.left)
      if not truthy(left):
        return "0"
      if truthy(ev.eval(expr.right)):
        return "1"
      return "0"
    if expr.op == bOr:
      let left = ev.eval(expr.left)
      if truthy(left):
        return "1"
      if truthy(ev.eval(expr.right)):
        return "1"
      return "0"
    let left = ev.eval(expr.left)
    let right = ev.eval(expr.right)
    # §2.2.2: operands coerce by longest leading numeric prefix — strict
    # parseFloat discarded whole expressions on any non-numeric operand (#284).
    case expr.op
    of bAdd:
      return formatNumber(numPrefix(left) + numPrefix(right))
    of bSub:
      return formatNumber(numPrefix(left) - numPrefix(right))
    of bMul:
      return formatNumber(numPrefix(left) * numPrefix(right))
    of bDiv:
      let r = numPrefix(right)
      if r == 0.0: return "0"
      return formatNumber(numPrefix(left) / r)
    of bIntDiv:
      let r = numPrefix(right)
      if r == 0.0: return "0"
      return formatNumber(float(int(numPrefix(left) / r)))
    of bMod:
      let r = numPrefix(right)
      if r == 0.0: return "0"
      let l = numPrefix(left)
      return formatNumber(l - r * floor(l / r))
    of bPow:
      return formatNumber(pow(numPrefix(left), numPrefix(right)))
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
    # Indirection: @expr — per ISO §7.4 the evaluated text replaces the
    # @-reference syntactically. The text may name a variable OR be a full
    # expression ("1+2", "B+1", "$L(B)") — re-parse and evaluate (#279).
    # Falls back to plain variable lookup when the text does not parse.
    let varName = ev.eval(expr.indirectExpr)
    if varName.len == 0: return ""
    # Evaluate subscripts if present
    var subs: seq[string] = @[]
    for sub in expr.indirectSubs:
      subs.add(ev.eval(sub))
    # Try expression indirection first — but if subscripts are present,
    # apply them to the resolved variable name (#359 bm25idx.m @GLOB@(ID))
    try:
      var p = newParser(varName)
      let inner = p.parseExpr()
      if subs.len > 0 and inner.kind == eVar:
        # @A(1) where A="X" or A="^X" — apply outer subscripts
        return ev.globals[].get(inner.vname, subs)
      return ev.eval(inner)
    except CatchableError:
      discard
    # Fallback — treat the text as a variable name
    return ev.globals[].get(varName, subs)
  of eEntryRef:
    # Entry references (label^routine) are only meaningful in DO/GOTO/ZGOTO
    # command handlers — not evaluatable as expressions. Return the label.
    return expr.entryLabel

proc callFunction*(ev: var Evaluator, name: string, args: seq[string]): string =
  ## Call an intrinsic function
  # Record function call for introspection
  if ev.inspector != nil:
    ev.inspector[].recordFunctionCall()
  case name
  of "ASCII", "A":
    if args.len < 1: return "-1"
    let s = args[0]
    if s.len == 0: return "-1"
    var pos = 1
    if args.len > 1:
      try: pos = parseInt(args[1])
      except: return "-1"
    if pos < 1 or pos > s.len: return "-1"
    return $int(uint8(s[pos - 1]))
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
    if args.len == 1:
      return $s[0]
    var first = 0
    var last = -1
    try: first = parseInt(args[1])
    except: discard
    if args.len > 2:
      try: last = parseInt(args[2])
      except: last = first
    if args.len < 3: last = first
    if first < 1: first = 1
    if last > s.len: last = s.len
    if last < first: return ""
    if first > s.len: return ""
    return s[(first - 1)..<last]
  of "FIND", "F":
    if args.len < 2: return ""
    let s = args[0]
    let f = args[1]
    var start = 0
    if args.len > 2:
      try: start = parseInt(args[2]) - 1
      except: start = 0
    if start < 0: start = 0
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
    if width < 0:
      # Reference behavior (RSM/RFC consensus): negative width returns the
      # string unchanged rather than ISO-style left-justify.
      return s
    if args.len > 2:
      # §9.7: decimals present → convert to numeric first ("zz9" → 0.0) (#285)
      let precision = parseInt(args[2])
      let formatted = formatFloat(numPrefix(s), ffDecimal, precision)
      return formatted.align(width)
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
    if start <= 0 or stop < start: return ""
    # Fast path: single piece extraction via find (#323)
    if start == stop:
      var pieceStart = 0
      var pieceNum = 1
      while pieceNum < start and pieceStart < s.len:
        let pos = s.find(d, pieceStart)
        if pos < 0: return ""
        pieceStart = pos + d.len
        inc pieceNum
      if pieceStart >= s.len and start > pieceNum: return ""
      let pieceEnd = s.find(d, pieceStart)
      if pieceEnd < 0: return s[pieceStart..^1]
      return s[pieceStart..<pieceEnd]
    # Multi-piece: split and join
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
      # §9.11: uniform integer in [0,n) — Nim's rand(n) is inclusive
      return $(rand(n - 1))
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
      if truthy(cond):
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
    # $NAME(expr) — Returns canonical name of variable (§9.8.1)
    if args.len < 1: return ""
    # Canonicalize: uppercase, preserve subscripts
    let name = args[0]
    let openParen = name.find('(')
    if openParen < 0:
      return name.toUpperAscii()
    let base = name[0..<openParen].toUpperAscii()
    let subs = name[openParen..^1]
    return base & subs
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
    # Return nth subscript (1-based), stripped of surrounding quotes;
    # M string subscripts arrive with their delimiters and doubled quotes.
    if n >= 1 and n <= subs.len:
      var val = subs[n-1]
      if val.len >= 2 and val[0] == '"' and val[^1] == '"':
        val = val[1 ..< ^1].replace("\"\"", "\"")
      return val
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
    of "t", "w":
      # Title case: uppercase the first letter of each word. "t" leaves the
      # rest of each word unchanged; "w" also lowercases the rest.
      var r = s
      var inWord = false
      for i in 0..<r.len:
        let ch = r[i]
        if ch.isAlphaAscii:
          if not inWord:
            r[i] = ch.toUpperAscii
            inWord = true
          elif t == "w":
            r[i] = ch.toLowerAscii
        else:
          inWord = false
      return r
    of "m": return s  # M collation — identity for now
    else: return s
  of "ZWIDTH":
    # $ZWIDTH(expr) — Get display width (§9.16.7)
    # Counts visible characters, skipping control characters
    if args.len < 1: return "0"
    let s = args[0]
    var width = 0
    for ch in s:
      let code = ord(ch)
      if code >= 32 and code != 127:  # Skip control chars and DEL
        width += 1
    return $width
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
  of "ZFILE":
    # $ZFILE(path[, "exists"]) — file existence/size test (#368)
    if args.len < 1: return ""
    let path = args[0]
    if args.len > 1 and args[1].toLowerAscii == "exists":
      return if fileExists(path): "1" else: "0"
    try:
      return if fileExists(path): $getFileSize(path) else: ""
    except:
      return ""
  of "ZARG":
    # $ZARG(n) — nth command-line script argument (1-based) (#368)
    let n = if args.len >= 1: parseInt(args[0]) else: 0
    return getZArg(n)
  of "ZCHAR":
    # $ZCHAR(n[,n2,...]) — alias for $CHAR (#374)
    var zr = ""
    for a in args:
      try: zr.add(char(parseInt(a)))
      except: discard
    return zr
  of "ZCHANGE":
    # $ZCHANGE(str, old, new) — replace all occurrences of old with new (#374)
    if args.len < 3: return ""
    let s = args[0]
    let old = args[1]
    let nw = args[2]
    if old.len == 0: return s
    return s.replace(old, nw)
  of "ZSTRIPCOMMAND":
    # $ZSTRIPCOMMAND(line) — strip a leading M command keyword (#374)
    if args.len < 1: return ""
    var s = args[0].strip()
    var i = 0
    var tok = ""
    while i < s.len and s[i] in {'A'..'Z','a'..'z','0'..'9','%','_'}:
      tok.add(s[i]); inc i
    # A command keyword is followed by whitespace (or EOL); "X=1" is an
    # assignment, not the XECUTE abbreviation "X".
    if tok.len > 0 and isCommandKeyword(tok) and
       (i >= s.len or s[i] in {' ', '\t'}):
      while i < s.len and s[i] in {' ','\t'}: inc i
      return s[i..^1]
    return s
  of "ZSYSTEM", "ZSY":
    if args.len < 1: return ""
    let (output, exitCode) = execCmdEx(args[0])
    setZsystemOutput(output.strip())
    return $exitCode
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
  of "NI_SYSTEM":
    # $NI_SYSTEM(subscript) — System information
    let sub = if args.len >= 1: args[0] else: ""
    return niSystem(sub)
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
  of "NI_HEAP":
    # $NI_HEAP(action, id, ...) — Min-heap priority queue operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niHeaps[id] = newHeap()
      return id
    of "push":
      if args.len < 3: return ""
      if id notin niHeaps: return ""
      niHeaps[id].push(args[2])
      return $niHeaps[id].len
    of "pop":
      if id notin niHeaps: return ""
      return niHeaps[id].pop()
    of "peek":
      if id notin niHeaps: return ""
      return niHeaps[id].peek()
    of "len":
      if id notin niHeaps: return "0"
      return $niHeaps[id].len
    of "destroy":
      if id in niHeaps:
        niHeaps.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_RING":
    # $NI_RING(action, id, ...) — Ring buffer operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niRings[id] = newRing(parseInt(args[2]))
      return id
    of "push":
      if args.len < 3: return ""
      if id notin niRings: return ""
      niRings[id].push(args[2])
      return $niRings[id].len
    of "pop":
      if id notin niRings: return ""
      return niRings[id].pop()
    of "peek":
      if id notin niRings: return ""
      return niRings[id].peek()
    of "len":
      if id notin niRings: return "0"
      return $niRings[id].len
    of "isfull":
      if id notin niRings: return "0"
      return if niRings[id].isFull(): "1" else: "0"
    of "isempty":
      if id notin niRings: return "0"
      return if niRings[id].isEmpty(): "1" else: "0"
    of "toseq":
      if id notin niRings: return ""
      return niRings[id].toSeq().join(",")
    of "destroy":
      if id in niRings:
        niRings.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_LRU":
    # $NI_LRU(action, id, ...) — LRU cache operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niLrus[id] = newLRU(parseInt(args[2]))
      return id
    of "put":
      if args.len < 4: return ""
      if id notin niLrus: return ""
      niLrus[id].put(args[2], args[3])
      return "1"
    of "get":
      if args.len < 3: return ""
      if id notin niLrus: return ""
      return niLrus[id].get(args[2])
    of "has":
      if args.len < 3: return ""
      if id notin niLrus: return "0"
      return if niLrus[id].has(args[2]): "1" else: "0"
    of "len":
      if id notin niLrus: return "0"
      return $niLrus[id].len
    of "clear":
      if id notin niLrus: return ""
      niLrus[id].clear()
      return "1"
    of "destroy":
      if id in niLrus:
        niLrus.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_BITSET":
    # $NI_BITSET(action, id, ...) — Bit set operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niBitSets[id] = newBitSet(parseInt(args[2]))
      return id
    of "set":
      if args.len < 3: return ""
      if id notin niBitSets: return ""
      niBitSets[id].set(parseInt(args[2]))
      return "1"
    of "clear":
      if id notin niBitSets: return ""
      if args.len >= 3:
        niBitSets[id].clear(parseInt(args[2]))
      else:
        niBitSets[id].clear()
      return "1"
    of "test":
      if args.len < 3: return ""
      if id notin niBitSets: return "0"
      return if niBitSets[id].test(parseInt(args[2])): "1" else: "0"
    of "count":
      if id notin niBitSets: return "0"
      return $niBitSets[id].count()
    of "destroy":
      if id in niBitSets:
        niBitSets.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_TRIE":
    # $NI_TRIE(action, id, ...) — Trie operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niTries[id] = newTrie()
      return id
    of "insert":
      if args.len < 3: return ""
      if id notin niTries: return ""
      let val = if args.len >= 4: args[3] else: ""
      niTries[id].insert(args[2], val)
      return "1"
    of "search":
      if args.len < 3: return ""
      if id notin niTries: return "0"
      return if niTries[id].search(args[2]): "1" else: "0"
    of "get":
      if args.len < 3: return ""
      if id notin niTries: return ""
      return niTries[id].get(args[2])
    of "startswith":
      if args.len < 3: return ""
      if id notin niTries: return "0"
      return if niTries[id].startsWith(args[2]): "1" else: "0"
    of "autocomplete":
      if args.len < 3: return ""
      if id notin niTries: return ""
      return niTries[id].autocomplete(args[2]).join(",")
    of "destroy":
      if id in niTries:
        niTries.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_GRAPH":
    # $NI_GRAPH(action, id, ...) — Graph operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len >= 3 and args[2].toLowerAscii in ["0", "false", "no"]:
        niGraphs[id] = newGraph(false)
      else:
        niGraphs[id] = newGraph(true)
      return id
    of "addnode":
      if args.len < 3: return ""
      if id notin niGraphs: return ""
      niGraphs[id].addNode(args[2])
      return "1"
    of "addedge":
      if args.len < 4: return ""
      if id notin niGraphs: return ""
      let w = if args.len >= 5: parseFloat(args[4]) else: 1.0
      niGraphs[id].addEdge(args[2], args[3], w)
      return "1"
    of "neighbors":
      if args.len < 3: return ""
      if id notin niGraphs: return ""
      let ns = niGraphs[id].neighbors(args[2])
      var names: seq[string] = @[]
      for pair in ns:
        names.add(pair[0])
      return names.join(",")
    of "hasnode":
      if args.len < 3: return ""
      if id notin niGraphs: return "0"
      return if niGraphs[id].hasNode(args[2]): "1" else: "0"
    of "hasedge":
      if args.len < 4: return ""
      if id notin niGraphs: return "0"
      return if niGraphs[id].hasEdge(args[2], args[3]): "1" else: "0"
    of "nodecount":
      if id notin niGraphs: return "0"
      return $niGraphs[id].nodeCount()
    of "edgecount":
      if id notin niGraphs: return "0"
      return $niGraphs[id].edgeCount()
    of "dfs":
      if args.len < 3: return ""
      if id notin niGraphs: return ""
      return niGraphs[id].dfs(args[2]).join(",")
    of "bfs":
      if args.len < 3: return ""
      if id notin niGraphs: return ""
      return niGraphs[id].bfs(args[2]).join(",")
    of "destroy":
      if id in niGraphs:
        niGraphs.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_MATRIX":
    # $NI_MATRIX(action, id, ...) — Dense matrix operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 4: return ""
      niMatrices[id] = newMatrix(parseInt(args[2]), parseInt(args[3]))
      return id
    of "set":
      if args.len < 5: return ""
      if id notin niMatrices: return ""
      niMatrices[id].set(parseInt(args[2]), parseInt(args[3]), parseFloat(args[4]))
      return "1"
    of "get":
      if args.len < 4: return ""
      if id notin niMatrices: return ""
      return formatNumber(niMatrices[id].get(parseInt(args[2]), parseInt(args[3])))
    of "rows":
      if id notin niMatrices: return "0"
      return $niMatrices[id].rows()
    of "cols":
      if id notin niMatrices: return "0"
      return $niMatrices[id].cols()
    of "tostring":
      if id notin niMatrices: return ""
      return niMatrices[id].toString()
    of "destroy":
      if id in niMatrices:
        niMatrices.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_BLOOM":
    # $NI_BLOOM(action, id, ...) — Bloom filter operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      let hc = if args.len >= 4: parseInt(args[3]) else: 3
      niBlooms[id] = newBloom(parseInt(args[2]), hc)
      return id
    of "add":
      if args.len < 3: return ""
      if id notin niBlooms: return ""
      niBlooms[id].add(args[2])
      return "1"
    of "contains":
      if args.len < 3: return ""
      if id notin niBlooms: return "0"
      return if niBlooms[id].contains(args[2]): "1" else: "0"
    of "clear":
      if id notin niBlooms: return ""
      niBlooms[id].clear()
      return "1"
    of "destroy":
      if id in niBlooms:
        niBlooms.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_SKIPLIST":
    # $NI_SKIPLIST(action, id, ...) — Skip list operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      let ml = if args.len >= 3: parseInt(args[2]) else: 16
      niSkipLists[id] = newSkipList(ml)
      return id
    of "insert":
      if args.len < 3: return ""
      if id notin niSkipLists: return ""
      niSkipLists[id].insert(args[2])
      return "1"
    of "search":
      if args.len < 3: return ""
      if id notin niSkipLists: return "0"
      return if niSkipLists[id].search(args[2]): "1" else: "0"
    of "len":
      if id notin niSkipLists: return "0"
      return $niSkipLists[id].len
    of "destroy":
      if id in niSkipLists:
        niSkipLists.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_TREAP":
    # $NI_TREAP(action, id, ...) — Treap operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niTreaps[id] = newTreap()
      return id
    of "insert":
      if args.len < 3: return ""
      if id notin niTreaps: return ""
      niTreaps[id].insert(args[2])
      return "1"
    of "search":
      if args.len < 3: return ""
      if id notin niTreaps: return "0"
      return if niTreaps[id].search(args[2]): "1" else: "0"
    of "len":
      if id notin niTreaps: return "0"
      return $niTreaps[id].len
    of "destroy":
      if id in niTreaps:
        niTreaps.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_DSET":
    # $NI_DSET(action, id, ...) — Disjoint set operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niDisjointSets[id] = newDisjointSet(parseInt(args[2]))
      return id
    of "union":
      if args.len < 4: return ""
      if id notin niDisjointSets: return ""
      niDisjointSets[id].union(parseInt(args[2]), parseInt(args[3]))
      return "1"
    of "find":
      if args.len < 3: return ""
      if id notin niDisjointSets: return ""
      return $niDisjointSets[id].find(parseInt(args[2]))
    of "connected":
      if args.len < 4: return ""
      if id notin niDisjointSets: return "0"
      return if niDisjointSets[id].connected(parseInt(args[2]), parseInt(args[3])): "1" else: "0"
    of "count":
      if id notin niDisjointSets: return "0"
      return $niDisjointSets[id].componentCount()
    of "destroy":
      if id in niDisjointSets:
        niDisjointSets.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_SEGTREE":
    # $NI_SEGTREE(action, id, ...) — Segment tree operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      let op = if args.len >= 4: args[3] else: "sum"
      niSegTrees[id] = newSegmentTree(parseInt(args[2]), op)
      return id
    of "setdata":
      if id notin niSegTrees: return ""
      niSegTrees[id].data = newSeq[int](args.len - 2)
      for i in 2 ..< args.len:
        try: niSegTrees[id].data[i - 2] = parseInt(args[i])
        except: discard
      return "1"
    of "build":
      if id notin niSegTrees: return "0"
      if niSegTrees[id].n < 1: return "0"
      niSegTrees[id].build(1, 0, niSegTrees[id].n - 1)
      return "1"
    of "update":
      if args.len < 4: return ""
      if id notin niSegTrees: return ""
      niSegTrees[id].update(1, 0, niSegTrees[id].n - 1, parseInt(args[2]), parseInt(args[3]))
      return "1"
    of "query":
      if args.len < 4: return ""
      if id notin niSegTrees: return "0"
      return $niSegTrees[id].query(1, 0, niSegTrees[id].n - 1, parseInt(args[2]), parseInt(args[3]))
    of "len":
      if id notin niSegTrees: return "0"
      return $niSegTrees[id].n
    of "destroy":
      if id in niSegTrees:
        niSegTrees.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_FENWICK":
    # $NI_FENWICK(action, id, ...) — Fenwick tree operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niFenwicks[id] = newFenwickTree(parseInt(args[2]))
      return id
    of "update":
      if args.len < 4: return ""
      if id notin niFenwicks: return ""
      niFenwicks[id].update(parseInt(args[2]), parseInt(args[3]))
      return "1"
    of "query":
      if args.len < 3: return ""
      if id notin niFenwicks: return "0"
      return $niFenwicks[id].query(parseInt(args[2]))
    of "range":
      if args.len < 4: return ""
      if id notin niFenwicks: return "0"
      return $niFenwicks[id].rangeQuery(parseInt(args[2]), parseInt(args[3]))
    of "len":
      if id notin niFenwicks: return "0"
      return $niFenwicks[id].n
    of "destroy":
      if id in niFenwicks:
        niFenwicks.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_SPARSE":
    # $NI_SPARSE(action, id, ...) — Sparse matrix operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 4: return ""
      niSparse[id] = newSparseMatrix(parseInt(args[2]), parseInt(args[3]))
      return id
    of "set":
      if args.len < 5: return ""
      if id notin niSparse: return ""
      niSparse[id].set(parseInt(args[2]), parseInt(args[3]), parseFloat(args[4]))
      return "1"
    of "get":
      if args.len < 4: return ""
      if id notin niSparse: return ""
      return formatNumber(niSparse[id].get(parseInt(args[2]), parseInt(args[3])))
    of "nnz":
      if id notin niSparse: return "0"
      return $niSparse[id].nnz()
    of "rows":
      if id notin niSparse: return "0"
      return $niSparse[id].rows
    of "cols":
      if id notin niSparse: return "0"
      return $niSparse[id].cols
    of "destroy":
      if id in niSparse:
        niSparse.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_ITREE":
    # $NI_ITREE(action, id, ...) — Interval tree operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      niIntervals[id] = newIntervalTree()
      return id
    of "insert":
      if args.len < 4: return ""
      if id notin niIntervals: return ""
      let data = if args.len >= 5: args[4] else: ""
      niIntervals[id].insert(parseInt(args[2]), parseInt(args[3]), data)
      return "1"
    of "query":
      if args.len < 4: return ""
      if id notin niIntervals: return ""
      let res = niIntervals[id].query(parseInt(args[2]), parseInt(args[3]))
      var parts: seq[string] = @[]
      for it in res:
        parts.add($it.low & "-" & $it.high)
      return parts.join(",")
    of "destroy":
      if id in niIntervals:
        niIntervals.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_SUFFIX":
    # $NI_SUFFIX(action, id, ...) — Suffix array operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niSuffixes[id] = newSuffixArray(args[2])
      return id
    of "search":
      if args.len < 3: return ""
      if id notin niSuffixes: return ""
      let res = niSuffixes[id].search(args[2])
      var parts: seq[string] = @[]
      for p in res:
        parts.add($p)
      return parts.join(",")
    of "len":
      if id notin niSuffixes: return "0"
      return $niSuffixes[id].sa.len
    of "destroy":
      if id in niSuffixes:
        niSuffixes.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_WAVELET":
    # $NI_WAVELET(action, id, ...) — Wavelet tree operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      var data: seq[int] = @[]
      for i in 2 ..< args.len:
        try: data.add(parseInt(args[i]))
        except: discard
      niWavelets[id] = newWaveletTree(data)
      return id
    of "range":
      if args.len < 5: return ""
      if id notin niWavelets: return "0"
      return $niWavelets[id].rangeRank(parseInt(args[2]), parseInt(args[3]), parseInt(args[4]))
    of "min":
      if id notin niWavelets: return "0"
      return $niWavelets[id].minVal
    of "max":
      if id notin niWavelets: return "0"
      return $niWavelets[id].maxVal
    of "len":
      if id notin niWavelets: return "0"
      return $niWavelets[id].data.len
    of "destroy":
      if id in niWavelets:
        niWavelets.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_KDTREE":
    # $NI_KDTREE(action, id, ...) — K-d tree operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niKdTrees[id] = newKdTree(parseInt(args[2]))
      return id
    of "insert":
      if id notin niKdTrees: return ""
      let dims = niKdTrees[id].dimensions
      if args.len < 2 + dims: return ""
      var coords: seq[float] = @[]
      for i in 0 ..< dims:
        try: coords.add(parseFloat(args[2 + i]))
        except: return ""
      let data = if args.len > 2 + dims: args[2 + dims] else: ""
      niKdTrees[id].insert(coords, data)
      return "1"
    of "nearest":
      if id notin niKdTrees: return ""
      let dims = niKdTrees[id].dimensions
      if args.len < 2 + dims: return ""
      var coords: seq[float] = @[]
      for i in 0 ..< dims:
        try: coords.add(parseFloat(args[2 + i]))
        except: return ""
      return niKdTrees[id].nearest(coords).data
    of "destroy":
      if id in niKdTrees:
        niKdTrees.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_ROPE":
    # $NI_ROPE(action, id, ...) — Rope operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      niRopes[id] = newRope(args[2])
      return id
    of "concat":
      if args.len < 4: return ""
      if id notin niRopes or args[2] notin niRopes: return ""
      niRopes[args[3]] = concat(niRopes[id], niRopes[args[2]])
      return args[3]
    of "tostring":
      if id notin niRopes: return ""
      return niRopes[id].toString()
    of "substring":
      if args.len < 4: return ""
      if id notin niRopes: return ""
      return niRopes[id].substring(parseInt(args[2]), parseInt(args[3]))
    of "len":
      if id notin niRopes: return "0"
      return $niRopes[id].length
    of "destroy":
      if id in niRopes:
        niRopes.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "NI_MERKLE":
    # $NI_MERKLE(action, id, ...) — Merkle tree operations
    if args.len < 2: return ""
    let action = args[0].toLowerAscii
    let id = args[1]
    case action
    of "create":
      if args.len < 3: return ""
      var leaves: seq[string] = @[]
      for i in 2 ..< args.len:
        leaves.add(args[i])
      niMerkles[id] = newMerkleTree(leaves)
      return id
    of "root":
      if id notin niMerkles: return ""
      return niMerkles[id].rootHash()
    of "verify":
      if args.len < 4: return ""
      if id notin niMerkles: return "0"
      return if niMerkles[id].verify(parseInt(args[2]), args[3]): "1" else: "0"
    of "leafcount":
      if id notin niMerkles: return "0"
      return $niMerkles[id].leafCount()
    of "destroy":
      if id in niMerkles:
        niMerkles.del(id)
        return "1"
      return "0"
    else:
      return ""
  of "ZJOB":
    # $ZJOB — Return current job (process) ID (#301)
    return $getpid()
  of "ZPOS":
    # $ZPOS — Return current execution position (#302)
    # Returns "ROUTINE:LABEL+offset" format
    let routine = if ev.runtime != nil: ev.runtime[].currentRoutine else: ""
    let line = if ev.runtime != nil: ev.runtime[].currentLine else: 0
    if routine.len == 0: return ""
    return routine & ":" & $line
  of "ZROUTINE":
    # $ZROUTINE — Return current routine name (#303)
    if ev.runtime != nil: return ev.runtime[].currentRoutine
    return ""
  of "ZSOURCE":
    # $ZSOURCE — Return source file path of current routine (#304)
    if ev.runtime != nil:
      let routine = ev.runtime[].currentRoutine
      if routine.len > 0 and routine in ev.runtime[].routines:
        return ev.runtime[].routines[routine].filePath
    return ""
  else:
    return ""
