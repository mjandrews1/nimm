// formal/numeric_prefix.dfy
//
// Formal model of `numPrefix`/`truthy` (value.nim): M's truth-value test
// (ANSI/ISO 2.2.4) — a string is truthy iff its longest leading numeric
// prefix has a non-zero value.
//
// The prefix grammar is `[+-]? ( digit+ ('.' digit*)? | '.' digit+ )`; the
// optional `E` exponent is omitted because it can never change the truth value
// (0·10^k == 0 and a non-zero mantissa stays non-zero). Only UPPERCASE 'E'
// would introduce an exponent, and since it is not part of the mantissa it is
// simply trailing (so "2e3" and "2E3" are both truthy, "0E5" is false).
//
// Verify with:  dafny verify formal/numeric_prefix.dfy

module NumericPrefix {

  // End of the leading digit run starting at i (first non-digit, or |s|).
  function DigitRunEnd(s: seq<char>, i: nat): nat
    requires i <= |s|
    decreases |s| - i
  {
    if i < |s| && '0' <= s[i] <= '9' then DigitRunEnd(s, i + 1) else i
  }

  // Longest leading mantissa (sign + digits + optional fraction), 0 if none.
  function MantissaEnd(s: seq<char>): nat {
    var i := if |s| > 0 && (s[0] == '+' || s[0] == '-') then 1 else 0;
    var intEnd := DigitRunEnd(s, i);
    if intEnd > i then
      (if intEnd < |s| && s[intEnd] == '.' then
         (var fracEnd := DigitRunEnd(s, intEnd + 1);
          if fracEnd > intEnd + 1 then fracEnd else intEnd)
       else intEnd)
    else
      (if intEnd < |s| && s[intEnd] == '.' then
         (var fracEnd := DigitRunEnd(s, intEnd + 1);
          if fracEnd > intEnd + 1 then fracEnd else 0)
       else 0)
  }

  // A digit run never ends before its start index.
  lemma DigitRunEndAtLeast(s: seq<char>, i: nat)
    requires i <= |s|
    ensures DigitRunEnd(s, i) >= i
    decreases |s| - i
  {
    reveal DigitRunEnd;
    if i < |s| && '0' <= s[i] <= '9' {
      DigitRunEndAtLeast(s, i + 1);
      assert DigitRunEnd(s, i) == DigitRunEnd(s, i + 1);
    }
  }

  // Truth value: a non-empty mantissa containing at least one non-zero digit.
  function Truthy(s: seq<char>): bool {
    var m := MantissaEnd(s);
    m > 0 && (exists i | 0 <= i < m && i < |s| :: '1' <= s[i] <= '9')
  }

  // --- Truth table (mirrors value.nim truthy / numPrefix docstring) ---
  lemma EmptyIsFalse() ensures !Truthy("") { }
  lemma ZeroIsFalse() ensures !Truthy("0") { }
  lemma ZeroPointZeroIsFalse() ensures !Truthy("0.00") { }
  lemma AlphaIsFalse() ensures !Truthy("abc") { }
  lemma OneIsTrue() ensures Truthy("1") { }
  lemma LeadingZeroIsTrue() ensures Truthy("042") { }
  lemma FractionIsTrue() ensures Truthy(".5x") {
    reveal MantissaEnd;
    reveal DigitRunEnd;
    assert MantissaEnd(".5x") == 2;
    assert '1' <= ".5x"[1] <= '9';
  }
  lemma PrefixIsTrue() ensures Truthy("3apples") { }
  lemma LowerEIsTrue() ensures Truthy("2e3") { }

  // Structural: a leading non-zero digit makes the string truthy.
  lemma LeadingNonZeroDigitIsTrue(s: seq<char>)
    requires |s| > 0 && '1' <= s[0] <= '9'
    ensures Truthy(s)
  {
    reveal MantissaEnd;
    DigitRunEndAtLeast(s, 1);
    assert '0' <= s[0] <= '9';
    assert DigitRunEnd(s, 0) == DigitRunEnd(s, 1);
    assert DigitRunEnd(s, 0) >= 1;
    assert MantissaEnd(s) >= 1;
  }

  // Structural: a string with no digits anywhere is falsy.
  lemma NoDigitsIsFalse(s: seq<char>)
    requires forall i | 0 <= i < |s| :: !('0' <= s[i] <= '9')
    ensures !Truthy(s)
  {
  }

}
