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

var seed = 0xBEEF'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)
proc randInt(lo, hi: int): int = lo + int(rng() mod uint32(hi - lo + 1))

proc scoreOf(results: seq[(string, float)], id: string): float =
  for (d, s) in results:
    if d == id: return s
  return -1.0

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

  # 4. Randomized rerank-monotonicity fuzz: a doc at a better (smaller) rank
  #    always outscores the same doc at a worse rank, holding everything else.
  for _ in 1 .. 2000:
    let rGood = randInt(1, 50)
    let rBad = randInt(rGood + 1, 100)
    var l1: seq[(string, float)] = @[]
    var l2: seq[(string, float)] = @[]
    for i in 0 ..< rBad:
      if i == rGood - 1: l1.add(("0", 1.0)) else: l1.add(("x" & $i, 1.0))
      if i == rBad - 1: l2.add(("0", 1.0)) else: l2.add(("x" & $i, 1.0))
    let sGood = scoreOf(hs.rrfScore(l1, @[]), "0")
    let sBad = scoreOf(hs.rrfScore(l2, @[]), "0")
    assert sGood > sBad, "rank " & $rGood & " should outscore rank " & $rBad

  echo "  positive / monotone / dual-list / deterministic / fuzz all hold"
  echo "RRF hybrid merge test passed!"

main()
