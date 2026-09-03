// formal/boolean_search.dfy
//
// Formal model of Boolean search over posting lists (#468). A term's match-set
// is a strictly-increasing sequence of doc-id ordinals (the ^BM25 posting list
// under M collation; here abstracted to `nat` ordinals, which is a surjective
// order-isomorphic image of the real string doc-ids). AND/OR/NOT combine them
// by zig-zag merge; no materialization.
//
// Proves, for each operator, soundness (emitted ordinal is in the semantic
// result) and completeness (every semantic result is emitted), plus
// commutativity/associativity so the planner may reorder by list length.
//
// Verify with:  dafny verify formal/boolean_search.dfy

module BooleanSearch {

  // Doc ids are natural-number ordinals. The real doc-ids are strings, but
  // their M-collation order is a total order isomorphic to `nat`, so reasoning
  // over ordinals is faithful and gives Dafny built-in trichotomy (which string
  // lacks).
  type Doc = nat

  // A posting list is strictly increasing (sorted, distinct) — the invariant
  // the ^BM25 walk provides; the head is the minimum.
  predicate SortedPosting(ids: seq<Doc>)
  {
    forall i | 1 <= i < |ids| :: ids[i - 1] < ids[i]
  }

  // Semantic model: membership in the list-as-a-set.
  ghost function ToSet(ids: seq<Doc>): set<Doc>
    decreases |ids|
  {
    if ids == [] then {} else {ids[0]} + ToSet(ids[1..])
  }

  // In a sorted list the head is strictly below every other element; combined
  // with a strict bound this says a smaller head is absent from the whole list.
  lemma SmallerHeadAbsent(a0: Doc, b: seq<Doc>)
    requires SortedPosting(b)
    requires b != []
    requires a0 < b[0]
    ensures a0 !in ToSet(b)
    decreases |b|
  {
    reveal ToSet;
    if |b| == 1 {
    } else {
      reveal ToSet;
      assert ToSet(b) == {b[0]} + ToSet(b[1..]);
      assert SortedPosting(b[1..]);
      assert b[0] < b[1..][0];
      SmallerHeadAbsent(a0, b[1..]);
    }
  }

  // --- Intersection (AND) ---

  // Zig-zag intersection implementation.
  ghost function Intersect(a: seq<Doc>, b: seq<Doc>): seq<Doc>
    decreases |a| + |b|
  {
    if a == [] || b == [] then []
    else if a[0] == b[0] then [a[0]] + Intersect(a[1..], b[1..])
    else if a[0] < b[0] then Intersect(a[1..], b)
    else Intersect(a, b[1..])
  }

  // Soundness: every emitted ordinal is in both sides.
  lemma {:vcs_split_on_every_assert} IntersectSound(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures forall d | d in ToSet(Intersect(a, b)) :: d in ToSet(a) && d in ToSet(b)
    decreases |a| + |b|
  {
    reveal Intersect; reveal ToSet;
    if a == [] || b == [] {
    } else if a[0] == b[0] {
      IntersectSound(a[1..], b[1..]);
    } else if a[0] < b[0] {
      IntersectSound(a[1..], b);
    } else {
      IntersectSound(a, b[1..]);
    }
  }

  // Completeness: every ordinal in both sides is emitted.
  lemma {:vcs_split_on_every_assert} IntersectComplete(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures forall d | d in ToSet(a) && d in ToSet(b) :: d in ToSet(Intersect(a, b))
    decreases |a| + |b|
  {
    reveal Intersect; reveal ToSet;
    if a == [] || b == [] {
    } else if a[0] == b[0] {
      IntersectComplete(a[1..], b[1..]);
    } else if a[0] < b[0] {
      SmallerHeadAbsent(a[0], b);
      IntersectComplete(a[1..], b);
    } else {
      // b[0] < a[0] (nat is trichotomous + irreflexive, so this `else` IS the
      // strictly-greater case).
      SmallerHeadAbsent(b[0], a);
      IntersectComplete(a, b[1..]);
    }
  }

  // --- Union (OR) ---

  ghost function Union(a: seq<Doc>, b: seq<Doc>): seq<Doc>
    decreases |a| + |b|
  {
    if a == [] then b
    else if b == [] then a
    else if a[0] == b[0] then [a[0]] + Union(a[1..], b[1..])
    else if a[0] < b[0] then [a[0]] + Union(a[1..], b)
    else [b[0]] + Union(a, b[1..])
  }

  lemma {:vcs_split_on_every_assert} UnionSound(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures forall d | d in ToSet(Union(a, b)) :: d in ToSet(a) || d in ToSet(b)
    decreases |a| + |b|
  {
    reveal Union; reveal ToSet;
    if a == [] || b == [] {
    } else if a[0] == b[0] {
      UnionSound(a[1..], b[1..]);
    } else if a[0] < b[0] {
      UnionSound(a[1..], b);
    } else {
      UnionSound(a, b[1..]);
    }
  }

  lemma {:vcs_split_on_every_assert} UnionComplete(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures forall d | d in ToSet(a) || d in ToSet(b) :: d in ToSet(Union(a, b))
    decreases |a| + |b|
  {
    reveal Union; reveal ToSet;
    if a == [] || b == [] {
    } else if a[0] == b[0] {
      UnionComplete(a[1..], b[1..]);
    } else if a[0] < b[0] {
      UnionComplete(a[1..], b);
    } else {
      UnionComplete(a, b[1..]);
    }
  }

  // --- Difference (NOT / A AND NOT B) ---

  ghost function Difference(a: seq<Doc>, b: seq<Doc>): seq<Doc>
    decreases |a| + |b|
  {
    if a == [] then []
    else if b == [] then a
    else if a[0] == b[0] then Difference(a[1..], b[1..])
    else if a[0] < b[0] then [a[0]] + Difference(a[1..], b)
    else Difference(a, b[1..])
  }

  lemma {:vcs_split_on_every_assert} DifferenceSound(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures forall d | d in ToSet(Difference(a, b)) :: d in ToSet(a) && d !in ToSet(b)
    decreases |a| + |b|
  {
    reveal Difference; reveal ToSet;
    if a == [] || b == [] {
    } else if a[0] == b[0] {
      DifferenceSound(a[1..], b[1..]);
    } else if a[0] < b[0] {
      SmallerHeadAbsent(a[0], b);
      DifferenceSound(a[1..], b);
    } else {
      // b[0] < a[0]: drop b[0] (it is absent from a).
      SmallerHeadAbsent(b[0], a);
      reveal Difference;
      assert Difference(a, b) == Difference(a, b[1..]);
      DifferenceSound(a, b[1..]);
    }
  }

  lemma {:vcs_split_on_every_assert} DifferenceComplete(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures forall d | d in ToSet(a) && d !in ToSet(b) :: d in ToSet(Difference(a, b))
    decreases |a| + |b|
  {
    reveal Difference; reveal ToSet;
    if a == [] || b == [] {
    } else if a[0] == b[0] {
      DifferenceComplete(a[1..], b[1..]);
    } else if a[0] < b[0] {
      SmallerHeadAbsent(a[0], b);
      DifferenceComplete(a[1..], b);
    } else {
      // b[0] < a[0]: drop b[0] (it is absent from a, so a keeps its elements).
      SmallerHeadAbsent(b[0], a);
      reveal Difference;
      assert Difference(a, b) == Difference(a, b[1..]);
      DifferenceComplete(a, b[1..]);
    }
  }

  // --- Commutativity/associativity at the semantic level ---
  // (The planner reorders operands by list length; results are unchanged.)

  lemma IntersectCommutative(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures ToSet(Intersect(a, b)) == ToSet(Intersect(b, a))
  {
    IntersectSound(a, b);
    IntersectComplete(a, b);
    IntersectSound(b, a);
    IntersectComplete(b, a);
  }

  lemma UnionCommutative(a: seq<Doc>, b: seq<Doc>)
    requires SortedPosting(a)
    requires SortedPosting(b)
    ensures ToSet(Union(a, b)) == ToSet(Union(b, a))
  {
    UnionSound(a, b);
    UnionComplete(a, b);
    UnionSound(b, a);
    UnionComplete(b, a);
  }

}
