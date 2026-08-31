# global_bm25.nim — BM25 scoring over the ^BM25* LMDB globals.
#
# This is the single canonical BM25 path: it reads the index that the M build
# (bm25idx.m COMMON) writes into the ^BM25* globals, and scores with the same
# formula as bm25.nim (verified by formal/bm25.dfy). It routes through
# globals.nim, so there is one LMDB access path (no separate LmdbStore).
#
# Index layout (produced by bm25idx.m COMMON):
#   ^BM25(term, type, id) = tf      ^BM25DF(term, type) = df
#   ^BM25LEN(type, id) = docLen     ^BM25META(type, "N"/"avgdl")
#
# k1 defaults to 1.5 to match the M SCORE/SEARCH (bm25.nim's default is 1.2).

import math
import tables
import strutils
import algorithm
import bm25
import ../../globals

const TokenSep = {' ', '\t', '\n', '\r', ',', '.', '!', '?', ';', ':', '(',
                  ')', '[', ']', '{', '}', '"', '\'', '~', '@', '#', '$', '%',
                  '^', '&', '*', '_', '-', '+', '=', '|', '<', '>', '/', '`',
                  '\\'}

# DocP is the exact $CHAR set that bm25idx.m COMMON builds for $TRANSLATE:
#   $CHAR(34)=`"`  $CHAR(126)=`~` $CHAR(33)=`!` $CHAR(64)=`@` $CHAR(35)=`#`
#   $CHAR(36)=`$`  $CHAR(37)=`%` $CHAR(94)=`^` $CHAR(38)=`&` $CHAR(42)=`*`
#   $CHAR(40)=`(`  $CHAR(41)=`)` $CHAR(95)=`_` $CHAR(45)=`-` $CHAR(43)=`+`
#   $CHAR(61)=`=`  $CHAR(91)=`[` $CHAR(93)=`]` $CHAR(123)=`{` $CHAR(125)=`}`
#   $CHAR(124)=`|` $CHAR(59)=`;` $CHAR(58)=`:` $CHAR(39)=`'` $CHAR(44)=`,`
#   $CHAR(46)=`.`  $CHAR(60)=`<` $CHAR(62)=`>` $CHAR(47)=`/` $CHAR(63)=`?`
#   $CHAR(32)=` `  $CHAR(96)=``` ` $CHAR(9)=tab   $CHAR(92)=`\`
# NOTE: '\n' and '\r' are intentionally absent, matching M COMMON.
const DocP = {'"', '~', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
              '_', '-', '+', '=', '[', ']', '{', '}', '|', ';', ':', '\'',
              ',', '.', '<', '>', '/', '?', ' ', '`', '\t', '\\'}

proc tokenizeQuery(query: string): seq[string] =
  ## Lowercase and split a query the way COMMON tokenizes documents.
  result = @[]
  for t in query.toLowerAscii.split(TokenSep):
    let s = t.strip()
    if s.len > 0:
      result.add(s)

proc tokenizeDoc*(text: string): seq[string] =
  ## Tokenize a document exactly as bm25idx.m COMMON does: lowercase ASCII,
  ## replace the P punctuation set with spaces, then split on ' ' only.
  ## Unlike tokenizeQuery (which also splits '\n'/'\r'), newlines and carriage
  ## returns are NOT separators here — they stay inside tokens.
  result = @[]
  let lower = text.toLowerAscii
  var buf = newStringOfCap(lower.len)
  for c in lower:
    buf.add(if c in DocP: ' ' else: c)
  for t in buf.split(' '):
    if t.len > 0:
      result.add(t)

proc parseFloatOr(s: string, def: float): float =
  try: parseFloat(s) except: def

proc parseIntOr(s: string, def: int): int =
  try: parseInt(s) except: def

proc idf(n: int, df: int): float =
  if df <= 0: return 0.0
  ln((float(n) - float(df) + 0.5) / (float(df) + 0.5) + 1.0)

proc scoreGlobal*(g: var Globals, src: string, docId: string, query: string,
                  k1: float = 1.5, b: float = 0.75): float =
  ## BM25 score of `docId` against `query`, reading the ^BM25* index via
  ## globals.nim. Matches bm25.nim's score() and the M SCORE formula.
  let n = parseIntOr(g.get("^BM25META", @[src, "N"]), 0)
  let avgdl = parseFloatOr(g.get("^BM25META", @[src, "avgdl"]), 0.0)
  let docLen = parseIntOr(g.get("^BM25LEN", @[src, docId]), 0)
  if avgdl <= 0.0 or docLen <= 0:
    return 0.0
  var total = 0.0
  for term in tokenizeQuery(query):
    let tf = parseIntOr(g.get("^BM25", @[term, src, docId]), 0)
    if tf <= 0:
      continue
    let df = parseIntOr(g.get("^BM25DF", @[term, src]), 0)
    if df <= 0:
      continue
    let idfV = idf(n, df)
    let denom = float(tf) + k1 * (1.0 - b + b * float(docLen) / avgdl)
    total += idfV * (float(tf) * (k1 + 1.0)) / denom
  return total

proc searchGlobal*(g: var Globals, src: string, query: string, topK: int = 10,
                   k1: float = 1.5, b: float = 0.75): seq[(string, float)] =
  ## Top-K documents in `src` by BM25 score over the ^BM25* globals.
  var scores: seq[(string, float)] = @[]
  for node in g.listNodes("^BM25LEN", @[src]):
    if node.len > 0:
      let docId = node[^1]
      let s = scoreGlobal(g, src, docId, query, k1, b)
      if s > 0.0:
        scores.add((docId, s))
  scores.sort(proc (a, b: (string, float)): int = cmp(b[1], a[1]))
  if scores.len > topK:
    return scores[0 ..< topK]
  return scores

proc collectDocIds(g: var Globals, glob: string): seq[string] =
  ## Top-level subscripts of `glob` (the doc ids), in $ORDER order. Must run
  ## BEFORE beginWriteBatch so the cursor reads the committed source globals.
  var ids: seq[string] = @[]
  var id = g.order(glob, @[], forward = true)
  while id.len > 0:
    ids.add(id)
    id = g.order(glob, @[id], forward = true)
  return ids

proc buildIndex*(g: var Globals, src: string, glob: string, flist: string,
                 flushEvery: int = 1000): tuple[docs, tokens: int, avgdl: float] =
  ## Build the ^BM25* index for source `src` from the documents in `glob`
  ## (fields listed in `flist`, '^'-separated), exactly mirroring bm25idx.m
  ## COMMON:
  ##   ^BM25(term,src,id)=tf   ^BM25DF(term,src)=df
  ##   ^BM25LEN(src,id)=len    ^BM25META(src,"N"/"avgdl")
  ##
  ## Writes are batched and the write transaction is flushed every `flushEvery`
  ## docs so a single LMDB write txn never grows to the ~1.2M-doc size that
  ## aborted the M build (#457). Doc ids are collected before the batch begins.
  let fields = flist.split('^')
  let docIds = g.collectDocIds(glob)

  g.beginWriteBatch()
  var written = 0
  for docId in docIds:
    # Skip docs already indexed (idempotent re-runs mirror COMMON's
    # `IF '$DATA(^BM25LEN(SRC,ID))` guard).
    if g.get("^BM25LEN", @[src, docId]).len > 0:
      continue
    var tf = initCountTable[string]()
    var dl = 0
    for fname in fields:
      if fname.len == 0:
        continue
      let txt = g.get(glob, @[docId, fname])
      for w in tokenizeDoc(txt):
        tf.inc(w)
        inc dl
    if dl == 0:
      continue
    for w, c in tf.pairs:
      g.set("^BM25", @[w, src, docId], $c)
      # df is the first-occurrence count: +1 per doc containing w. The
      # read-back during writeTxnActive sees this txn's own writes (#359/#368).
      let oldDf = parseIntOr(g.get("^BM25DF", @[w, src]), 0)
      g.set("^BM25DF", @[w, src], $(oldDf + 1))
    g.set("^BM25LEN", @[src, docId], $dl)
    inc written
    if written mod flushEvery == 0:
      g.endWriteBatch()
      g.beginWriteBatch()
  g.endWriteBatch()

  # Meta: N = number of indexed docs, avgdl = mean doc length (matches COMMON).
  # $ORDER(^BM25LEN(SRC,ID)) iterates doc ids; the null first subscript in M is
  # the $ORDER(^BM25LEN(SRC,"")) start, mirrored by order(...,@[src,""]).
  var n = 0
  var sum = 0
  var id = g.order("^BM25LEN", @[src, ""], forward = true)
  while id.len > 0:
    sum += parseIntOr(g.get("^BM25LEN", @[src, id]), 0)
    inc n
    id = g.order("^BM25LEN", @[src, id], forward = true)
  let avgdl = if n > 0: float(sum) / float(n) else: 0.0
  g.set("^BM25META", @[src, "N"], $n)
  g.set("^BM25META", @[src, "avgdl"], formatFloat(avgdl, ffDecimal, 2))
  return (docs: n, tokens: sum, avgdl: avgdl)
