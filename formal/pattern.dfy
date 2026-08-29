// formal/pattern.dfy
//
// Formal model of pattern.nim matchPattern / matchAlt. Models termination,
// the disjunction-of-alternatives property (the `!` fix from #406), and the
// whole-string-consumption invariant.
//
// Verify with:  dafny verify formal/pattern.dfy

module Pattern {

  // A pattern atom: a character class of exact `count`, or of `min`-or-more.
  // (Literal-string atoms are analogous and omitted for brevity.)
  datatype Atom =
    | Cls(count: nat, code: char)
    | ClsMore(min: nat, code: char)

  // Character-class membership (A/N/U/L/P/C/H/E, ...). Abstracted.
  function MatchesCode(c: char, code: char): bool

  // Minimum length an atom must consume.
  function MinLen(a: Atom): nat {
    if a.Cls? then a.count else a.min
  }

  // Total minimum length of an atom sequence.
  function TotalMin(atoms: seq<Atom>): nat {
    if atoms == [] then 0 else MinLen(atoms[0]) + TotalMin(atoms[1..])
  }

  // Greedy left-to-right match of one alternative; succeeds iff the whole
  // string is consumed. Terminates because each step consumes >= MinLen > 0
  // characters or drops an atom (decreases |atoms| + |s|).
  function MatchAlt(s: seq<char>, atoms: seq<Atom>): bool
    decreases |atoms| + |s|
  {
    if atoms == [] then s == []
    else if MinLen(atoms[0]) > |s| then false
    else if atoms[0].Cls? then
      (forall i | 0 <= i < atoms[0].count :: MatchesCode(s[i], atoms[0].code))
        && MatchAlt(s[atoms[0].count..], atoms[1..])
    else
      exists k | atoms[0].min <= k <= |s| ::
        (forall i | 0 <= i < k :: MatchesCode(s[i], atoms[0].code))
        && (k == |s| || !MatchesCode(s[k], atoms[0].code))
        && MatchAlt(s[k..], atoms[1..])
  }

  // matchPattern: the disjunction of alternatives (the `!` alternation).
  function Match(s: seq<char>, alts: seq<seq<Atom>>): bool {
    exists i | 0 <= i < |alts| :: MatchAlt(s, alts[i])
  }

  // Whole-string consumption: a successful match never reads past the end —
  // the atom sequence's minimum length is a lower bound on the input length.
  lemma MatchAltConsumesAll(s: seq<char>, atoms: seq<Atom>)
    ensures MatchAlt(s, atoms) ==> TotalMin(atoms) <= |s|
    decreases |atoms|
  {
    reveal MatchAlt;
    if atoms == [] {
    } else {
      var a := atoms[0];
      if MatchAlt(s, atoms) {
        assert MinLen(a) <= |s|;
        if a.Cls? {
          assert MatchAlt(s[a.count..], atoms[1..]);
          MatchAltConsumesAll(s[a.count..], atoms[1..]);
          assert TotalMin(atoms) == a.count + TotalMin(atoms[1..]);
        } else {
          var k :| a.min <= k <= |s|
            && (forall i | 0 <= i < k :: MatchesCode(s[i], a.code))
            && (k == |s| || !MatchesCode(s[k], a.code))
            && MatchAlt(s[k..], atoms[1..]);
          MatchAltConsumesAll(s[k..], atoms[1..]);
          assert TotalMin(atoms) == a.min + TotalMin(atoms[1..]);
          assert a.min <= k;
        }
      }
    }
  }

  // Disjunction direction: any matching alternative makes the whole pattern match.
  lemma MatchFromAlt(s: seq<char>, alts: seq<seq<Atom>>, i: nat)
    requires 0 <= i < |alts| && MatchAlt(s, alts[i])
    ensures Match(s, alts)
  {
  }

}
