// formal/value_format.dfy
//
// Formal model of the §5.2 canonical-number rules in formatNumber (value.nim):
// a proper fraction drops its redundant integer zero ("0.5" → ".5"), and the
// fractional part carries no trailing zeros ("1.50" → "1.5") or trailing point
// ("5.0" → "5"). Each rule is a normal form, so formatNumber always emits a
// string parseNum accepts.
//
// Verify with:  dafny verify formal/value_format.dfy

module ValueFormat {

  // Drop the redundant integer zero on a proper fraction. Integers and
  // other strings are left unchanged.
  function DropLeadingZero(s: seq<char>): seq<char>
  {
    if |s| >= 2 && s[0] == '0' && s[1] == '.' then s[1..]
    else if |s| >= 3 && s[0] == '-' && s[1] == '0' && s[2] == '.' then [s[0]] + s[2..]
    else s
  }

  // Idempotent: applying the rule twice is the same as once.
  lemma DropLeadingZeroIdempotent(s: seq<char>)
    ensures DropLeadingZero(DropLeadingZero(s)) == DropLeadingZero(s)
  {
  }

  // Does s contain a decimal point?
  predicate HasPoint(s: seq<char>)
  {
    exists i | 0 <= i < |s| :: s[i] == '.'
  }

  // Strip trailing zeros and then a trailing point (matches formatNumber's
  // "while buf[^1]=='0' … if buf[^1]=='.'" for the non-exponent path).
  function StripZeros(s: seq<char>): seq<char>
    decreases |s|
  {
    if s != [] && s[|s| - 1] == '0' then StripZeros(s[..|s| - 1])
    else if s != [] && s[|s| - 1] == '.' then s[..|s| - 1]
    else s
  }

  // Strip trailing zeros only when there is a fractional part.
  function StripTrailingZeros(s: seq<char>): seq<char>
  {
    if HasPoint(s) then StripZeros(s) else s
  }

  // Full canonical form (§5.2): strip trailing zeros, then drop the leading
  // integer zero on a proper fraction.
  function Canonicalize(s: seq<char>): seq<char>
  {
    DropLeadingZero(StripTrailingZeros(s))
  }

  // A string already free of trailing zeros/point is a fixed point.
  lemma StripZerosFix(s: seq<char>)
    requires s == [] || (s[|s| - 1] != '0' && s[|s| - 1] != '.')
    ensures StripZeros(s) == s
  {
  }

  // Concrete cases.
  lemma CanonicalizeHalf() ensures DropLeadingZero("0.5") == ".5" { }
  lemma CanonicalizeNegQuarter() ensures DropLeadingZero("-0.25") == "-.25" { }
  lemma KeepInteger() ensures DropLeadingZero("5") == "5" { }
  lemma KeepWhole() ensures DropLeadingZero("10") == "10" { }

  lemma StripHalfZero() ensures StripTrailingZeros("1.50") == "1.5" {
    reveal StripTrailingZeros;
    reveal StripZeros;
    assert "1.50"[1] == '.';
    assert HasPoint("1.50");
    assert StripZeros("1.50") == StripZeros("1.5");
    assert StripZeros("1.5") == "1.5";
  }
  lemma StripPointZero() ensures StripTrailingZeros("5.0") == "5" {
    reveal StripTrailingZeros;
    reveal StripZeros;
    assert "5.0"[1] == '.';
    assert HasPoint("5.0");
    assert StripZeros("5.0") == StripZeros("5.");
    assert StripZeros("5.") == "5";
  }
  lemma KeepTrailingIntegerZero() ensures StripTrailingZeros("50") == "50" {
    reveal StripTrailingZeros;
    reveal HasPoint;
  }
  lemma CanonicalizeHalfZero() ensures Canonicalize("1.50") == "1.5" {
    reveal Canonicalize;
    reveal StripTrailingZeros;
    reveal StripZeros;
    assert "1.50"[1] == '.';
    assert StripTrailingZeros("1.50") == "1.5";
  }
  lemma CanonicalizeFive() ensures Canonicalize("5.0") == "5" {
    reveal Canonicalize;
    reveal StripTrailingZeros;
    reveal StripZeros;
    assert "5.0"[1] == '.';
    assert StripTrailingZeros("5.0") == "5";
  }

}
