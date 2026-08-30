// formal/functions_more.dfy
//
// Formal model of more pure evaluator intrinsics (evaluator.nim): $GET, $CASE,
// $SELECT, $QLENGTH, $REVERSE. Complements string_functions.dfy.
//
// Verify with:  dafny verify formal/numeric_prefix.dfy formal/functions_more.dfy

module FunctionsMore {

  import opened NumericPrefix   // for Truthy

  // $GET(s, d): s if non-empty, else the default d.
  function Get(s: seq<char>, d: seq<char>): seq<char>
  {
    if s == [] then d else s
  }

  // $CASE(expr, cases, default): the result paired with the first value equal
  // to expr; otherwise the default.
  function Case(expr: seq<char>, cases: seq<(seq<char>, seq<char>)>, default: seq<char>): seq<char>
    decreases |cases|
  {
    if |cases| == 0 then default
    else if expr == cases[0].0 then cases[0].1
    else Case(expr, cases[1..], default)
  }

  // $SELECT(pairs, default): the value paired with the first truthy condition;
  // otherwise the default.
  function Select(pairs: seq<(seq<char>, seq<char>)>, default: seq<char>): seq<char>
    decreases |pairs|
  {
    if |pairs| == 0 then default
    else if Truthy(pairs[0].0) then pairs[0].1
    else Select(pairs[1..], default)
  }

  // $QLENGTH: number of subscript separators (commas) in a subscript string.
  function CountCommas(s: seq<char>): int
    decreases |s|
  {
    if |s| == 0 then 0
    else (if s[0] == ',' then 1 else 0) + CountCommas(s[1..])
  }

  // $REVERSE: reverse the character sequence.
  function Reverse(s: seq<char>): seq<char>
    decreases |s|
  {
    if |s| == 0 then []
    else Reverse(s[1..]) + [s[0]]
  }

  // --- concrete cases ---
  lemma GetValue() ensures Get("x", "d") == "x" { }
  lemma GetDefault() ensures Get("", "d") == "d" { }

  lemma CaseFirst() ensures Case("a", [("a", "1"), ("b", "2")], "z") == "1" { }
  lemma CaseSecond() ensures Case("b", [("a", "1"), ("b", "2")], "z") == "2" { }
  lemma CaseDefault() ensures Case("c", [("a", "1"), ("b", "2")], "z") == "z" { }

  lemma SelectFirstTruthy() ensures Select([("", "a"), ("1", "b")], "d") == "b" { }
  lemma SelectNoTruthy() ensures Select([("", "a"), ("0", "c")], "d") == "d" { }

  lemma CountCommasZero() ensures CountCommas("") == 0 { }
  lemma CountCommasTwo() ensures CountCommas("a,b,c") == 2 { }

  lemma ReverseAbc() ensures Reverse("abc") == "cba" { }
  lemma ReverseEmpty() ensures Reverse("") == "" { }

  // --- key properties ---

  // Case returns the first matching result (or default if none match).
  lemma CaseFirstMatch(expr: seq<char>, cases: seq<(seq<char>, seq<char>)>, default: seq<char>, r: seq<char>)
    requires 0 < |cases| && cases[0].0 == expr
    ensures Case(expr, cases, default) == cases[0].1
  {
  }

  // If Case returns a non-default result, it is one of the case results.
  lemma CaseReturnsAResult(expr: seq<char>, cases: seq<(seq<char>, seq<char>)>, default: seq<char>)
    ensures Case(expr, cases, default) == default ||
            (exists i | 0 <= i < |cases| :: cases[i].1 == Case(expr, cases, default))
  {
  }

  // Reverse distributes over concatenation (in reversed order).
  lemma ReverseConcat(a: seq<char>, b: seq<char>)
    ensures Reverse(a + b) == Reverse(b) + Reverse(a)
    decreases |a|
  {
    if |a| == 0 {
      assert a == [];
      assert [] + b == b;
      assert Reverse([]) == [];
      assert Reverse(b) + [] == Reverse(b);
    } else {
      assert (a + b)[0] == a[0];
      assert (a + b)[1..] == a[1..] + b;
      ReverseConcat(a[1..], b);
    }
  }

  // Reverse is an involution.
  lemma ReverseInvolution(s: seq<char>)
    ensures Reverse(Reverse(s)) == s
    decreases |s|
  {
    if |s| > 0 {
      ReverseInvolution(s[1..]);
      ReverseConcat(Reverse(s[1..]), [s[0]]);
      assert Reverse(s) == Reverse(s[1..]) + [s[0]];
      assert Reverse([s[0]]) == [s[0]];
    }
  }

}
