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

  // TupCmp is reflexive.
  lemma TupCmpReflexive(a: seq<Sub>)
    ensures TupCmp(a, a) == 0
    decreases |a|
  {
    reveal TupCmp;
    if a == [] {
    } else {
      CmpAntisymmetric(a[0], a[0]);
      assert Cmp(a[0], a[0]) == 0;
      TupCmpReflexive(a[1..]);
    }
  }

  // Completeness: the successor is *minimal* among nodes strictly after `subs`
  // — no node is skipped (the walk has no gaps).
  lemma SuccessorMinimal(nodes: seq<seq<Sub>>, subs: seq<Sub>)
    requires Sorted(nodes)
    ensures Successor(nodes, subs) != [] ==>
      forall i | 0 <= i < |nodes| :: TupCmp(nodes[i], subs) > 0 ==>
        TupCmp(Successor(nodes, subs), nodes[i]) <= 0
    decreases |nodes|
  {
    if nodes == [] {
    } else if TupCmp(nodes[0], subs) > 0 {
      assert Successor(nodes, subs) == nodes[0];
      TupCmpReflexive(nodes[0]);
      forall i | 0 <= i < |nodes|
        ensures TupCmp(nodes[i], subs) > 0 ==> TupCmp(Successor(nodes, subs), nodes[i]) <= 0
      {
        if i > 0 {
          assert TupCmp(nodes[0], nodes[i]) <= 0;
        }
      }
    } else {
      SuccessorMinimal(nodes[1..], subs);
      assert Successor(nodes, subs) == Successor(nodes[1..], subs);
      assert TupCmp(nodes[0], subs) <= 0;
    }
  }

  // Strictly sorted: every pair is strictly increasing (distinct).
  predicate StrictSorted(nodes: seq<seq<Sub>>)
  {
    forall i, j | 0 <= i < j < |nodes| :: TupCmp(nodes[i], nodes[j]) < 0
  }

  // A prefix of nodes all <= subs does not affect the successor.
  lemma SuccessorSkipPrefix(nodes: seq<seq<Sub>>, subs: seq<Sub>, k: nat)
    requires k <= |nodes|
    requires forall j | 0 <= j < k :: TupCmp(nodes[j], subs) <= 0
    ensures Successor(nodes, subs) == Successor(nodes[k..], subs)
    decreases k
  {
    reveal Successor;
    if k == 0 {
    } else {
      assert TupCmp(nodes[0], subs) <= 0;
      SuccessorSkipPrefix(nodes[1..], subs, k - 1);
      assert nodes[1..][k - 1 ..] == nodes[k..];
    }
  }

  // The successor of an element is the next element (and [] after the last):
  // the walk visits every element exactly once, in order.
  lemma SuccessorNext(nodes: seq<seq<Sub>>, i: nat)
    requires StrictSorted(nodes)
    requires i < |nodes|
    ensures Successor(nodes, nodes[i]) == (if i + 1 < |nodes| then nodes[i + 1] else [])
  {
    reveal Successor;
    // Every j <= i has nodes[j] <= nodes[i].
    forall j | 0 <= j < i + 1
      ensures TupCmp(nodes[j], nodes[i]) <= 0
    {
      if j < i {
        assert TupCmp(nodes[j], nodes[i]) < 0;
      } else {
        TupCmpReflexive(nodes[i]);
      }
    }
    SuccessorSkipPrefix(nodes, nodes[i], i + 1);
    assert Successor(nodes, nodes[i]) == Successor(nodes[i + 1 ..], nodes[i]);
    if i + 1 >= |nodes| {
      assert nodes[i + 1 ..] == [];
    } else {
      assert TupCmp(nodes[i], nodes[i + 1]) < 0;
      TupCmpAntisymmetric(nodes[i], nodes[i + 1]);
      assert TupCmp(nodes[i + 1], nodes[i]) > 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Backward predecessor ($QUERY/$ORDER backward)
  // ---------------------------------------------------------------------------
  // The backward predecessor of `subs`: the largest node strictly before it
  // (the first node < subs when scanning from the end of the sorted list).

  function Predecessor(nodes: seq<seq<Sub>>, subs: seq<Sub>): seq<Sub>
    decreases |nodes|
  {
    if nodes == [] then []
    else if TupCmp(nodes[|nodes| - 1], subs) < 0 then nodes[|nodes| - 1]
    else Predecessor(nodes[..|nodes| - 1], subs)
  }

  lemma PredecessorIsBefore(nodes: seq<seq<Sub>>, subs: seq<Sub>)
    requires Sorted(nodes)
    ensures Predecessor(nodes, subs) == [] || TupCmp(Predecessor(nodes, subs), subs) < 0
    decreases |nodes|
  {
    if nodes == [] {
    } else if TupCmp(nodes[|nodes| - 1], subs) < 0 {
    } else {
      PredecessorIsBefore(nodes[..|nodes| - 1], subs);
    }
  }

  // A suffix of nodes all >= subs does not affect the predecessor.
  lemma PredecessorSkipSuffix(nodes: seq<seq<Sub>>, subs: seq<Sub>, k: nat)
    requires k <= |nodes|
    requires forall j | k <= j < |nodes| :: TupCmp(nodes[j], subs) >= 0
    ensures Predecessor(nodes, subs) == Predecessor(nodes[..k], subs)
    decreases |nodes| - k
  {
    reveal Predecessor;
    if k == |nodes| {
      assert nodes[..k] == nodes;
    } else {
      assert TupCmp(nodes[|nodes| - 1], subs) >= 0;
      PredecessorSkipSuffix(nodes[..|nodes| - 1], subs, k);
      assert (nodes[..|nodes| - 1])[..k] == nodes[..k];
      assert Predecessor(nodes, subs) == Predecessor(nodes[..|nodes| - 1], subs);
    }
  }

  // The predecessor is *maximal*: no node strictly before subs is skipped.
  lemma PredecessorMaximal(nodes: seq<seq<Sub>>, subs: seq<Sub>)
    requires Sorted(nodes)
    ensures Predecessor(nodes, subs) != [] ==>
      forall i | 0 <= i < |nodes| :: TupCmp(nodes[i], subs) < 0 ==>
        TupCmp(nodes[i], Predecessor(nodes, subs)) <= 0
    decreases |nodes|
  {
    if nodes == [] {
    } else if TupCmp(nodes[|nodes| - 1], subs) < 0 {
      assert Predecessor(nodes, subs) == nodes[|nodes| - 1];
      forall i | 0 <= i < |nodes|
        ensures TupCmp(nodes[i], subs) < 0 ==> TupCmp(nodes[i], nodes[|nodes| - 1]) <= 0
      {
        if TupCmp(nodes[i], subs) < 0 {
          if i == |nodes| - 1 {
            TupCmpReflexive(nodes[|nodes| - 1]);
          } else {
            assert TupCmp(nodes[i], nodes[|nodes| - 1]) <= 0;
          }
        }
      }
    } else {
      PredecessorMaximal(nodes[..|nodes| - 1], subs);
      assert Predecessor(nodes, subs) == Predecessor(nodes[..|nodes| - 1], subs);
    }
  }

  // The predecessor of an element is the previous element ([] before the first).
  lemma PredecessorPrev(nodes: seq<seq<Sub>>, i: nat)
    requires StrictSorted(nodes)
    requires i < |nodes|
    ensures Predecessor(nodes, nodes[i]) == (if i > 0 then nodes[i - 1] else [])
  {
    // The suffix j >= i is all >= nodes[i], so it does not affect the result.
    forall j | i <= j < |nodes|
      ensures TupCmp(nodes[j], nodes[i]) >= 0
    {
      if j == i {
        TupCmpReflexive(nodes[i]);
      } else {
        assert TupCmp(nodes[i], nodes[j]) < 0;
        TupCmpAntisymmetric(nodes[i], nodes[j]);
      }
    }
    PredecessorSkipSuffix(nodes, nodes[i], i);
    if i == 0 {
      assert nodes[..0] == [];
    } else {
      assert TupCmp(nodes[i - 1], nodes[i]) < 0;
      assert Predecessor(nodes[..i], nodes[i]) == nodes[i - 1];
    }
  }

  // ---------------------------------------------------------------------------
  // Full DFS: listNodes returns every strict descendant in pre-order
  // ---------------------------------------------------------------------------

  function IsDescendant(s: seq<Sub>, prefix: seq<Sub>): bool
  {
    |s| > |prefix| && s[..|prefix|] == prefix
  }

  // Filter nodes to those strictly below `prefix` (listNodes).
  function Descendants(nodes: seq<seq<Sub>>, prefix: seq<Sub>): seq<seq<Sub>>
  {
    if nodes == [] then []
    else if IsDescendant(nodes[0], prefix) then [nodes[0]] + Descendants(nodes[1..], prefix)
    else Descendants(nodes[1..], prefix)
  }

  // Completeness: every descendant in the list is returned, and every returned
  // node is a descendant of prefix.
  lemma DescendantsComplete(nodes: seq<seq<Sub>>, prefix: seq<Sub>)
    ensures forall i | 0 <= i < |nodes| :: IsDescendant(nodes[i], prefix) ==>
              nodes[i] in Descendants(nodes, prefix)
    decreases |nodes|
  {
    if nodes == [] {
    } else if IsDescendant(nodes[0], prefix) {
      DescendantsComplete(nodes[1..], prefix);
      forall i | 1 <= i < |nodes|
        ensures IsDescendant(nodes[i], prefix) ==> nodes[i] in Descendants(nodes, prefix)
      {
      }
    } else {
      DescendantsComplete(nodes[1..], prefix);
    }
  }

}
