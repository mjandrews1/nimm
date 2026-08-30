# test_hnsw_invariants.nim — HNSW index invariants
# (mirrors formal/hnsw.dfy).
#
# Checks the real HNSWIndex maintains:
#   - neighbor symmetry (no one-way edges)
#   - bounded degree (<= M connections)
#   - valid entry point
#   - cosine symmetry + self-similarity == 1
#   - search returns valid nodes in non-increasing similarity order
#
# Run: nim c -r tests/test_hnsw_invariants.nim

import tables
import ../future_search_tool/src/hnsw

var seed = 0xC0FFEE'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)
proc randFloat(): float = float(rng() mod 1000) / 1000.0 - 0.5

proc main() =
  echo "HNSW invariant test (mirrors formal/hnsw.dfy)..."

  # Cosine symmetry + self-similarity.
  for _ in 0 ..< 200:
    let a = @[randFloat(), randFloat(), randFloat()]
    let b = @[randFloat(), randFloat(), randFloat()]
    if a != b:
      assert abs(cosineSimilarity(a, b) - cosineSimilarity(b, a)) < 1e-9,
        "cosine must be symmetric"
    let v = @[randFloat(), randFloat(), randFloat()]
    if v != @[0.0, 0.0, 0.0]:
      assert abs(cosineSimilarity(v, v) - 1.0) < 1e-9,
        "self-similarity must be 1"

  # Build an index and check graph invariants.
  var idx = newHNSWIndex(dim = 3, M = 3, efConstruction = 20, efSearch = 20)
  for id in 0 ..< 60:
    var v: seq[float] = @[]
    for _ in 0 ..< 3:
      v.add(randFloat())
    idx.insert(id, v)

  # Bounded degree.
  for a, nb in idx.neighbors:
    assert nb.len <= idx.M, "degree must be <= M, got " & $nb.len & " for " & $a

  # Symmetry: every edge a->b has a reverse b->a.
  var edges = 0
  for a, nb in idx.neighbors:
    for b in nb:
      assert b in idx.neighbors and a in idx.neighbors[b], "one-way edge " & $a & "->" & $b
      inc edges
  assert edges > 0, "sanity: there should be some edges"

  # Valid entry point.
  assert idx.entryPoint == -1 or idx.entryPoint in idx.vectors,
    "entry point must be a known node"

  # Search returns valid nodes in non-increasing similarity order.
  let query = @[randFloat(), randFloat(), randFloat()]
  let results = idx.search(query, topK = 10)
  var prev = 2.0
  for (id, score) in results:
    assert id in idx.vectors, "search result must be a known node"
    assert score <= prev + 1e-9, "search results must be non-increasing"
    prev = score

  echo "  symmetry / bounded / entrypoint / cosine / search-order all hold"
  echo "HNSW invariant test passed!"

main()
