// formal/reporter_link.dfy
//
// Formal model of the PUBMED→REPORTER funding link (build_reporter_link.nim,
// #462 RePORTER→PubMed): each ExPORTER publication link-table row maps a PMID
// to the NIH grant (PROJECT_NUMBER) that funded it, written as
//   ^LINK("PUBMED", pmid, "REPORTER", project) = "funding"   (forward)
//   ^REPORTER(project, "pubmed", pmid) = "1"                 (reverse)
// The relation is many-to-many: one article cites many grants, one grant
// funds many articles. Models the two encodings staying consistent under
// link/unlink, idempotent dedup (a row may appear in several fiscal-year
// link tables), and the inverse query views.
//
// Verify with:  dafny verify formal/reporter_link.dfy

module ReporterLink {

  // A link is a (pmid, project) pair. Forward = ^LINK, reverse = ^REPORTER.
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

  // Re-linking an existing pair (e.g. the same PMID→project row in two fiscal
  // years) is a no-op.
  lemma LinkBothIdempotent(fwd: set<(string, string)>, rev: set<(string, string)>,
                           p: (string, string))
    requires Consistent(fwd, rev)
    ensures (fwd + {p}) + {p} == fwd + {p}
    ensures (rev + {p}) + {p} == rev + {p}
  {
  }

  // Query duality: the projects funding a PMID and the PMIDs funded by a
  // project are inverse views of the same relation.
  ghost function ProjectsOf(links: set<(string, string)>, pmid: string): iset<string>
  {
    iset project | (pmid, project) in links
  }

  ghost function PmidsOf(links: set<(string, string)>, project: string): iset<string>
  {
    iset pmid | (pmid, project) in links
  }

  lemma QueryDuality(links: set<(string, string)>, pmid: string, project: string)
    ensures project in ProjectsOf(links, pmid) <==> pmid in PmidsOf(links, project)
  {
  }

}
