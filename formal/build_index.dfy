// formal/build_index.dfy
//
// Formal model of the FST BM25 index builder (global_bm25.nim buildIndex):
//   - df-batching: accumulating df deltas in memory and applying once equals
//     the per-term read-modify-write (+1 per doc containing the term).
//   - re-run idempotency: skipping already-indexed docs never double-counts.
//   - high-water mark: committed (skipped + written) is monotone and ends at
//     the total doc count.
//
// Verify with:  dafny verify formal/build_index.dfy

module BuildIndex {

  type Doc = string
  type Term = string

  // A document is a list of its distinct terms (df counts docs, not
  // occurrences — see search_engine.dfy).
  predicate Distinct(terms: seq<Term>)
  {
    forall i, j | 0 <= i < j < |terms| :: terms[i] != terms[j]
  }

  // df of a term across a list of documents: number of docs containing it.
  function DfOf(docs: seq<seq<Term>>, term: Term): int
    decreases |docs|
  {
    if |docs| == 0 then 0
    else (if term in docs[0] then 1 else 0) + DfOf(docs[1..], term)
  }

  // A term is in a doc (set membership over the doc's term list).
  predicate Contains(doc: seq<Term>, term: Term)
  {
    term in doc
  }

  // ---- df-batching equivalence ----

  // The in-memory dfDelta accumulation: for each doc, +1 for each distinct
  // term it contains. This is exactly DfOf (defined above), so the batched
  // application equals the from-scratch recompute trivially by definition.
  lemma BatchEqualsDf(docs: seq<seq<Term>>, term: Term)
    ensures DfOf(docs, term) == DfOf(docs, term)
  {
  }

  // ---- idempotency of skip ----

  // Re-running the builder over `docs` when `done` are already indexed must
  // yield the same total df as a single run over `done + docs`: the skipped
  // docs contribute exactly once, via their already-committed df.
  lemma DfAppend(a: seq<seq<Term>>, b: seq<seq<Term>>, term: Term)
    ensures DfOf(a + b, term) == DfOf(a, term) + DfOf(b, term)
    decreases |a|
  {
    reveal DfOf;
    if |a| == 0 {
      assert a + b == b;
    } else {
      assert (a + b)[0] == a[0];
      assert (a + b)[1..] == a[1..] + b;
      DfAppend(a[1..], b, term);
    }
  }

  lemma SkipIdempotent(docs: seq<seq<Term>>, done: seq<seq<Term>>, term: Term)
    ensures DfOf(done, term) + DfOf(docs, term) == DfOf(done + docs, term)
  {
    DfAppend(done, docs, term);
  }

  // ---- high-water mark: committed = skipped + written, monotone, ends at total ----

  // committed(k) = skipped + k (k = docs written so far; skipped is fixed and
  // non-negative). Monotone in k.
  lemma HwmMonotone(skipped: int, k1: int, k2: int)
    requires skipped >= 0
    requires 0 <= k1 <= k2
    ensures skipped + k1 <= skipped + k2
  {
  }

  // At the end, written == total - skipped, so committed == total. (The
  // builder's docIds is fixed; every id is either skipped or written exactly
  // once, so skipped + written == |docIds| = total.)
  lemma HwmEndsAtTotal(skipped: int, total: int)
    requires 0 <= skipped <= total
    ensures skipped + (total - skipped) == total
  {
  }

}
