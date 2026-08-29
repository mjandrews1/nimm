// formal/entry_term_expansion.dfy
//
// Formal model of the FST entry-term expansion pipeline (bm25idx.m DICT +
// fst_search.py search_descriptors, #390).
//
// The pipeline merges two ranked lists:
//   dict  — entry-term dictionary hits (exact MeSH names, then synonyms)
//   bm25  — BM25-ranked hits
// into a single deduplicated, dict-first, capped list.
//
// Proved here:
//   1. The BM25 fill excludes every dict hit (and is itself duplicate-free).
//   2. The merged list has no duplicates.
//   3. The dict hits are a prefix of the merged list (dict-first ordering).
//   4. The capped result never exceeds the cap.
//
// Verify with:  dafny verify formal/entry_term_expansion.dfy

module EntryTermExpansion {

  type UI = string

  predicate NoDup(s: seq<UI>)
  {
    forall i, j | 0 <= i < j < |s| :: s[i] != s[j]
  }

  // Set of elements of s.
  function SetOf(s: seq<UI>): set<UI>
  {
    if |s| == 0 then {} else {s[0]} + SetOf(s[1..])
  }

  lemma SetOfContains(s: seq<UI>)
    ensures forall i | 0 <= i < |s| :: s[i] in SetOf(s)
    decreases |s|
  {
    if |s| > 0 {
      SetOfContains(s[1..]);
    }
  }

  // Filter s, dropping anything already in `seen` (and accumulating new hits).
  function FilterSeen(s: seq<UI>, seen: set<UI>): seq<UI>
    decreases |s|
  {
    if |s| == 0 then []
    else if s[0] in seen then FilterSeen(s[1..], seen)
    else [s[0]] + FilterSeen(s[1..], seen + {s[0]})
  }

  // FilterSeen is duplicate-free and disjoint from the initial `seen`.
  lemma FilterSeenGood(s: seq<UI>, seen: set<UI>)
    ensures NoDup(FilterSeen(s, seen))
    ensures forall i | 0 <= i < |FilterSeen(s, seen)| :: FilterSeen(s, seen)[i] !in seen
    decreases |s|
  {
    if |s| > 0 {
      if s[0] in seen {
        FilterSeenGood(s[1..], seen);
      } else {
        FilterSeenGood(s[1..], seen + {s[0]});
      }
    }
  }

  // Merge: dict hits first, then BM25 hits excluding any dict hit.
  function Merge(dict: seq<UI>, bm25: seq<UI>): seq<UI>
  {
    dict + FilterSeen(bm25, SetOf(dict))
  }

  lemma ConcatNoDup(a: seq<UI>, b: seq<UI>)
    requires NoDup(a) && NoDup(b)
    requires forall i | 0 <= i < |a| :: forall j | 0 <= j < |b| :: a[i] != b[j]
    ensures NoDup(a + b)
  {
    forall i, j | 0 <= i < j < |a| + |b|
      ensures (a + b)[i] != (a + b)[j]
    {
      if i < |a| && j >= |a| {
        assert (a + b)[i] == a[i];
        assert (a + b)[j] == b[j - |a|];
      }
    }
  }

  // No dict hit reappears in the BM25 fill.
  lemma MergeDisjoint(dict: seq<UI>, bm25: seq<UI>)
    ensures forall i | 0 <= i < |dict| ::
              forall j | 0 <= j < |FilterSeen(bm25, SetOf(dict))| ::
                dict[i] != FilterSeen(bm25, SetOf(dict))[j]
  {
    FilterSeenGood(bm25, SetOf(dict));
    SetOfContains(dict);
    forall i | 0 <= i < |dict|
      ensures forall j | 0 <= j < |FilterSeen(bm25, SetOf(dict))| ::
                dict[i] != FilterSeen(bm25, SetOf(dict))[j]
    {
      assert dict[i] in SetOf(dict);
      forall j | 0 <= j < |FilterSeen(bm25, SetOf(dict))|
        ensures dict[i] != FilterSeen(bm25, SetOf(dict))[j]
      {
        assert FilterSeen(bm25, SetOf(dict))[j] !in SetOf(dict);
      }
    }
  }

  // The merged list has no duplicates (given a duplicate-free dict).
  lemma MergeNoDup(dict: seq<UI>, bm25: seq<UI>)
    requires NoDup(dict)
    ensures NoDup(Merge(dict, bm25))
  {
    FilterSeenGood(bm25, SetOf(dict));
    MergeDisjoint(dict, bm25);
    ConcatNoDup(dict, FilterSeen(bm25, SetOf(dict)));
  }

  // The dict hits are a prefix of the merged list (dict-first ordering).
  lemma MergeDictFirst(dict: seq<UI>, bm25: seq<UI>)
    ensures Merge(dict, bm25)[..|dict|] == dict
  {
  }

  // Truncate to at most `cap` elements.
  function Truncate(s: seq<UI>, cap: int): seq<UI>
    decreases |s|
  {
    if cap <= 0 || |s| == 0 then []
    else [s[0]] + Truncate(s[1..], cap - 1)
  }

  lemma TruncateCapped(s: seq<UI>, cap: int)
    ensures |Truncate(s, cap)| <= (if cap > 0 then cap else 0)
    decreases |s|
  {
    if cap > 0 && |s| > 0 {
      TruncateCapped(s[1..], cap - 1);
    }
  }

  // The capped merge never exceeds the cap.
  lemma MergeCapped(dict: seq<UI>, bm25: seq<UI>, cap: int)
    ensures |Truncate(Merge(dict, bm25), cap)| <= (if cap > 0 then cap else 0)
  {
    TruncateCapped(Merge(dict, bm25), cap);
  }

}
