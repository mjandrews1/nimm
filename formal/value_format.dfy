// formal/value_format.dfy
//
// Formal model of the §5.2 canonical-number rule in formatNumber (value.nim):
// a proper fraction drops its redundant integer zero ("0.5" → ".5",
// "-0.25" → "-.25"). This is the rule isNumeric/decodeKey must also accept,
// and it is a normal form (idempotent).
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

  // Concrete cases.
  lemma CanonicalizeHalf() ensures DropLeadingZero("0.5") == ".5" { }
  lemma CanonicalizeNegQuarter() ensures DropLeadingZero("-0.25") == "-.25" { }
  lemma KeepInteger() ensures DropLeadingZero("5") == "5" { }
  lemma KeepWhole() ensures DropLeadingZero("10") == "10" { }

}
