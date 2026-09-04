// formal/query_semantics.dfy
//
// Formal model of the SELECT-only SQL layer (future_search_tool/src/sql_select.nim,
// #462 M1): after the planner binds a prefix of the key columns, the executor
// walks the final key column in ascending Cmp order ($ORDER) and emits rows
// while they satisfy the range predicate, stopping early at the upper bound or
// after LIMIT. Modeled over the sorted walked-key sequence (the Nim store's
// sortedness is enforced by $ORDER itself).
//
// Verify with:  dafny verify formal/key_encoding.dfy formal/query_semantics.dfy

module QuerySemantics {

  import opened KeyEncoding

  // A relation table after prefix binding: the sorted sequence of the walked
  // key column's values, strictly increasing in M collation.
  predicate SortedKeys(keys: seq<Sub>)
  {
    forall i, j | 0 <= i < j < |keys| :: Cmp(keys[i], keys[j]) < 0
  }

  // Range predicate. Empty low/high means "unbounded" on that side (the SQL
  // literal can never be Empty, so no real key collides with the sentinel).
  predicate InRange(k: Sub, low: Sub, high: Sub, loInc: bool, hiInc: bool)
  {
    (low.Empty? || (loInc && Cmp(k, low) >= 0) || (!loInc && Cmp(k, low) > 0)) &&
    (high.Empty? || (hiInc && Cmp(k, high) <= 0) || (!hiInc && Cmp(k, high) < 0))
  }

  // The unbounded result of a range scan: every key in range, in order.
  function ScanAll(keys: seq<Sub>, low: Sub, high: Sub, loInc: bool, hiInc: bool): seq<Sub>
    decreases |keys|
  {
    if keys == [] then []
    else if InRange(keys[0], low, high, loInc, hiInc) then
      [keys[0]] + ScanAll(keys[1..], low, high, loInc, hiInc)
    else
      ScanAll(keys[1..], low, high, loInc, hiInc)
  }

  // LIMIT k: the first k elements.
  function Take(keys: seq<Sub>, k: nat): seq<Sub>
  {
    if keys == [] || k == 0 then [] else [keys[0]] + Take(keys[1..], k - 1)
  }

  // Point lookup (all key columns bound): one row iff the key is present.
  function PointLookup(keys: set<Sub>, k: Sub): nat
  {
    if k in keys then 1 else 0
  }

  // Soundness: every emitted row satisfies the range predicate.
  lemma ScanAllSound(keys: seq<Sub>, low: Sub, high: Sub, loInc: bool, hiInc: bool)
    ensures forall i | 0 <= i < |ScanAll(keys, low, high, loInc, hiInc)| ::
              InRange(ScanAll(keys, low, high, loInc, hiInc)[i], low, high, loInc, hiInc)
    decreases |keys|
  {
    if keys == [] {
    } else {
      ScanAllSound(keys[1..], low, high, loInc, hiInc);
    }
  }

  // Completeness: every in-range key in the store is emitted.
  lemma ScanAllComplete(keys: seq<Sub>, low: Sub, high: Sub, loInc: bool, hiInc: bool)
    ensures forall i | 0 <= i < |keys| ::
              InRange(keys[i], low, high, loInc, hiInc) ==>
                keys[i] in ScanAll(keys, low, high, loInc, hiInc)
    decreases |keys|
  {
    if keys == [] {
    } else {
      ScanAllComplete(keys[1..], low, high, loInc, hiInc);
    }
  }

  // Every element emitted by ScanAll comes from the input (a subsequence).
  lemma ScanAllFromKeys(keys: seq<Sub>, low: Sub, high: Sub, loInc: bool, hiInc: bool)
    ensures forall i | 0 <= i < |ScanAll(keys, low, high, loInc, hiInc)| ::
              ScanAll(keys, low, high, loInc, hiInc)[i] in keys
    decreases |keys|
  {
    if keys == [] {
    } else {
      ScanAllFromKeys(keys[1..], low, high, loInc, hiInc);
    }
  }

  // In a strictly sorted sequence, the head precedes every element of the tail.
  lemma HeadLtRest(keys: seq<Sub>, x: Sub)
    requires SortedKeys(keys)
    requires keys != []
    requires x in keys[1..]
    ensures Cmp(keys[0], x) < 0
  {
    var j :| 0 <= j < |keys[1..]| && keys[1..][j] == x;
    assert keys[1..][j] == keys[j + 1];
    assert Cmp(keys[0], keys[j + 1]) < 0;
  }

  // The scan preserves the store's order, so ORDER BY on the walked column is
  // free (no sort).
  lemma ScanAllPreservesOrder(keys: seq<Sub>, low: Sub, high: Sub, loInc: bool, hiInc: bool)
    requires SortedKeys(keys)
    ensures SortedKeys(ScanAll(keys, low, high, loInc, hiInc))
    decreases |keys|
  {
    if keys == [] {
    } else if InRange(keys[0], low, high, loInc, hiInc) {
      ScanAllPreservesOrder(keys[1..], low, high, loInc, hiInc);
      ScanAllFromKeys(keys[1..], low, high, loInc, hiInc);
      forall i | 0 <= i < |ScanAll(keys[1..], low, high, loInc, hiInc)|
        ensures Cmp(keys[0], ScanAll(keys[1..], low, high, loInc, hiInc)[i]) < 0
      {
        HeadLtRest(keys, ScanAll(keys[1..], low, high, loInc, hiInc)[i]);
      }
    } else {
      ScanAllPreservesOrder(keys[1..], low, high, loInc, hiInc);
    }
  }

  // LIMIT k yields a prefix of the unbounded result (and never more than k).
  lemma TakeIsPrefix(keys: seq<Sub>, k: nat)
    ensures |Take(keys, k)| <= |keys|
    ensures forall i | 0 <= i < |Take(keys, k)| :: Take(keys, k)[i] == keys[i]
  {
    if keys == [] || k == 0 {
    } else {
      TakeIsPrefix(keys[1..], k - 1);
      assert Take(keys, k) == [keys[0]] + Take(keys[1..], k - 1);
      assert Take(keys, k)[0] == keys[0];
      assert |Take(keys, k)| == 1 + |Take(keys[1..], k - 1)|;
      assert |Take(keys, k)| <= |keys|;
      forall i | 1 <= i < |Take(keys, k)|
        ensures Take(keys, k)[i] == keys[i]
      {
        assert Take(keys, k)[i] == Take(keys[1..], k - 1)[i - 1];
        assert Take(keys[1..], k - 1)[i - 1] == keys[1..][i - 1];
        assert keys[1..][i - 1] == keys[i];
      }
    }
  }

  lemma TakeBounded(keys: seq<Sub>, k: nat)
    ensures |Take(keys, k)| <= k
  {
    if keys == [] || k == 0 {
    } else {
      TakeBounded(keys[1..], k - 1);
    }
  }

  // Point lookup returns exactly one row iff the key is present, zero otherwise.
  lemma PointLookupCount(keys: set<Sub>, k: Sub)
    ensures PointLookup(keys, k) == (if k in keys then 1 else 0)
  {
  }

  // ---------------------------------------------------------------------------
  // M2: nested-index join (driving walk × joined point-lookup)
  // ---------------------------------------------------------------------------
  //
  // The driving table is walked in ascending Cmp order over the ON column; each
  // driving key is looked up as the joined table's leading key. A row is emitted
  // iff the joined key is present. Modeled over the sorted driving-key sequence
  // and a `present: set<Sub>` of joined keys that exist.

  // Rows emitted by the join: the driving keys whose joined record exists, in
  // walk order.
  function JoinRows(driving: seq<Sub>, present: set<Sub>): seq<Sub>
    decreases |driving|
  {
    if driving == [] then []
    else if driving[0] in present then [driving[0]] + JoinRows(driving[1..], present)
    else JoinRows(driving[1..], present)
  }

  // Soundness: every emitted row's joined key exists.
  lemma JoinSoundness(driving: seq<Sub>, present: set<Sub>)
    ensures forall i | 0 <= i < |JoinRows(driving, present)| ::
              JoinRows(driving, present)[i] in present
    decreases |driving|
  {
    if driving == [] {
    } else {
      JoinSoundness(driving[1..], present);
    }
  }

  // Completeness: every driving key whose joined record exists is emitted.
  lemma JoinCompleteness(driving: seq<Sub>, present: set<Sub>)
    ensures forall i | 0 <= i < |driving| ::
              driving[i] in present ==> driving[i] in JoinRows(driving, present)
    decreases |driving|
  {
    if driving == [] {
    } else {
      JoinCompleteness(driving[1..], present);
    }
  }

  // The join result is exactly the set intersection of the driving keys and the
  // joined relation — i.e. the nested-index join and a merge join agree, so the
  // M2 planner may choose either without changing results.
  ghost function DrivingSet(driving: seq<Sub>): set<Sub>
    decreases |driving|
  {
    if driving == [] then {} else {driving[0]} + DrivingSet(driving[1..])
  }

  lemma JoinIsIntersection(driving: seq<Sub>, present: set<Sub>)
    ensures DrivingSet(JoinRows(driving, present)) == DrivingSet(driving) * present
    decreases |driving|
  {
    reveal DrivingSet; reveal JoinRows;
    if driving == [] {
    } else if driving[0] in present {
      JoinIsIntersection(driving[1..], present);
    } else {
      JoinIsIntersection(driving[1..], present);
    }
  }

  // The join preserves walk order (free ORDER BY on the ON column).
  lemma JoinRowsFromDriving(driving: seq<Sub>, present: set<Sub>)
    ensures forall i | 0 <= i < |JoinRows(driving, present)| ::
              JoinRows(driving, present)[i] in DrivingSet(driving)
    decreases |driving|
  {
    reveal DrivingSet;
    if driving == [] {
    } else if driving[0] in present {
      JoinRowsFromDriving(driving[1..], present);
    } else {
      JoinRowsFromDriving(driving[1..], present);
    }
  }

  // In a sorted sequence, the head is strictly below every element of the tail,
  // stated over set membership (DrivingSet) rather than sequence membership.
  lemma HeadBelowSet(driving: seq<Sub>, x: Sub)
    requires SortedKeys(driving)
    requires driving != []
    requires x in DrivingSet(driving[1..])
    ensures Cmp(driving[0], x) < 0
    decreases |driving|
  {
    reveal DrivingSet;
    if driving == [] {
    } else if |driving| == 1 {
    } else {
      if x == driving[1] {
        assert Cmp(driving[0], driving[1]) < 0;
      } else {
        assert x in DrivingSet(driving[2..]);
        assert SortedKeys(driving[1..]);
        // reuse the head-vs-tail fact on the tail sequence
        HeadBelowSet(driving[1..], x);
        assert Cmp(driving[1], x) < 0;
        assert Cmp(driving[0], driving[1]) < 0;
        CmpStrictTrans(driving[0], driving[1], x);
      }
    }
  }

  lemma JoinPreservesOrder(driving: seq<Sub>, present: set<Sub>)
    requires SortedKeys(driving)
    ensures SortedKeys(JoinRows(driving, present))
    decreases |driving|
  {
    reveal DrivingSet;
    if driving == [] {
    } else if driving[0] in present {
      JoinPreservesOrder(driving[1..], present);
      JoinRowsFromDriving(driving[1..], present);
      forall i | 0 <= i < |JoinRows(driving[1..], present)|
        ensures Cmp(driving[0], JoinRows(driving[1..], present)[i]) < 0
      {
        HeadBelowSet(driving, JoinRows(driving[1..], present)[i]);
      }
    } else {
      JoinPreservesOrder(driving[1..], present);
    }
  }

}


