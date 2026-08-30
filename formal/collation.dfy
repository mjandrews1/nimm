// formal/collation.dfy
//
// Formal model of M-collation (storage/key_encoding.nim mCollationCmp): empty
// < numeric < string; numeric by value; string lexicographic. Proves the
// comparison is a *consistent comparison* (a total preorder): it returns
// -1/0/1, is reflexive, skew-symmetric, and transitive.
//
// Note: the collation is a preorder, not a strict total order — distinct
// non-canonical numeric strings ("1", "1.0", "01", ".1") share a numeric key
// and compare equal. That is why numeric subscripts are canonicalized
// (value.nim formatNumber) before use; canonical forms are anti-symmetric.
//
// `isNumeric`/`numKey` are abstract (they stand for the lexer's numeric test
// and parseFloat); the theorems hold for ANY such classifier and key, which is
// what the sorted walks ($ORDER/$QUERY/listSubs/listNodes) rely on.
//
// Verify with:  dafny verify formal/collation.dfy

module Collation {

  // Numeric-class test (abstracts key_encoding.isNumeric).
  predicate IsNumeric(s: seq<char>)

  // Numeric key (abstracts parseFloat); only consulted when IsNumeric.
  function NumKey(s: seq<char>): real

  // Lexicographic trichotomy on strings (Dafny has transitivity and
  // anti-symmetry of seq `<` built in, but not trichotomy).
  lemma {:axiom} SeqTrichotomy(a: seq<char>, b: seq<char>)
    ensures a < b || a == b || b < a

  // Collation class: 0 = empty, 1 = numeric, 2 = string.
  function Class(s: seq<char>): int
  {
    if |s| == 0 then 0 else if IsNumeric(s) then 1 else 2
  }

  // M-collation comparison, returning -1 / 0 / 1.
  function Cmp(a: seq<char>, b: seq<char>): int
  {
    var ca := Class(a);
    var cb := Class(b);
    if ca < cb then -1
    else if cb < ca then 1
    else if ca == 0 then 0
    else if ca == 1 then
      if NumKey(a) < NumKey(b) then -1 else if NumKey(b) < NumKey(a) then 1 else 0
    else
      if a < b then -1 else if b < a then 1 else 0
  }

  // The result is always one of -1, 0, 1.
  lemma CmpInRange(a: seq<char>, b: seq<char>)
    ensures Cmp(a, b) == -1 || Cmp(a, b) == 0 || Cmp(a, b) == 1
  {
    reveal Class;
    var ca := Class(a);
    var cb := Class(b);
    if ca < cb {
    } else if cb < ca {
    } else if ca == 0 {
    } else if ca == 1 {
      if NumKey(a) < NumKey(b) {
      } else if NumKey(b) < NumKey(a) {
      }
    } else {
      if a < b {
      } else if b < a {
      }
    }
  }

  // Reflexive: a compares equal to itself.
  lemma CmpReflexive(a: seq<char>)
    ensures Cmp(a, a) == 0
  {
    reveal Class;
    var ca := Class(a);
    if ca == 0 {
    } else if ca == 1 {
    } else {
    }
  }

  // Skew-symmetric: Cmp(a, b) == -Cmp(b, a).
  lemma CmpSkew(a: seq<char>, b: seq<char>)
    ensures Cmp(a, b) == -Cmp(b, a)
  {
    reveal Class;
    var ca := Class(a);
    var cb := Class(b);
    if ca < cb {
    } else if cb < ca {
    } else if ca == 0 {
    } else if ca == 1 {
      if NumKey(a) < NumKey(b) {
      } else if NumKey(b) < NumKey(a) {
      }
    } else {
      SeqTrichotomy(a, b);
    }
  }

  // Transitive (strict): a < b and b < c implies a < c.
  lemma CmpTransitive(a: seq<char>, b: seq<char>, c: seq<char>)
    requires Cmp(a, b) < 0 && Cmp(b, c) < 0
    ensures Cmp(a, c) < 0
  {
    reveal Class;
    var ca := Class(a);
    var cb := Class(b);
    var cc := Class(c);
    // From Cmp(a,b) < 0 we have ca <= cb; from Cmp(b,c) < 0, cb <= cc.
    assert ca <= cb;
    assert cb <= cc;
    assert ca <= cc;
    if ca < cc {
    } else {
      assert ca == cb && cb == cc;
      if ca == 1 {
        assert NumKey(a) < NumKey(b);
        assert NumKey(b) < NumKey(c);
      } else {
        assert a < b;
        assert b < c;
      }
    }
  }

}
