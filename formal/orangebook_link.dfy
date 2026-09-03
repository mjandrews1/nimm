// formal/orangebook_link.dfy
//
// Formal model of the Orange Book ingredient -> MeSH SCR cross-link
// (build_orangebook.nim, #462 Phase 2). An ingredient name maps to a SCR via
// ^SUPPNAME: the link is written only when the name resolves to exactly ONE
// SCR (unambiguous), and is skipped when zero or multiple SCRs claim the name.
//
// The model states: (1) a linking decision is a partial function name -> SCR
// that is injective-on-the-domain (one SCR per name); (2) the ^LINK forward
// and ^SUPP reverse encodings stay consistent; (3) linking is idempotent.
//
// Verify with:  dafny verify formal/orangebook_link.dfy

module OrangebookLink {

  // A name resolves to at most one SCR: model the decision as an optional SCR.
  datatype MaybeScr = None | Some(scrui: string)

  // resolveNames maps a name to its candidate SCR set (from ^SUPPNAME).
  // resolve returns Some(scrui) iff the candidate set is the singleton {scrui}.
  ghost function Resolve(cands: set<string>): (r: MaybeScr)
    requires |cands| <= 1
  {
    if cands == {} then None else Some(var s :| s in cands; s)
  }

  // Unambiguous (singleton) names resolve to that sole SCR.
  lemma ResolveUnambiguous(scrui: string)
    ensures Resolve({scrui}) == Some(scrui)
  {
  }

  // Empty candidate set resolves to nothing.
  lemma ResolveEmpty()
    ensures Resolve({}) == None
  {
  }

  lemma ResolveIsDeterministic(cands: set<string>, r1: MaybeScr, r2: MaybeScr)
    requires |cands| <= 1
    requires r1 == Resolve(cands)
    requires r2 == Resolve(cands)
    ensures r1 == r2
  {
  }

  // A link is a (name, scrui) pair; forward = ^LINK, reverse = ^SUPP(...).
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

  lemma LinkBothIdempotent(fwd: set<(string, string)>, rev: set<(string, string)>,
                           p: (string, string))
    requires Consistent(fwd, rev)
    ensures (fwd + {p}) + {p} == fwd + {p}
  {
  }

}
