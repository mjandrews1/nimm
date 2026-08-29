// formal/order_pairs.dfy
//
// Formal model of the multi-level $ORDER candidate extraction (globals.nim
// orderPairs): the result subscript is at depth |subs|-1 (or 0 for a bare
// $ORDER), under the parent path, and — for two qualifying nodes — the tuple
// order at that level agrees with the subscript order (so extracting
// candidates from a TupCmp-sorted list yields Cmp-sorted candidates). Also
// formalizes §9.9 (backward from the null subscript returns nothing).
//
// Verify with:  dafny verify formal/key_encoding.dfy formal/globals_order.dfy formal/order_pairs.dfy

module OrderPairs {

  import opened KeyEncoding
  import opened GlobalsOrder

  // The result level: |subs| - 1, or 0 for a bare $ORDER (no subscripts).
  function CandLevel(subs: seq<Sub>): nat {
    if |subs| == 0 then 0 else |subs| - 1
  }

  // A node qualifies as a candidate source iff it is deeper than candLevel and
  // (for |subs| >= 2) its parent path matches subs[..|subs|-1].
  predicate Qualifies(node: seq<Sub>, subs: seq<Sub>) {
    |node| > CandLevel(subs) &&
    (|subs| <= 1 || node[..|subs| - 1] == subs[..|subs| - 1])
  }

  // The candidate subscript extracted from a qualifying node.
  function CandidateOf(node: seq<Sub>, subs: seq<Sub>): Sub
    requires |node| > CandLevel(subs)
  {
    node[CandLevel(subs)]
  }

  // §9.9: nothing sorts strictly below Empty, so backward from the null
  // subscript has no predecessor.
  lemma BackwardFromEmptyIsNothing(c: Sub)
    ensures !(Cmp(c, Empty) < 0)
  {
    EmptyIsMin(c);
    CmpAntisymmetric(Empty, c);
  }

  // TupCmp of two non-empty sequences with different heads reduces to Cmp of
  // the heads.
  lemma TupCmpHeadNeq(a: seq<Sub>, b: seq<Sub>)
    requires |a| > 0 && |b| > 0 && a[0] != b[0]
    ensures TupCmp(a, b) == Cmp(a[0], b[0])
  {
    reveal TupCmp;
  }

  // TupCmp of two sequences sharing a common prefix of length k reduces to
  // TupCmp of their tails.
  lemma TupCmpCommonPrefix(n1: seq<Sub>, n2: seq<Sub>, k: nat)
    requires |n1| >= k && |n2| >= k
    requires n1[..k] == n2[..k]
    ensures TupCmp(n1, n2) == TupCmp(n1[k..], n2[k..])
    decreases k
  {
    reveal TupCmp;
    if k > 0 {
      assert n1[0] == n2[0];
      TupCmpCommonPrefix(n1[1..], n2[1..], k - 1);
    }
  }

  // The candidate extraction preserves order: if the candidate of n1 sorts
  // before the candidate of n2, then n1 sorts before n2 in tuple order.
  // (So a TupCmp-sorted node list yields Cmp-sorted candidates.)
  lemma CandidateOrderImpliesTupleOrder(n1: seq<Sub>, n2: seq<Sub>, subs: seq<Sub>)
    requires Qualifies(n1, subs) && Qualifies(n2, subs)
    ensures Cmp(CandidateOf(n1, subs), CandidateOf(n2, subs)) < 0 ==>
            TupCmp(n1, n2) < 0
  {
    reveal Qualifies;
    reveal Cmp;
    var k := CandLevel(subs);
    if Cmp(CandidateOf(n1, subs), CandidateOf(n2, subs)) < 0 {
      assert n1[k] != n2[k];
      if |subs| <= 1 {
        TupCmpHeadNeq(n1, n2);
      } else {
        assert n1[..k] == n2[..k];
        TupCmpCommonPrefix(n1, n2, k);
        TupCmpHeadNeq(n1[k..], n2[k..]);
      }
    }
  }

}
