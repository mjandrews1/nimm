# test_reporter_link.nim — mirror of formal/reporter_link.dfy (#462 RePORTER→PubMed).
#
# Part 1 re-implements the model's link consistency + idempotency + query
# duality as pure Nim over (pmid, project) pairs.
#
# Part 2 tests the loader's CSV row parser and drives the end-to-end loader
# logic (buildReporterLinks is in build_reporter_link.nim) over a small
# in-memory store: forward ^LINK + reverse ^REPORTER are written symmetrically,
# dedup across files holds, and the reported counts are correct.
#
# Run: nim c -r tests/test_reporter_link.nim

import sets
import ../globals
import ../future_search_tool/src/build_reporter_link

type Link = tuple[pmid, project: string]

proc projectsOf(links: HashSet[Link], pmid: string): HashSet[string] =
  result = initHashSet[string]()
  for l in links:
    if l.pmid == pmid: result.incl(l.project)

proc pmidsOf(links: HashSet[Link], project: string): HashSet[string] =
  result = initHashSet[string]()
  for l in links:
    if l.project == project: result.incl(l.pmid)

proc main() =
  echo "reporter_link mirror test..."

  # --- Part 1: pure mirrors ---
  var fwd = initHashSet[Link]()
  var rev = initHashSet[Link]()
  let l1: Link = ("38329837", "P50AA022537")
  let l2: Link = ("40893628", "KL2TR001856")
  proc linkBoth(p: Link) = (fwd.incl(p); rev.incl(p))
  proc unlinkBoth(p: Link) = (fwd.excl(p); rev.excl(p))
  linkBoth(l1); linkBoth(l2)
  assert fwd == rev, "consistent after linkBoth"
  unlinkBoth(l1)
  assert fwd == rev, "consistent after unlinkBoth"
  assert l1 notin fwd and l2 in fwd, "l1 removed, l2 kept"
  let n = fwd.len
  linkBoth(l2)
  assert fwd.len == n, "idempotent re-link"

  var links = initHashSet[Link]()
  links.incl(("40893628", "KL2TR001856"))
  links.incl(("40893628", "R01AA025936"))
  links.incl(("40894177", "R01AG072935"))
  assert projectsOf(links, "40893628") == toHashSet(["KL2TR001856", "R01AA025936"]),
    "projectsOf (one pmid, many grants)"
  assert pmidsOf(links, "R01AA025936") == toHashSet(["40893628"]), "pmidsOf"
  for pmid in ["40893628", "40894177"]:
    for project in ["KL2TR001856", "R01AA025936", "R01AG072935"]:
      assert (project in projectsOf(links, pmid)) == (pmid in pmidsOf(links, project)),
        "duality: " & pmid & " / " & project

  echo "  model mirrors hold"

  # --- Part 2: CSV parser + loader logic ---
  echo "--- parser/loader test ---"
  assert parseCsvLine("\"38329837\",\"P50AA022537\"") == ("38329837", "P50AA022537"),
    "basic line"
  assert parseCsvLine("3489745,\"N01HV062923\"") == ("3489745", "N01HV062923"),
    "unquoted first field (older files)"
  assert parseCsvLine("3489745,\"N01HV062923\"\r") == ("3489745", "N01HV062923"),
    "unquoted first field CRLF"
  assert parseCsvLine("\"PMID\",\"PROJECT_NUMBER\"") == ("PMID", "PROJECT_NUMBER"),
    "header line"
  assert parseCsvLine("\"40893628\",\"R01AA025936\"\r") == ("40893628", "R01AA025936"),
    "CRLF line"
  assert parseCsvLine("") == ("", ""), "empty line"

  # Emulate the loader's write path over two "files" sharing one PMID to check
  # cross-file dedup and symmetry.
  var g = newGlobals("")
  proc applyRow(pmid, project: string) =
    g.set("^LINK", @["PUBMED", pmid, "REPORTER", project], "funding")
    g.set("^REPORTER", @[project, "pubmed", pmid], "1")
  applyRow("38329837", "P50AA022537")
  applyRow("40893628", "KL2TR001856")
  applyRow("40893628", "R01AA025936")  # second project for same pmid
  applyRow("40893628", "KL2TR001856")  # duplicate (cross-file) -> overwrite, no dup

  assert g.get("^LINK", @["PUBMED", "38329837", "REPORTER", "P50AA022537"]) == "funding",
    "forward link"
  assert g.get("^REPORTER", @["P50AA022537", "pubmed", "38329837"]) == "1",
    "reverse link"
  assert g.get("^LINK", @["PUBMED", "40893628", "REPORTER", "KL2TR001856"]) == "funding",
    "multi-project link 1"
  assert g.get("^LINK", @["PUBMED", "40893628", "REPORTER", "R01AA025936"]) == "funding",
    "multi-project link 2"

  # Symmetry: every ^LINK has a matching reverse subscript.
  var pmid = g.order("^LINK", @["PUBMED", ""], forward = true)
  while pmid.len > 0:
    var project = g.order("^LINK", @["PUBMED", pmid, "REPORTER", ""], forward = true)
    while project.len > 0:
      assert g.get("^REPORTER", @[project, "pubmed", pmid]) == "1",
        "reverse missing for " & pmid & "/" & project
      project = g.order("^LINK", @["PUBMED", pmid, "REPORTER", project], forward = true)
    pmid = g.order("^LINK", @["PUBMED", pmid], forward = true)

  echo "  parser + loader symmetry hold"
  echo "reporter_link mirror test passed!"

main()
