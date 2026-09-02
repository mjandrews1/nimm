// formal/supp_concepts.dfy
//
// Formal model of the MeSH Supplementary Concept Record (SCR) loader
// (xmlload.nim "scr" format, #462 Phase 1): each SupplementalRecord maps to
// MeSH descriptors via HeadingMappedTo, written as a MeSH-outbound ^LINK
// ("MESH", dui, "SUPP", scrui) plus the reverse per-record ^SUPP(scrui,"mesh",
// dui). Models:
//   - the leading-'*' (major-descriptor) marker is normalized away before
//     linking (bare descriptor UI);
//   - the forward (^LINK) and reverse (per-record) encodings stay consistent
//     under link/unlink, and linking is idempotent;
//   - records-of(dui) and descriptors-of(scrui) are inverse query views.
//
// Verify with:  dafny verify formal/supp_concepts.dfy

module SuppConcepts {

  // Normalize a DescriptorUI to its bare form by stripping leading '*'
  // major-descriptor markers. (NLM DescriptorUIs carry at most one '*'; the
  // Nim loader strips exactly one, which agrees with this normalization.)
  function StripStar(s: string): string
    decreases |s|
  {
    if s == "" then ""
    else if s[0] == '*' then StripStar(s[1..])
    else s
  }

  lemma StripStarIdempotent(s: string)
    ensures StripStar(StripStar(s)) == StripStar(s)
    decreases |s|
  {
    if s != "" && s[0] == '*' {
      StripStarIdempotent(s[1..]);
    }
  }

  // The normalized DUI is bare: it never begins with '*'.
  lemma BareDui(s: string)
    ensures StripStar(s) == "" || StripStar(s)[0] != '*'
    decreases |s|
  {
    if s != "" && s[0] == '*' {
      BareDui(s[1..]);
    }
  }

  // A SCR record's mapped-descriptor set is the normalized DescriptorUI list.
  function Mapped(raw: seq<string>): set<string>
    decreases |raw|
  {
    if raw == [] then {}
    else {StripStar(raw[0])} + Mapped(raw[1..])
  }

  // Soundness: every mapped descriptor UI is bare (no '*' survives), so ^LINK
  // is keyed on the canonical descriptor UI.
  lemma MappedSound(raw: seq<string>, u: string)
    requires u in Mapped(raw)
    ensures u == "" || u[0] != '*'
    decreases |raw|
  {
    if raw == [] {
    } else if u == StripStar(raw[0]) {
      BareDui(raw[0]);
    } else {
      MappedSound(raw[1..], u);
    }
  }

  // A link is a (dui, scrui) pair: forward = ^LINK("MESH",dui,"SUPP",scrui),
  // reverse = ^SUPP(scrui,"mesh",dui). Consistency means the two encodings
  // hold exactly the same pairs.
  ghost predicate Consistent(fwd: set<(string, string)>, rev: set<(string, string)>)
  {
    forall p :: p in fwd <==> p in rev
  }

  lemma LinkBothPreserves(fwd: set<(string, string)>, rev: set<(string, string)>,
                          p: (string, string))
    requires Consistent(fwd, rev)
    ensures Consistent(fwd + {p}, rev + {p})
  {
  }

  lemma UnlinkBothPreserves(fwd: set<(string, string)>, rev: set<(string, string)>,
                            p: (string, string))
    requires Consistent(fwd, rev)
    ensures Consistent(fwd - {p}, rev - {p})
  {
  }

  // Linking an already-present pair is a no-op (idempotent dedup).
  lemma LinkBothIdempotent(fwd: set<(string, string)>, rev: set<(string, string)>,
                           p: (string, string))
    requires Consistent(fwd, rev)
    ensures (fwd + {p}) + {p} == fwd + {p}
    ensures (rev + {p}) + {p} == rev + {p}
  {
  }

  // Query duality: the set of SCRs mapped to a descriptor and the set of
  // descriptors mapped to an SCR are inverse views of the same relation.
  ghost function RecordsOf(links: set<(string, string)>, dui: string): iset<string>
  {
    iset scrui | (dui, scrui) in links
  }

  ghost function DescriptorsOf(links: set<(string, string)>, scrui: string): iset<string>
  {
    iset dui | (dui, scrui) in links
  }

  lemma QueryDuality(links: set<(string, string)>, dui: string, scrui: string)
    ensures scrui in RecordsOf(links, dui) <==> dui in DescriptorsOf(links, scrui)
  {
  }

}
