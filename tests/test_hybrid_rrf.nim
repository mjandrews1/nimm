# test_hybrid_rrf.nim — Reciprocal Rank Fusion property test
# (mirrors formal/hybrid_merge.dfy).
#
# Validates the real rrfScore (future_search_tool/src/hybrid_search.nim):
#   positive   every fused score > 0
#   monotone   a rank-1 document outscores a rank-2 document
#   dual-list  a document in both lists accumulates both RRF terms
#   deterministic  same input -> identical output
#
# Run: nim c -r tests/test_hybrid_rrf.nim

import math
import tables
import ../future_search_tool/src/hybrid_search

proc main() =
  echo "RRF hybrid merge property test (mirrors formal/hybrid_merge.dfy)..."

  let hs = newHybridSearch(3, 60)

  # 1. Rank monotonicity + positivity.
  let r1 = hs.rrfScore(@[("A", 1.0), ("B", 0.5)], @[])
  var scores = initTable[string, float]()
  for (id, s) in r1:
    scores[id] = s
  assert scores["A"] > scores["B"], "rank-1 doc should outscore rank-2 doc"
  assert scores["A"] > 0.0 and scores["B"] > 0.0, "RRF scores must be positive"

  # 2. A doc in both lists accumulates both terms (1/61 + 1/61).
  let r2 = hs.rrfScore(@[("0", 1.0)], @[(0, 0.5)])
  var s0 = 0.0
  for (id, s) in r2:
    if id == "0": s0 = s
  assert abs(s0 - 2.0 / 61.0) < 1e-9, "dual-list doc should sum both RRF terms, got " & $s0

  # 3. Determinism.
  let r3 = hs.rrfScore(@[("A", 1.0), ("B", 0.5)], @[])
  assert r3 == r1, "rrfScore must be deterministic"

  echo "  positive / monotone / dual-list / deterministic all hold"
  echo "RRF hybrid merge test passed!"

main()
