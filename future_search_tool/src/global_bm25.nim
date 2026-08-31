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

proc tokenizeQuery(query: string): seq[string] =
  ## Lowercase and split a query the way COMMON tokenizes documents.
  result = @[]
  for t in query.toLowerAscii.split(TokenSep):
    let s = t.strip()
    if s.len > 0:
      result.add(s)

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
