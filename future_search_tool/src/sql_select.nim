# sql_select.nim — SELECT-only SQL layer over M globals (#462, M1).
#
# A declarative front-end that compiles a tiny SELECT to an ordered walk over
# the existing globals. Not a SQL engine: no storage, no writes, no DDL. The
# planner picks the scan root and the executor streams rows through globals.nim
# (the same order()/get() calls we otherwise write by hand).
#
# M1 scope (single relation table):
#   SELECT <col>[, <col>...] | *
#   FROM <table>
#   [WHERE <col> <op> <lit> [AND ...]]       op = = | >= | <= | > | <
#   [ORDER BY <col> [ASC|DESC]]              DESC deferred to M3
#   [LIMIT <n>]
#
# A relation table has leading key subscripts (the index) plus a stored value.
# The planner requires the `=` predicates to bind a *prefix* of the key columns
# and scans the final key column (or, if every key column is bound, does a
# point lookup). ORDER BY must be the scanned column — its ascending order is
# free (the walk already emits it). The `=`-bound columns become constants in
# each projected row; the value column is the leaf value.
#
# Tables (catalog): link, bm25, bm25len, bm25df, bm25meta.

import strutils
import tables
import ../../globals
import ../../storage/key_encoding

type
  PredOp* = enum opNone, opEq, opGe, opLe, opGt, opLt

  Predicate* = object
    col*: string
    op*: PredOp
    val*: string

  SelectStmt* = object
    table*: string
    cols*: seq[string]   # empty = SELECT *
    preds*: seq[Predicate]
    orderBy*: string     # "" = none
    orderDesc*: bool
    limit*: int          # 0 = no limit

  TableDef* = object
    global*: string
    keyCols*: seq[string]  # leading key subscripts, in order
    valCol*: string        # the stored value's column name

  QueryPlan* = object
    def*: TableDef
    pointLookup*: bool
    bound*: seq[string]   # bound key-col values (prefix); all key cols for point lookup
    walkedIdx*: int       # index into keyCols being scanned (-1 for point lookup)
    hasRange*: bool
    rangeOp*: PredOp
    rangeVal*: string
    cols*: seq[string]    # resolved projection (empty = *)
    limit*: int           # 0 = no limit

  SqlError* = object of CatchableError

proc catalog*(): Table[string, TableDef] =
  result = initTable[string, TableDef]()
  result["link"] = TableDef(global: "^LINK",
      keyCols: @["from_type", "from_id", "to_type", "to_id"], valCol: "rel")
  result["bm25"] = TableDef(global: "^BM25",
      keyCols: @["term", "src", "doc_id"], valCol: "tf")
  result["bm25len"] = TableDef(global: "^BM25LEN",
      keyCols: @["src", "doc_id"], valCol: "doc_len")
  result["bm25df"] = TableDef(global: "^BM25DF",
      keyCols: @["term", "src"], valCol: "df")
  result["bm25meta"] = TableDef(global: "^BM25META",
      keyCols: @["src", "name"], valCol: "value")

# --- tokenizer ---

type
  TokKind = enum tkIdent, tkStr, tkNum, tkComma, tkStar, tkEq, tkGe, tkLe, tkGt, tkLt, tkEof
  Token = object
    kind: TokKind
    text: string

const SqlWs = {' ', '\t', '\n', '\r'}

proc isIdentChar(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc tokenize(sql: string): seq[Token] =
  var i = 0
  while i < sql.len:
    let c = sql[i]
    if c in SqlWs:
      inc i
    elif c == '\'':
      var s = ""
      inc i
      while i < sql.len:
        if sql[i] == '\'':
          if i + 1 < sql.len and sql[i + 1] == '\'':
            s.add('\'')
            i += 2
          else:
            inc i
            break
        else:
          s.add(sql[i])
          inc i
      result.add(Token(kind: tkStr, text: s))
    elif c == '*':
      result.add(Token(kind: tkStar, text: "*"))
      inc i
    elif c == ',':
      result.add(Token(kind: tkComma, text: ","))
      inc i
    elif c == '=':
      result.add(Token(kind: tkEq, text: "="))
      inc i
    elif c == '>':
      if i + 1 < sql.len and sql[i + 1] == '=':
        result.add(Token(kind: tkGe, text: ">="))
        i += 2
      else:
        result.add(Token(kind: tkGt, text: ">"))
        inc i
    elif c == '<':
      if i + 1 < sql.len and sql[i + 1] == '=':
        result.add(Token(kind: tkLe, text: "<="))
        i += 2
      else:
        result.add(Token(kind: tkLt, text: "<"))
        inc i
    elif isIdentChar(c):
      var s = ""
      while i < sql.len and isIdentChar(sql[i]):
        s.add(sql[i])
        inc i
      if s.allCharsInSet({'0'..'9'}):
        result.add(Token(kind: tkNum, text: s))
      else:
        result.add(Token(kind: tkIdent, text: s))
    else:
      raise newException(SqlError, "unexpected character: " & c)
  result.add(Token(kind: tkEof, text: ""))

# --- parser ---

type Parser = object
  toks: seq[Token]
  pos: int

proc peek(p: Parser): Token = p.toks[p.pos]

proc next(p: var Parser): Token =
  result = p.toks[p.pos]
  if p.pos < p.toks.len - 1:
    inc p.pos

proc isKw(p: Parser, kw: string): bool =
  p.peek().kind == tkIdent and p.peek().text.toLowerAscii == kw

proc expectIdent(p: var Parser): string =
  let t = p.next()
  if t.kind != tkIdent:
    raise newException(SqlError, "expected identifier")
  return t.text.toLowerAscii

proc parseSelect*(sql: string): SelectStmt =
  var p = Parser(toks: tokenize(sql), pos: 0)

  if not p.isKw("select"):
    raise newException(SqlError, "expected SELECT")
  discard p.next()

  if p.peek().kind == tkStar:
    discard p.next()
  else:
    while true:
      let c = p.next()
      if c.kind != tkIdent:
        raise newException(SqlError, "expected column name")
      result.cols.add(c.text.toLowerAscii)
      if p.peek().kind == tkComma:
        discard p.next()
        continue
      break

  if not p.isKw("from"):
    raise newException(SqlError, "expected FROM")
  discard p.next()
  result.table = p.expectIdent()

  if p.isKw("where"):
    discard p.next()
    while true:
      var pred: Predicate
      pred.col = p.expectIdent()
      let op = p.next()
      case op.kind
      of tkEq: pred.op = opEq
      of tkGe: pred.op = opGe
      of tkLe: pred.op = opLe
      of tkGt: pred.op = opGt
      of tkLt: pred.op = opLt
      else: raise newException(SqlError, "expected comparison operator")
      let lit = p.next()
      if lit.kind in {tkStr, tkNum, tkIdent}:
        pred.val = lit.text
      else:
        raise newException(SqlError, "expected literal")
      result.preds.add(pred)
      if p.isKw("and"):
        discard p.next()
        continue
      break

  if p.isKw("order"):
    discard p.next()
    if not p.isKw("by"):
      raise newException(SqlError, "expected BY after ORDER")
    discard p.next()
    result.orderBy = p.expectIdent()
    if p.isKw("desc"):
      discard p.next()
      result.orderDesc = true
    elif p.isKw("asc"):
      discard p.next()
      result.orderDesc = false

  if p.isKw("limit"):
    discard p.next()
    let n = p.next()
    if n.kind != tkNum:
      raise newException(SqlError, "expected integer after LIMIT")
    result.limit = parseInt(n.text)

  if p.peek().kind != tkEof:
    raise newException(SqlError, "unexpected trailing token: " & p.peek().text)

# --- planner ---

proc planSelect*(stmt: SelectStmt): QueryPlan =
  let cat = catalog()
  if stmt.table notin cat:
    raise newException(SqlError, "unknown table: " & stmt.table)
  result.def = cat[stmt.table]
  let kc = result.def.keyCols
  let allCols = kc & @[result.def.valCol]

  if stmt.cols.len == 0:
    result.cols = allCols
  else:
    for c in stmt.cols:
      if c notin allCols:
        raise newException(SqlError, "unknown column: " & c)
    result.cols = stmt.cols

  var eqVals = initTable[string, string]()
  var rangeCol = ""
  var rangeOp = opNone
  var rangeVal = ""
  for pred in stmt.preds:
    if pred.col notin allCols:
      raise newException(SqlError, "unknown column in WHERE: " & pred.col)
    if pred.op == opEq:
      eqVals[pred.col] = pred.val
    else:
      if rangeCol != "":
        raise newException(SqlError, "M1 supports at most one range predicate")
      rangeCol = pred.col
      rangeOp = pred.op
      rangeVal = pred.val

  var bound: seq[string] = @[]
  var i = 0
  while i < kc.len and kc[i] in eqVals:
    bound.add(eqVals[kc[i]])
    inc i
  for j in i ..< kc.len:
    if kc[j] in eqVals:
      raise newException(SqlError,
        "cannot filter on " & kc[j] & " without binding " & kc[i])
  if result.def.valCol in eqVals:
    raise newException(SqlError, "value-column filter not in M1")

  if i == kc.len:
    result.pointLookup = true
    result.bound = bound
    result.walkedIdx = -1
    if rangeCol != "":
      raise newException(SqlError, "range predicate with fully-bound key has nothing to scan")
  else:
    if i != kc.len - 1:
      raise newException(SqlError,
        "M1 scans only the final key column; cannot scan " & kc[i])
    result.pointLookup = false
    result.bound = bound
    result.walkedIdx = i
    result.hasRange = rangeCol != ""
    if rangeCol != "" and rangeCol != kc[i]:
      raise newException(SqlError,
        "range predicate must be on the scanned column " & kc[i])
    result.rangeOp = rangeOp
    result.rangeVal = rangeVal

  if stmt.orderBy.len > 0:
    if stmt.orderBy notin allCols:
      raise newException(SqlError, "unknown ORDER BY column: " & stmt.orderBy)
    if not result.pointLookup and stmt.orderBy != kc[result.walkedIdx]:
      raise newException(SqlError,
        "ORDER BY must be on the scanned column " & kc[result.walkedIdx])
    if stmt.orderDesc:
      raise newException(SqlError, "ORDER BY DESC not in M1 (materialize+sort is M3)")

  result.limit = stmt.limit

proc rowValues(plan: QueryPlan, subs: seq[string], val: string): seq[string] =
  let kc = plan.def.keyCols
  for c in plan.cols:
    if c == plan.def.valCol:
      result.add(val)
    else:
      var v = ""
      for idx in 0 ..< kc.len:
        if kc[idx] == c:
          v = subs[idx]
      result.add(v)

# --- executor ---

proc execSelect*(g: var Globals, plan: QueryPlan): seq[seq[string]] =
  let kc = plan.def.keyCols
  if plan.pointLookup:
    let val = g.get(plan.def.global, plan.bound)
    if val.len > 0:
      result.add(rowValues(plan, plan.bound, val))
    return result

  var cur = g.order(plan.def.global, plan.bound & @[""], forward = true)
  while cur.len > 0:
    var stop = false
    var skip = false
    if plan.hasRange:
      let c = mCollationCmp(cur, plan.rangeVal)
      case plan.rangeOp
      of opGe: skip = c < 0
      of opGt: skip = c <= 0
      of opLe: stop = c > 0
      of opLt: stop = c >= 0
      else: discard
    if stop:
      break
    if not skip:
      let subs = plan.bound & @[cur]
      let val = g.get(plan.def.global, subs)
      result.add(rowValues(plan, subs, val))
      if plan.limit > 0 and result.len >= plan.limit:
        break
    cur = g.order(plan.def.global, plan.bound & @[cur], forward = true)

proc niSql*(g: var Globals, sql: string): string =
  ## Parse + plan + execute a SELECT and return rows as TSV lines (one per row).
  let stmt = parseSelect(sql)
  let plan = planSelect(stmt)
  var res = ""
  for row in execSelect(g, plan):
    res.add(row.join("\t"))
    res.add("\n")
  return res
