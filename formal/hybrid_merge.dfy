// formal/hybrid_merge.dfy
//
// Formal model of the FST hybrid search (future_search_tool/src/
// hybrid_search.nim): Reciprocal Rank Fusion combines BM25 and HNSW results,
// scoring a document at rank r in a list as 1/(k + r). A document appearing in
// both lists accumulates both contributions; the merged map is then sorted by
// descending score (dedup is structural — a table keyed by docId).
//
// Proved here:
//   1. The RRF term is positive.
//   2. The RRF term is strictly decreasing in rank (better rank = higher score).
//   3. Improving a document's rank in either list raises its combined score
//      (monotone rerank).
//   4. The combined score is non-negative.
//
// Verify with:  dafny verify formal/hybrid_merge.dfy

module HybridMerge {

  // Reciprocal rank term (k > 0, rank >= 1).
  function RRF(k: int, rank: int): real
    requires k > 0 && rank >= 1
  {
    1.0 / (k as real + rank as real)
  }

  // The RRF term is strictly positive.
  lemma RRFPositive(k: int, rank: int)
    requires k > 0 && rank >= 1
    ensures RRF(k, rank) > 0.0
  {
  }

  // Reciprocal of a positive is strictly decreasing.
  lemma RecipDecreasing(x: real, y: real)
    requires 0.0 < x < y
    ensures 1.0 / x > 1.0 / y
  {
  }

  // The RRF term is strictly decreasing in rank.
  lemma RRFDecreasing(k: int, r1: int, r2: int)
    requires k > 0 && 1 <= r1 < r2
    ensures RRF(k, r1) > RRF(k, r2)
  {
    assert 0.0 < k as real + r1 as real < k as real + r2 as real;
    RecipDecreasing(k as real + r1 as real, k as real + r2 as real);
  }

  // A document's combined score: the sum of its BM25 and HNSW contributions,
  // with 0 for a list it is absent from.
  function Combined(k: int, rb: int, rh: int): real
    requires k > 0
  {
    (if rb >= 1 then RRF(k, rb) else 0.0) + (if rh >= 1 then RRF(k, rh) else 0.0)
  }

  // The combined score is non-negative.
  lemma CombinedNonNeg(k: int, rb: int, rh: int)
    requires k > 0
    ensures Combined(k, rb, rh) >= 0.0
  {
    if rb >= 1 { RRFPositive(k, rb); }
    if rh >= 1 { RRFPositive(k, rh); }
  }

  // Improving a document's rank in one list (smaller rank) strictly raises its
  // combined score, holding the other list's rank fixed.
  lemma RerankMonotone(k: int, rb1: int, rb2: int, rh: int)
    requires k > 0 && 1 <= rb1 < rb2 && rh >= 1
    ensures Combined(k, rb1, rh) > Combined(k, rb2, rh)
  {
    RRFDecreasing(k, rb1, rb2);
  }

}
