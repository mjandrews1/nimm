// formal/globals_order.dfy
//
// Formal model of the ordering primitives in globals.nim that `$ORDER` and
// `$QUERY` build on: tupCollationCmp (DFS pre-order over subscript tuples)
// and the §9.9 "empty is the minimum" rule.
//
// Verify with:  dafny verify formal/key_encoding.dfy formal/globals_order.dfy

module GlobalsOrder {

  import opened KeyEncoding

  // Tuple collation — the lexicographic extension of Cmp over subscript
  // tuples; a shorter prefix sorts first. This is tupCollationCmp in
  // globals.nim, i.e. depth-first pre-order over the key tree.
  function TupCmp(a: seq<Sub>, b: seq<Sub>): int
    decreases |a| + |b|
  {
    if a == [] then if b == [] then 0 else -1
    else if b == [] then 1
    else
      var c := Cmp(a[0], b[0]);
      if c != 0 then c else TupCmp(a[1..], b[1..])
  }

  lemma TupCmpAntisymmetric(a: seq<Sub>, b: seq<Sub>)
    ensures TupCmp(a, b) == -TupCmp(b, a)
    decreases |a| + |b|
  {
    reveal TupCmp;
    if a == [] {
    } else if b == [] {
    } else {
      var c := Cmp(a[0], b[0]);
      if c == 0 {
        TupCmpAntisymmetric(a[1..], b[1..]);
      } else {
        CmpAntisymmetric(a[0], b[0]);
      }
    }
  }

  lemma TupCmpTransitive(a: seq<Sub>, b: seq<Sub>, c: seq<Sub>)
    requires TupCmp(a, b) <= 0 && TupCmp(b, c) <= 0
    ensures TupCmp(a, c) <= 0
    decreases |a| + |b| + |c|
  {
    reveal TupCmp;
    reveal Cmp;
    if a == [] {
    } else if b == [] || c == [] {
    } else {
      var cab := Cmp(a[0], b[0]);
      var cbc := Cmp(b[0], c[0]);
      if cab < 0 {
        // a[0] < b[0]; TupCmp(b,c) <= 0 gives b[0] <= c[0], so a[0] < c[0].
        assert cbc <= 0;
        CmpStrictTrans(a[0], b[0], c[0]);
      } else if cab == 0 {
        if cbc < 0 {
          assert Cmp(a[0], c[0]) < 0;
        } else {
          TupCmpTransitive(a[1..], b[1..], c[1..]);
        }
      }
    }
  }

  // Empty is the minimum subscript (the basis for §9.9: backward from the
  // null subscript returns nothing).
  lemma EmptyIsMin(x: Sub)
    ensures Cmp(Empty, x) <= 0
  {
    reveal Cmp;
  }

  // ---------------------------------------------------------------------------
  // $QUERY successor (spec, over a TupCmp-sorted list of nodes)
  // ---------------------------------------------------------------------------
  //
  // queryPairs returns the first node strictly after `subs` in DFS pre-order.
  // Modeled as a total function over the SORTED node list; the sortedness of
  // the real store is enforced by the Nim implementation (pairs.sort) and by
  // the store-parity test.

  predicate Sorted(nodes: seq<seq<Sub>>)
  {
    forall i, j | 0 <= i < j < |nodes| :: TupCmp(nodes[i], nodes[j]) <= 0
  }

  // The forward successor of `subs`: first node strictly greater in TupCmp.
  function Successor(nodes: seq<seq<Sub>>, subs: seq<Sub>): seq<Sub>
  {
    if nodes == [] then []
    else if TupCmp(nodes[0], subs) > 0 then nodes[0]
    else Successor(nodes[1..], subs)
  }

  lemma SuccessorIsAfter(nodes: seq<seq<Sub>>, subs: seq<Sub>)
    requires Sorted(nodes)
    ensures Successor(nodes, subs) == [] || TupCmp(Successor(nodes, subs), subs) > 0
  {
    if nodes == [] {
    } else if TupCmp(nodes[0], subs) > 0 {
    } else {
      SuccessorIsAfter(nodes[1..], subs);
    }
  }

}
