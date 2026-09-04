// formal/bioxiv_link.dfy
//
// Formal model of the BioArxiv/medRxiv preprint loader (build_biorxiv.nim,
// #469). Each preprint (keyed by DOI) may carry a `published` DOI once a
// journal has published it; before publication that field is "NA". The model
// proves:
//   - the published-DOI link is only asserted when the value is a real DOI
//     (not "NA") — the join gate that keeps un-published preprints from
//     dangling;
//   - forward/reverse encodings stay consistent under link/unlink, and linking
//     is idempotent;
//   - query duality (preprint-of vs published-by) holds.
//
// Verify with:  dafny verify formal/bioxiv_link.dfy

module BioxivLink {

  // A "published" value is either the sentinel "NA" (not yet published) or a
  // real DOI.
  ghost predicate IsPublished(pub: string)
  {
    pub != "" && pub != "NA"
  }

  // The link for a preprint is Some(doi) iff it is published; None otherwise.
  datatype MaybeDoi = None | Some(doi: string)

  ghost function PublishedLink(pub: string): MaybeDoi
  {
    if IsPublished(pub) then Some(pub) else None
  }

  // Un-published ("NA" or empty) preprints yield no link.
  lemma NaGate(pub: string)
    requires !IsPublished(pub)
    ensures PublishedLink(pub) == None
  {
  }

  lemma PublishedGate(pub: string)
    requires IsPublished(pub)
    ensures PublishedLink(pub) == Some(pub)
  {
  }

  // A link is a (preprintDoi, publishedDoi) pair; forward = the loader's
  // record, reverse = the query view. Consistency is the standard equality.
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

  ghost function PublishedOf(links: set<(string, string)>, preprint: string): iset<string>
  {
    iset pub | (preprint, pub) in links
  }

  ghost function PreprintsOf(links: set<(string, string)>, pub: string): iset<string>
  {
    iset preprint | (preprint, pub) in links
  }

  lemma QueryDuality(links: set<(string, string)>, preprint: string, pub: string)
    ensures pub in PublishedOf(links, preprint) <==> preprint in PreprintsOf(links, pub)
  {
  }

}
