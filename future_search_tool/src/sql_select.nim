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

  JoinInfo* = object
    table*: string        # the joined relation's table name
    alias*: string        # its alias (e.g. "p" in "pubmed p")
    leftCol*: string      # qualified col on the driving side, e.g. "l.to_id"
    rightCol*: string     # qualified col on the joined side, e.g. "p.pmid"

  SelectStmt* = object
    table*: string
    alias*: string        # "" if none (M2)
    cols*: seq[string]    # empty = SELECT * (may be qualified, e.g. "p.title")
    preds*: seq[Predicate]
    joins*: seq[JoinInfo]
    orderBy*: string      # "" = none (may be qualified)
    orderDesc*: bool
    limit*: int           # 0 = no limit

  TableDef* = object
    global*: string
    keyCols*: seq[string]  # leading key subscripts, in order
    valCol*: string        # the stored value's column name ("" for record tables)
    fields*: seq[string]   # record-table field subscripts (e.g. ^PUBMED "title"/"abstract")

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
    # M2 nested-index join: driving table `def` (e.g. ^LINK) + one joined table
    # whose leading key column is looked up per driving row.
    join*: TableDef         # joined table def (zero-value when no join)
    joinAlias*: string      # driven-side alias of the joined table ("" = table)
    joinRightCol*: string   # joined side's column being fed the driving value

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
  # Record tables (the JOIN's second relation): id-keyed globals whose "columns"
  # are field subscripts, not a single leaf value (#462 M2).
  result["pubmed"] = TableDef(global: "^PUBMED", keyCols: @["pmid"],
      fields: @["title", "abstract", "journal", "authors", "nlmUniqueID"])
  result["catline"] = TableDef(global: "^CATLINE", keyCols: @["nlm_id"],
      fields: @["title", "issn"])
  result["serline"] = TableDef(global: "^SERLINE", keyCols: @["nlm_id"],
      fields: @["title", "issn"])
  result["mesh"] = TableDef(global: "^MESH", keyCols: @["dui"],
      fields: @["name", "scopeNote"])
  result["supp"] = TableDef(global: "^SUPP", keyCols: @["scrui"],
      fields: @["name", "class", "note", "frequency"])
  result["ctrial"] = TableDef(global: "^CTRIAL", keyCols: @["nct"],
      fields: @["title", "status"])

# --- tokenizer ---

type
  TokKind = enum tkIdent, tkStr, tkNum, tkComma, tkStar, tkEq, tkGe, tkLe, tkGt, tkLt, tkEof
  Token = object
    kind: TokKind
    text: string

const SqlWs = {' ', '\t', '\n', '\r'}

proc isIdentChar(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc isIdentStart(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '_'}

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
      while i < sql.len and (isIdentChar(sql[i]) or sql[i] == '.'):
        s.add(sql[i])
        inc i
      if s.allCharsInSet({'0'..'9', '.'}):
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

  var star = false
  if p.peek().kind == tkStar:
    discard p.next()
    star = true
  else:
    while true:
      let c = p.next()
      if c.kind == tkStar:
        star = true
        break
      if c.kind != tkIdent:
        raise newException(SqlError, "expected column name")
      let name = c.text.toLowerAscii
      # "<alias>.*" lexes as ident "alias." followed by tkStar
      if name.endsWith("."):
        if p.peek().kind == tkStar:
          discard p.next()
          star = true
          break
      result.cols.add(name)
      if p.peek().kind == tkComma:
        discard p.next()
        continue
      break
  if star:
    result.cols = @[]   # SELECT * semantics (possibly qualified)

  if not p.isKw("from"):
    raise newException(SqlError, "expected FROM")
  discard p.next()
  result.table = p.expectIdent()
  # optional alias: FROM pubmed p
  if p.peek().kind == tkIdent and not p.isKw("join") and not p.isKw("where") and
     not p.isKw("order") and not p.isKw("limit"):
    result.alias = p.expectIdent()

  while p.isKw("join"):
    discard p.next()
    var j: JoinInfo
    j.table = p.expectIdent()
    # optional alias for the joined table
    if p.peek().kind == tkIdent and not p.isKw("on"):
      j.alias = p.expectIdent()
    if not p.isKw("on"):
      raise newException(SqlError, "expected ON after JOIN")
    discard p.next()
    j.leftCol = p.expectIdent()
    if p.peek().kind != tkEq:
      raise newException(SqlError, "expected = in JOIN ON")
    discard p.next()
    j.rightCol = p.expectIdent()
    result.joins.add(j)

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

proc niSqlJoin*(g: var Globals, stmt: SelectStmt): string

proc niSql*(g: var Globals, sql: string): string =
  ## Parse + plan + execute a SELECT and return rows as TSV lines (one per row).
  let stmt = parseSelect(sql)
  if stmt.joins.len > 0:
    return niSqlJoin(g, stmt)
  let plan = planSelect(stmt)
  var res = ""
  for row in execSelect(g, plan):
    res.add(row.join("\t"))
    res.add("\n")
  return res

# ---------------------------------------------------------------------------
# M2 — nested-index join over ^LINK (the #462 worked example)
# ---------------------------------------------------------------------------
#
#   SELECT p.title FROM pubmed p
#   JOIN link l ON l.to_id = p.pmid
#   WHERE l.from_type='MESH' AND l.from_id='D000001' AND l.to_type='PUBMED'
#
# The driving table (`link`) is walked by an $ORDER over its leading bound
# subscripts (from_type/from_id/to_type all EQ-bound); each row yields a value
# for its ON column (`to_id`). That value is used as the leading-key point lookup
# into the joined table (`pubmed`), whose leading key column is the ON's right
# column (`pmid`). This is the O(k) walk + O(1) lookups shape from #462 — the
# join is baked into subscript order, no hash/nested-loop.

proc qualAlias(col: string): (string, string) =
  ## Split "a.b" into (alias, col); unqualified -> ("", col).
  let dot = col.find('.')
  if dot < 0: return ("", col)
  return (col[0 ..< dot], col[dot + 1 .. ^1])

proc stripQual(col: string, alias: string): string =
  ## "a.b" -> "b" when alias=="a"; unqualified passes through unchanged.
  let (a, c) = qualAlias(col)
  if a.len > 0 and a == alias: return c
  return col

proc niSqlJoin*(g: var Globals, stmt: SelectStmt): string =
  let cat = catalog()
  if stmt.joins.len != 1:
    raise newException(SqlError, "M2 supports exactly one JOIN")
  let j = stmt.joins[0]

  # Two relations: the FROM table and the JOIN table. The *driver* is the one
  # whose WHERE = predicates pin a prefix of its leading key subscripts (the
  # scan root, per #462). The other is the *joined* table, looked up point-wise.
  let fromDef = cat[stmt.table]
  let joinDef = cat[j.table]
  let fromAlias = stmt.alias
  let joinAlias = j.alias

  # Group WHERE = predicates by (alias -> eqVals on that table's columns).
  var fromEq = initTable[string, string]()
  var joinEq = initTable[string, string]()
  for pred in stmt.preds:
    if pred.op != opEq:
      raise newException(SqlError, "M2 JOIN supports only = predicates")
    let (a, c) = qualAlias(pred.col)
    if a == fromAlias or (a.len == 0 and c in fromDef.keyCols):
      fromEq[c] = pred.val
    elif a == joinAlias or (a.len == 0 and c in joinDef.keyCols):
      joinEq[c] = pred.val
    else:
      raise newException(SqlError, "M2 cannot bind " & pred.col)

  proc boundPrefix(t: TableDef, eq: Table[string, string]): int =
    var n = 0
    while n < t.keyCols.len and t.keyCols[n] in eq:
      inc n
    return n

  let fromBound = boundPrefix(fromDef, fromEq)
  let joinBound = boundPrefix(joinDef, joinEq)

  var driveDef: TableDef
  var joinedDef: TableDef
  var driveEq: Table[string, string]
  var walkCol: string   # the driving column that the ON feeds into the joined side
  var joinedAlias: string

  # The ON columns tell us the join key. l.to_id = p.pmid: the driving column is
  # whichever side of the `=` lives on the table that is being *walked*.
  let (leftA, leftC) = qualAlias(j.leftCol)
  let (rightA, rightC) = qualAlias(j.rightCol)

  # The side whose other key columns are EQ-bound (>0 bound prefix, or more bound)
  # is the driver. The driver walks the ON column (leftC if left side wins).
  if joinBound > fromBound:
    driveDef = joinDef; joinedDef = fromDef
    driveEq = joinEq
    # ON: drvCol = joinedCol. The ON references join alias on one side and from alias on the other.
    if leftA == joinAlias: walkCol = leftC
    else: walkCol = rightC
    joinedAlias = fromAlias
  else:
    driveDef = fromDef; joinedDef = joinDef
    driveEq = fromEq
    if leftA == fromAlias: walkCol = leftC
    else: walkCol = rightC
    joinedAlias = joinAlias

  # walkCol must be the driver's final key column we scan (all earlier cols bound).
  var bound: seq[string] = @[]
  for kc in driveDef.keyCols:
    if kc == walkCol:
      break
    if kc notin driveEq:
      raise newException(SqlError, "M2 requires binding " & kc & " before walking " & walkCol)
    bound.add(driveEq[kc])
  if walkCol.len == 0 or not driveDef.keyCols.contains(walkCol):
    raise newException(SqlError, "M2 JOIN ON must name the driving walk column")

  # Projection: SELECT cols resolve against the joined table.
  var outCols: seq[string] = @[]
  if stmt.cols.len == 0:
    if joinedDef.fields.len > 0:
      outCols = joinedDef.fields
    else:
      outCols = joinedDef.keyCols & @[joinedDef.valCol]
  else:
    for c in stmt.cols:
      outCols.add(stripQual(c, joinedAlias))

  proc readField(g: var Globals, def: TableDef, key: string, col: string): string =
    if col == def.keyCols[0]:
      return key
    if def.fields.len > 0:
      return g.get(def.global, @[key, col])
    if col == def.valCol:
      return g.get(def.global, @[key])
    return g.get(def.global, @[key, col])

  var res = ""
  var cur = g.order(driveDef.global, bound & @[""], forward = true)
  var emitted = 0
  while cur.len > 0:
    let hasRow = (joinedDef.fields.len > 0 and
                  g.get(joinedDef.global, @[cur, joinedDef.fields[0]]).len > 0) or
                 (joinedDef.fields.len == 0 and g.get(joinedDef.global, @[cur]).len > 0)
    if hasRow:
      var row: seq[string] = @[]
      for c in outCols:
        row.add(readField(g, joinedDef, cur, c))
      res.add(row.join("\t"))
      res.add("\n")
      inc emitted
      if stmt.limit > 0 and emitted >= stmt.limit:
        break
    cur = g.order(driveDef.global, bound & @[cur], forward = true)
  return res
