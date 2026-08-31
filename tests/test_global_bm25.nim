# test_global_bm25.nim — globals-backed BM25 scorer consistency
# (mirrors formal/bm25.dfy).
#
# Proves the globals-backed scorer (global_bm25.nim, reading ^BM25* via
# globals.nim) yields the same score as the in-memory bm25.nim scorer, with
# k1 unified to 1.5 (the M SCORE/SEARCH value).
#
# Run: nim c -r tests/test_global_bm25.nim

import ../globals
import ../future_search_tool/src/global_bm25
import ../future_search_tool/src/bm25

proc main() =
  echo "global_bm25 consistency test..."

  # Build the ^BM25* index globals the way bm25idx.m COMMON would.
  var g = newGlobals("")
  g.set("^BM25META", @["MESH", "N"], "2")
  g.set("^BM25META", @["MESH", "avgdl"], "2.0")
  g.set("^BM25LEN", @["MESH", "d1"], "2")
  g.set("^BM25LEN", @["MESH", "d2"], "2")
  g.set("^BM25", @["hello", "MESH", "d1"], "1")
  g.set("^BM25", @["hello", "MESH", "d2"], "1")
  g.set("^BM25DF", @["hello", "MESH"], "2")

  # The in-memory scorer over the same documents (k1 unified to 1.5).
  var scorer = newBM25Scorer(k1 = 1.5, b = 0.75)
  scorer.addDocument("d1", "hello world")
  scorer.addDocument("d2", "hello universe")

  # scoreGlobal (globals-backed) must equal score (in-memory).
  let gs = scoreGlobal(g, "MESH", "d1", "hello", k1 = 1.5, b = 0.75)
  let ms = scorer.score("d1", "hello")
  assert abs(gs - ms) < 1e-9, "globals-backed score " & $gs & " != in-memory " & $ms

  # Both docs score positively for "hello"; a non-matching term scores 0.
  assert scoreGlobal(g, "MESH", "d1", "hello") > 0.0
  assert scoreGlobal(g, "MESH", "d2", "hello") > 0.0
  assert scoreGlobal(g, "MESH", "d1", "absentterm") == 0.0

  # searchGlobal returns both docs.
  let results = searchGlobal(g, "MESH", "hello", topK = 10)
  assert results.len == 2, "searchGlobal should return 2 docs, got " & $results.len

  echo "  globals-backed score == in-memory score (k1 unified to 1.5)"
  echo "global_bm25 consistency test passed!"

main()
