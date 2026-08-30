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

  // --- $PIECE (delimiter split, evaluator.nim:590) ---
  // First match position of d in s[..] starting at i; |s| if none.
  function FirstMatch(s: seq<char>, d: seq<char>, i: nat): nat
    requires i <= |s|
    ensures FirstMatch(s, d, i) <= |s|
    ensures FirstMatch(s, d, i) == |s| || FirstMatch(s, d, i) + |d| <= |s|
    decreases |s| - i
  {
    if i + |d| <= |s| && s[i .. i + |d|] == d then i
    else if i < |s| then FirstMatch(s, d, i + 1)
    else |s|
  }

  // The nth piece (1-indexed) of s split by delimiter d.
  function Piece(s: seq<char>, d: seq<char>, n: nat): seq<char>
    decreases n + |s|
  {
    if d == [] then s
    else if n == 0 then []
    else
      var p := FirstMatch(s, d, 0);
      if p == |s| then
        if n == 1 then s else []
      else if n == 1 then
        s[..p]
      else
        Piece(s[p + |d| ..], d, n - 1)
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

  // FirstMatch facts for the caret delimiter (shared by the Piece cases).
  lemma FirstMatchCaretAbc() ensures FirstMatch("a^b^c", "^", 0) == 1 {
    reveal FirstMatch;
    assert "a^b^c"[0..1] == "a";
    assert "a^b^c"[1..2] == "^";
  }
  lemma FirstMatchCaretBc() ensures FirstMatch("b^c", "^", 0) == 1 {
    reveal FirstMatch;
    assert "b^c"[0..1] == "b";
    assert "b^c"[1..2] == "^";
  }
  lemma FirstMatchCaretC() ensures FirstMatch("c", "^", 0) == 1 {
    reveal FirstMatch;
    assert "c"[0..1] == "c";
  }
  lemma FirstMatchCaretPlain() ensures FirstMatch("abc", "^", 0) == 3 {
    reveal FirstMatch;
    assert "abc"[0..1] == "a";
    assert "abc"[1..2] == "b";
    assert "abc"[2..3] == "c";
  }

  lemma PieceFirst() ensures Piece("a^b^c", "^", 1) == "a" {
    reveal Piece;
    FirstMatchCaretAbc();
  }
  lemma PieceSecond() ensures Piece("a^b^c", "^", 2) == "b" {
    reveal Piece;
    FirstMatchCaretAbc();
    FirstMatchCaretBc();
  }
  lemma PieceThird() ensures Piece("a^b^c", "^", 3) == "c" {
    reveal Piece;
    FirstMatchCaretAbc();
    FirstMatchCaretBc();
    FirstMatchCaretC();
  }
  lemma PieceBeyond() ensures Piece("a^b^c", "^", 4) == "" {
    reveal Piece;
    FirstMatchCaretAbc();
    FirstMatchCaretBc();
    FirstMatchCaretC();
  }
  lemma PieceNoDelim() ensures Piece("abc", "^", 1) == "abc" {
    reveal Piece;
    FirstMatchCaretPlain();
  }

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

  // ================= $PIECE multi-piece (split + join) =================
  // The multi-piece path (start != stop) splits on the full delimiter, then
  // joins pieces start..stop with the delimiter.

  // Split s at each (non-overlapping) occurrence of delimiter d.
  function Split(s: seq<char>, d: seq<char>): seq<seq<char>>
    decreases |s|
  {
    if d == [] then [s]
    else
      var p := FirstMatch(s, d, 0);
      if p == |s| then [s]
      else [s[..p]] + Split(s[p + |d| ..], d)
  }

  // Number of (non-overlapping) occurrences of d in s.
  function CountDelim(s: seq<char>, d: seq<char>): nat
    requires d != []
    decreases |s|
  {
    var p := FirstMatch(s, d, 0);
    if p == |s| then 0
    else 1 + CountDelim(s[p + |d| ..], d)
  }

  // Join pieces with delimiter d between them.
  function Join(pieces: seq<seq<char>>, d: seq<char>): seq<char>
    decreases |pieces|
  {
    if |pieces| == 0 then []
    else if |pieces| == 1 then pieces[0]
    else pieces[0] + d + Join(pieces[1..], d)
  }

  // FirstMatch returns a position where d actually matches (or |s|).
  lemma FirstMatchFound(s: seq<char>, d: seq<char>, i: nat)
    requires d != [] && i <= |s|
    ensures var p := FirstMatch(s, d, i); p < |s| ==> s[p .. p + |d|] == d
    decreases |s| - i
  {
    reveal FirstMatch;
    if i + |d| <= |s| && s[i .. i + |d|] == d {
    } else if i < |s| {
      FirstMatchFound(s, d, i + 1);
    }
  }

  // Split always yields at least one piece.
  lemma SplitNonEmpty(s: seq<char>, d: seq<char>)
    ensures |Split(s, d)| >= 1
    decreases |s|
  {
    reveal Split;
    if d == [] {
    } else {
      var p := FirstMatch(s, d, 0);
      if p != |s| {
        SplitNonEmpty(s[p + |d| ..], d);
      }
    }
  }

  // The number of pieces is one more than the number of delimiters.
  lemma PieceCount(s: seq<char>, d: seq<char>)
    requires d != []
    ensures |Split(s, d)| == CountDelim(s, d) + 1
    decreases |s|
  {
    reveal Split;
    reveal CountDelim;
    var p := FirstMatch(s, d, 0);
    if p != |s| {
      PieceCount(s[p + |d| ..], d);
    }
  }

  // Splitting on d and joining with d recovers the original string: the
  // multi-piece $PIECE over the full range (start=1, stop=count) is the whole.
  lemma SplitJoinRoundTrip(s: seq<char>, d: seq<char>)
    requires d != []
    ensures Join(Split(s, d), d) == s
    decreases |s|
  {
    reveal Split;
    reveal Join;
    var p := FirstMatch(s, d, 0);
    if p == |s| {
    } else {
      SplitJoinRoundTrip(s[p + |d| ..], d);
      SplitNonEmpty(s[p + |d| ..], d);
      FirstMatchFound(s, d, 0);
      assert s[p .. p + |d|] == d;
      assert Split(s, d) == [s[..p]] + Split(s[p + |d| ..], d);
      assert Join(Split(s, d), d) == s[..p] + d + Join(Split(s[p + |d| ..], d), d);
      assert s[..p] + d + s[p + |d| ..] == s;
    }
  }

  // ================= $JUSTIFY (width align) =================
  // Right-justify s to width by left-padding with spaces; a non-positive width
  // (or width <= |s|) leaves s unchanged.

  function Spaces(n: nat): seq<char>
    decreases n
  {
    if n == 0 then [] else [' '] + Spaces(n - 1)
  }

  lemma SpacesLength(n: nat)
    ensures |Spaces(n)| == n
    decreases n
  {
    if n == 0 {
    } else {
      SpacesLength(n - 1);
    }
  }

  function Justify(s: seq<char>, width: int): seq<char>
  {
    if width <= |s| then s else Spaces(width - |s|) + s
  }

  lemma JustifyLength(s: seq<char>, width: int)
    ensures |Justify(s, width)| == (if width > |s| then width else |s|)
  {
    if width > |s| {
      SpacesLength(width - |s|);
    }
  }

  lemma JustifyNegative(s: seq<char>, width: int)
    requires width <= |s|
    ensures Justify(s, width) == s
  {
  }

  // ================= $FNUMBER (sign decoration) =================
  // '+' in the format forces a leading '+' on non-negative numbers; 'P'
  // parenthesizes negative numbers.

  function FNumberSign(s: string, hasPlus: bool, hasParen: bool, negative: bool): string
  {
    if hasParen && negative then "(" + s + ")"
    else if hasPlus && !negative then "+" + s
    else s
  }

  lemma FNumberPlus(s: string)
    ensures FNumberSign(s, true, false, false) == "+" + s
  {
  }

  lemma FNumberParen(s: string)
    ensures FNumberSign(s, false, true, true) == "(" + s + ")"
  {
  }

}
