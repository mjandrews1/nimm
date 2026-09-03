# bool_search.nim — Boolean search over the ^BM25 posting index (#468).
#
# Parses infix expressions with AND / OR / NOT, parenthesised groups, and
# "double-quoted phrases", then evaluates them by zig-zag merge over the sorted
# ^BM25 posting lists (no materialization) and adjacently-checks phrases via
# ^BMPOS. Mirrors formal/boolean_search.dfy (merge soundness/completeness) and
# formal/phrase_search.dfy (adjacency chain).
#
#   atom := term | "phrase" | ( expr )
#   not  := NOT not | atom
#   and  := not (AND not)*          (implicit adjacency is NOT implicit here)
#   expr := and (OR and)*
#
# NOT is set difference only: `A AND NOT B` subtracts; a bare leading NOT needs
# a corpus scope (the caller supplies the source doc-id universe from ^BM25LEN).

import strutils
import sets
import tables
import ../../globals

type
  BoolExprKind* = enum eTerm, ePhrase, eAnd, eOr, eNot
  BoolExpr* = ref object
    case kind*: BoolExprKind
    of eTerm:
      term*: string
    of ePhrase:
      words*: seq[string]
    of eAnd, eOr:
      left*, right*: BoolExpr
    of eNot:
      inner*: BoolExpr

  BoolError* = object of CatchableError

# --- lexer ---

type
  TokKind = enum tWord, tPhrase, tAnd, tOr, tNot, tLParen, tRParen, tEof
  Tok = object
    kind: TokKind
    text: string

const BoolWs = {' ', '\t', '\n', '\r'}

proc lex*(src: string): seq[Tok] =
  result = @[]
  var i = 0
  while i < src.len:
    let c = src[i]
    if c in BoolWs:
      inc i
    elif c == '(':
      result.add(Tok(kind: tLParen, text: "(")); inc i
    elif c == ')':
      result.add(Tok(kind: tRParen, text: ")")); inc i
    elif c == '"':
      var s = ""
      inc i
      while i < src.len and src[i] != '"':
        s.add(src[i]); inc i
      if i < src.len: inc i  # closing quote
      result.add(Tok(kind: tPhrase, text: s))
    else:
      var s = ""
      while i < src.len and src[i] notin BoolWs and src[i] notin {'(', ')', '"'}:
        s.add(src[i]); inc i
      let up = s.toUpperAscii
      if up == "AND": result.add(Tok(kind: tAnd, text: s))
      elif up == "OR": result.add(Tok(kind: tOr, text: s))
      elif up == "NOT": result.add(Tok(kind: tNot, text: s))
      else: result.add(Tok(kind: tWord, text: s))
  result.add(Tok(kind: tEof, text: ""))

# --- parser ---

proc tokenizePhraseWords*(phrase: string): seq[string]

type Parser = object
  toks: seq[Tok]
  pos: int

proc peek(p: Parser): Tok = p.toks[p.pos]
proc next(p: var Parser): Tok =
  result = p.toks[p.pos]
  if p.pos < p.toks.len - 1: inc p.pos

proc parseNot(p: var Parser): BoolExpr
proc parseAnd(p: var Parser): BoolExpr
proc parseOr(p: var Parser): BoolExpr

proc parseNot(p: var Parser): BoolExpr =
  let t = p.peek()
  case t.kind
  of tNot:
    discard p.next()
    result = BoolExpr(kind: eNot, inner: parseNot(p))
  of tLParen:
    discard p.next()
    result = parseOr(p)
    if p.peek().kind != tRParen:
      raise newException(BoolError, "expected )")
    discard p.next()
  of tWord:
    discard p.next()
    result = BoolExpr(kind: eTerm, term: t.text)
  of tPhrase:
    discard p.next()
    # tokenize the phrase the same way documents are tokenized
    let words = tokenizePhraseWords(t.text)
    if words.len == 0:
      raise newException(BoolError, "empty phrase")
    result = if words.len == 1:
      BoolExpr(kind: eTerm, term: words[0])
    else:
      BoolExpr(kind: ePhrase, words: words)
  else:
    raise newException(BoolError, "unexpected token")

proc parseAnd(p: var Parser): BoolExpr =
  result = parseNot(p)
  while p.peek().kind == tAnd:
    discard p.next()
    let rhs = parseNot(p)
    result = BoolExpr(kind: eAnd, left: result, right: rhs)

proc parseOr(p: var Parser): BoolExpr =
  result = parseAnd(p)
  while p.peek().kind == tOr:
    discard p.next()
    let rhs = parseAnd(p)
    result = BoolExpr(kind: eOr, left: result, right: rhs)

proc parseBool*(src: string): BoolExpr =
  var p = Parser(toks: lex(src), pos: 0)
  result = parseOr(p)
  if p.peek().kind != tEof:
    raise newException(BoolError, "unexpected trailing token: " & p.peek().text)

proc tokenizePhraseWords*(phrase: string): seq[string] =
  ## Tokenize a quoted phrase exactly as documents are tokenized (tokenizeDoc),
  ## preserving the order for adjacency checks.
  result = @[]
  let lower = phrase.toLowerAscii
  var buf = newStringOfCap(lower.len)
  # reuse the same punctuation set as tokenizeDoc (DocP in global_bm25.nim)
  const DocP = {'"', '~', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
                '_', '-', '+', '=', '[', ']', '{', '}', '|', ';', ':', '\'',
                ',', '.', '<', '>', '/', '?', ' ', '`', '\t', '\\'}
  for c in lower:
    buf.add(if c in DocP: ' ' else: c)
  for t in buf.split(' '):
    if t.len > 0:
      result.add(t)

# --- postings access (sorted walks, mirrors zig-zag of boolean_search.dfy) ---

proc posting*(g: var Globals, src: string, term: string): seq[string] =
  ## The sorted doc-id posting list for `term` under `src` (^BM25 walk).
  result = @[]
  var id = g.order("^BM25", @[term, src, ""], forward = true)
  while id.len > 0:
    result.add(id)
    id = g.order("^BM25", @[term, src, id], forward = true)

proc intersectPostings*(a, b: seq[string]): seq[string] =
  ## Zig-zag intersect of two sorted posting lists.
  result = @[]
  var i = 0; var j = 0
  while i < a.len and j < b.len:
    let cmp = cmp(a[i], b[j])
    if cmp == 0:
      result.add(a[i]); inc i; inc j
    elif cmp < 0: inc i
    else: inc j

proc unionPostings*(a, b: seq[string]): seq[string] =
  ## Zig-zag union of two sorted posting lists.
  result = @[]
  var i = 0; var j = 0
  while i < a.len and j < b.len:
    let cmp = cmp(a[i], b[j])
    if cmp == 0: result.add(a[i]); inc i; inc j
    elif cmp < 0: result.add(a[i]); inc i
    else: result.add(b[j]); inc j
  while i < a.len: result.add(a[i]); inc i
  while j < b.len: result.add(b[j]); inc j

proc differencePostings*(a, b: seq[string]): seq[string] =
  ## Set difference A \ B of two sorted posting lists.
  result = @[]
  var i = 0; var j = 0
  while i < a.len and j < b.len:
    let cmp = cmp(a[i], b[j])
    if cmp == 0: inc i; inc j
    elif cmp < 0: result.add(a[i]); inc i
    else: inc j
  while i < a.len: result.add(a[i]); inc i

# --- phrase evaluation via ^BMPOS (phrase_search.dfy) ---

proc phraseMatches*(g: var Globals, src: string, docId: string,
                    words: seq[string]): bool =
  ## True iff every word in `words` occurs at consecutive positions in docId.
  ## Pick the rarest word first (smallest posting), then verify adjacency.
  if words.len == 0: return false
  # fetch each word's position list for this doc
  var plist: seq[seq[int]] = @[]
  for w in words:
    let packed = g.get("^BMPOS", @[src, docId, w])
    if packed.len == 0: return false
    var p: seq[int] = @[]
    for x in packed.split('|'):
      if x.len > 0:
        p.add(parseInt(x))
    plist.add(p)
  # check for a chain p, p+1, ..., p+k-1
  for start in plist[0]:
    var ok = true
    for k in 1 ..< words.len:
      if start + k notin plist[k]:
        ok = false
        break
    if ok: return true
  return false

# --- evaluator ---

proc evalExpr*(g: var Globals, src: string, e: BoolExpr): seq[string] =
  case e.kind
  of eTerm:
    result = g.posting(src, e.term)
  of ePhrase:
    # candidate docs = posting of the rarest word; then adjacency-check each.
    var candidates: seq[string] = @[]
    var rare = 0
    var rareLen = -1
    for i in 0 ..< e.words.len:
      if rareLen < 0:
        let pst = g.posting(src, e.words[i])
        candidates = pst
        rareLen = pst.len
        rare = i
      else:
        let dflen = parseInt(g.get("^BM25DF", @[e.words[i], src]))
        if dflen < rareLen:
          let pst = g.posting(src, e.words[i])
          candidates = pst
          rareLen = pst.len
          rare = i
    result = @[]
    for docId in candidates:
      if g.phraseMatches(src, docId, e.words):
        result.add(docId)
  of eAnd:
    let l = evalExpr(g, src, e.left)
    let r = evalExpr(g, src, e.right)
    result = intersectPostings(l, r)
  of eOr:
    let l = evalExpr(g, src, e.left)
    let r = evalExpr(g, src, e.right)
    result = unionPostings(l, r)
  of eNot:
    # NOT = difference against the corpus scope (all doc ids under src).
    let inner = evalExpr(g, src, e.inner)
    var corpus: seq[string] = @[]
    var id = g.order("^BM25LEN", @[src, ""], forward = true)
    while id.len > 0:
      corpus.add(id)
      id = g.order("^BM25LEN", @[src, id], forward = true)
    result = differencePostings(corpus, inner)

proc boolSearch*(g: var Globals, src: string, query: string): seq[string] =
  ## Parse + evaluate a boolean query, returning the sorted set of doc ids.
  let e = parseBool(query)
  result = evalExpr(g, src, e)
