# test_fst_consistency.nim — FST SearchEngine index consistency
# (mirrors formal/search_engine.dfy).
#
# Checks the real SearchEngine:
#   - docFreq counts *documents* (not occurrences)
#   - avgDocLen == total length / doc count
#   - the docId -> vector-id mapping is a bijection (injective both ways)
#
# Run: nim c -r tests/test_fst_consistency.nim

import tables
import ../future_search_tool/src/fst_core

proc main() =
  echo "FST index-consistency test (mirrors formal/search_engine.dfy)..."

  var engine = newSearchEngine(dim = 3)

  # docFreq counts documents, not occurrences:
  #   d1 = "hello hello world" (hello appears twice, tf=2, df contribution=1)
  #   d2 = "hello universe"   (hello appears once,  df contribution=1)
  engine.indexDocument("d1", "hello hello world", @[1.0, 0.0, 0.0])
  engine.indexDocument("d2", "hello universe",    @[0.0, 1.0, 0.0])

  let dfHello = engine.bm25.docFreq.getOrDefault("hello", 0)
  assert dfHello == 2, "docFreq['hello'] should count 2 docs, got " & $dfHello

  # tf counts occurrences: d1 has hello twice.
  let tfHello = engine.bm25.termFreqs["d1"].getOrDefault("hello", 0)
  assert tfHello == 2, "tf('hello' in d1) should be 2, got " & $tfHello

  # avgDocLen == totalLen / docCount.
  var totalLen = 0
  for l in engine.bm25.docLens.values:
    totalLen += l
  assert abs(engine.bm25.avgDocLen - float(totalLen) / float(engine.bm25.docCount)) < 1e-9,
    "avgDocLen must equal totalLen / docCount"

  # docId <-> vector-id bijection: docOf is injective.
  var seenDocIds = initTable[string, bool]()
  for vecId, docId in engine.docOf:
    assert docId notin seenDocIds, "docId " & docId & " mapped twice"
    seenDocIds[docId] = true
  assert engine.docOf.len == 2, "both vector-indexed docs should be mapped"

  # A keyword-only document (no vector) must not enter the vector map.
  engine.indexDocument("d3", "no vector here", @[])
  assert engine.docOf.len == 2, "keyword-only doc must not get a vector id"

  echo "  docFreq / avgDocLen / docId<->vecId bijection all hold"
  echo "FST index-consistency test passed!"

main()
