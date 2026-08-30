// formal/string_functions.dfy
//
// Formal model of the pure string functions in evaluator.nim: $LENGTH,
// $EXTRACT, $FIND, $TRANSLATE. ($PIECE and $JUSTIFY are deferred — split/join
// and float formatting are modelled separately if needed.)
//
// Verify with:  dafny verify formal/string_functions.dfy

module StringFunctions {

  // --- $LENGTH ---
  function Length(s: seq<char>): int { |s| }

  // --- $EXTRACT (bounds-clamped substring, evaluator.nim:519) ---
  // first < 1 is clamped to 1; last > |s| is clamped to |s|; an empty range
  // (last < first, or first past the end) yields "".
  function Extract(s: seq<char>, first: int, last: int): seq<char> {
    var f := if first < 1 then 1 else first;
    var l := if last > |s| then |s| else last;
    if l < f || f > |s| then [] else s[f - 1 .. l]
  }

  // --- $FIND (substring search, evaluator.nim:538) ---
  // Returns 1 + (0-based index of the first match) + |f|, i.e. the 1-based
  // position just past the match; 0 if absent.
  predicate SubstringAt(s: seq<char>, f: seq<char>, i: nat) {
    i + |f| <= |s| && s[i .. i + |f|] == f
  }

  function FindAt(s: seq<char>, f: seq<char>, start: nat): int
    requires start <= |s|
    decreases |s| - start
  {
    if SubstringAt(s, f, start) then start
    else if start < |s| then FindAt(s, f, start + 1)
    else -1
  }

  function Find(s: seq<char>, f: seq<char>): int {
    var p := FindAt(s, f, 0);
    if p >= 0 then p + |f| + 1 else 0
  }

  // --- $TRANSLATE (character substitution, evaluator.nim:654) ---
  function IndexIn(ch: char, from: seq<char>): int
    decreases |from|
  {
    if |from| == 0 then -1
    else if from[0] == ch then 0
    else var r := IndexIn(ch, from[1..]); if r >= 0 then r + 1 else -1
  }

  function TranslateChar(ch: char, from: seq<char>, to: seq<char>): char {
    var i := IndexIn(ch, from);
    if i >= 0 && i < |to| then to[i] else ch
  }

  function Translate(s: seq<char>, from: seq<char>, to: seq<char>): seq<char>
    decreases |s|
  {
    if |s| == 0 then []
    else [TranslateChar(s[0], from, to)] + Translate(s[1..], from, to)
  }

  // --- Concrete cases ---
  lemma LengthHello() ensures Length("hello") == 5 { }
  lemma ExtractEll() ensures Extract("hello", 2, 4) == "ell" { }
  lemma ExtractFirst() ensures Extract("hello", 1, 1) == "h" { }
  lemma ExtractEmptyRange() ensures Extract("hello", 4, 2) == "" { }
  lemma ExtractClampFirst() ensures Extract("hello", 0, 3) == "hel" { }
  lemma ExtractClampLast() ensures Extract("hello", 1, 99) == "hello" { }
  lemma ExtractPastEnd() ensures Extract("hello", 6, 7) == "" { }
  lemma FindEll() ensures Find("hello", "ell") == 5 {
    reveal Find;
    reveal FindAt;
    reveal SubstringAt;
    assert "hello"[0..3] == "hel";
    assert "hel" != "ell";
    assert !SubstringAt("hello", "ell", 0);
    assert SubstringAt("hello", "ell", 1);
    assert FindAt("hello", "ell", 1) == 1;
    assert FindAt("hello", "ell", 0) == 1;
  }
  lemma FindAbsent() ensures Find("ab", "xy") == 0 {
    reveal Find;
    reveal FindAt;
    reveal SubstringAt;
    assert "ab" != "xy";
    assert FindAt("ab", "xy", 2) == -1;
    assert !SubstringAt("ab", "xy", 1);
    assert FindAt("ab", "xy", 1) == -1;
    assert !SubstringAt("ab", "xy", 0);
    assert FindAt("ab", "xy", 0) == -1;
  }
  lemma FindB() ensures Find("abc", "b") == 3 {
    reveal Find;
    reveal FindAt;
    reveal SubstringAt;
    assert "abc"[0..1] == "a";
    assert "a" != "b";
    assert !SubstringAt("abc", "b", 0);
    assert SubstringAt("abc", "b", 1);
    assert FindAt("abc", "b", 1) == 1;
    assert FindAt("abc", "b", 0) == 1;
  }
  lemma TranslateSimple() ensures Translate("abc", "a", "x") == "xbc" { }
  lemma TranslatePair() ensures Translate("abc", "ab", "xy") == "xyc" { }
  lemma TranslateRepeated() ensures Translate("hello", "l", "L") == "heLLo" { }

  // FindAt returns -1 or a non-negative index.
  lemma FindAtRange(s: seq<char>, f: seq<char>, start: nat)
    requires start <= |s|
    ensures FindAt(s, f, start) == -1 || FindAt(s, f, start) >= 0
    decreases |s| - start
  {
    reveal FindAt;
    if !SubstringAt(s, f, start) && start < |s| {
      FindAtRange(s, f, start + 1);
    }
  }

  // FindAt exhausts the search: if it returns -1, no match occurs at any
  // position >= start.
  lemma FindAtExhausts(s: seq<char>, f: seq<char>, start: nat)
    requires start <= |s|
    ensures FindAt(s, f, start) == -1 ==> forall i | start <= i <= |s| :: !SubstringAt(s, f, i)
    decreases |s| - start
  {
    reveal FindAt;
    if SubstringAt(s, f, start) {
    } else if start < |s| {
      FindAtExhausts(s, f, start + 1);
    } else {
    }
  }

  // Key property: $FIND is 0 only when the pattern is truly absent.
  lemma FindZeroMeansAbsent(s: seq<char>, f: seq<char>)
    requires f != []
    ensures Find(s, f) == 0 ==> !(exists i :: SubstringAt(s, f, i))
  {
    reveal Find;
    FindAtRange(s, f, 0);
    FindAtExhausts(s, f, 0);
    if Find(s, f) == 0 {
      assert FindAt(s, f, 0) == -1;
      assert forall i | 0 <= i <= |s| :: !SubstringAt(s, f, i);
    }
  }

}
