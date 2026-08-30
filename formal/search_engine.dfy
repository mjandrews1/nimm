// formal/search_engine.dfy
//
// Formal model of the FST SearchEngine index invariants
// (future_search_tool/src/fst_core.nim + bm25.nim):
//   - docFreq counts *documents* containing a term, not occurrences (df vs tf).
//   - the incremental addDocument matches a from-scratch recompute.
//   - the docId -> vector-id mapping is injective (each doc indexed once).
//
// Verify with:  dafny verify formal/search_engine.dfy

module SearchEngineModel {

  // ============ term frequency vs document frequency ============
  // tf: number of occurrences of `term` in a document (token list).
  function Tf(tokens: seq<string>, term: string): int
    decreases |tokens|
  {
    if |tokens| == 0 then 0
    else (if tokens[0] == term then 1 else 0) + Tf(tokens[1..], term)
  }

  // df: number of documents (in `docs`) containing `term` at least once.
  function Df(docs: seq<seq<string>>, term: string): int
    decreases |docs|
  {
    if |docs| == 0 then 0
    else (if Tf(docs[0], term) > 0 then 1 else 0) + Df(docs[1..], term)
  }

  // The incremental addDocument increments df by 1 when the new document
  // contains the term (matching bm25.nim, which iterates unique terms once).
  lemma DfAppend(docs: seq<seq<string>>, newDoc: seq<string>, term: string)
    ensures Df(docs + [newDoc], term) ==
            Df(docs, term) + (if Tf(newDoc, term) > 0 then 1 else 0)
    decreases |docs|
  {
    reveal Df;
    if |docs| == 0 {
    } else {
      DfAppend(docs[1..], newDoc, term);
      assert (docs + [newDoc])[0] == docs[0];
      assert (docs + [newDoc])[1..] == docs[1..] + [newDoc];
    }
  }

  // df counts documents, not occurrences: a document with a repeated term
  // still contributes exactly 1, whereas tf counts each occurrence.
  lemma DfCountsDocumentsNotOccurrences()
    ensures Df([["hello", "hello", "world"]], "hello") == 1
    ensures Tf(["hello", "hello", "world"], "hello") == 2
  {
  }

  // ============ docId -> vector-id bijection ============
  // The SearchEngine assigns each docId a fresh vector id and keeps the
  // reverse map injective (so vector results map back to a unique doc).
  type VecMap = imap<int, string>

  ghost predicate Injective(m: VecMap)
  {
    forall a, b | a in m && b in m && a != b :: m[a] != m[b]
  }

  // Assign a fresh id (nextVecId) to a docId.
  function Assign(m: VecMap, nextVecId: int, docId: string): VecMap
  {
    m[nextVecId := docId]
  }

  // A fresh id + a not-yet-mapped docId preserve injectivity. The docId-not-
  // mapped precondition is the "index each doc once" discipline that
  // indexDocument must enforce.
  lemma AssignFreshPreservesInjective(m: VecMap, nextVecId: int, docId: string)
    requires nextVecId !in m
    requires forall k | k in m :: m[k] != docId
    requires Injective(m)
    ensures Injective(Assign(m, nextVecId, docId))
  {
  }

}
