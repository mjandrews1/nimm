# test_biorxiv_link.nim — mirror of formal/bioxiv_link.dfy (#469).
#
# Re-implements the IsPublished/"NA" gate, the forward/reverse link
# consistency, and query duality as pure Nim, then drives the loader's write
# path over an in-memory store via a small JSON snippet.
#
# Run: nim c -r tests/test_biorxiv_link.nim

import json
import sets
import ../globals

type Link = tuple[preprint, pub: string]

proc isPublished(pub: string): bool =
  pub.len > 0 and pub != "NA"

proc main() =
  echo "biorxiv_link mirror test..."

  # --- Part 1: pure mirrors of bioxiv_link.dfy ---
  # NaGate: unpublished ("NA"/"") -> no link.
  assert not isPublished("NA"), "NA is not published"
  assert not isPublished(""), "empty is not published"
  assert isPublished("10.1016/j.annemergmed.2024.03.014"), "real DOI is published"

  # Link consistency + idempotency over (preprint, pub) pairs.
  var fwd = initHashSet[Link]()
  var rev = initHashSet[Link]()
  proc linkBoth(p: Link) = (fwd.incl(p); rev.incl(p))
  let l1: Link = ("10.1101/x", "10.1016/y")
  linkBoth(l1)
  assert fwd == rev, "forward == reverse after link"
  let before = fwd.len
  linkBoth(l1)
  assert fwd.len == before, "idempotent link"

  # Query duality.
  var links = initHashSet[Link]()
  links.incl(("10.1101/a", "10.1016/b"))
  links.incl(("10.1101/c", "10.1016/b"))
  for (preprint, pub) in links:
    var pubsOfPreprint = initHashSet[string]()
    for l in links:
      if l.preprint == preprint: pubsOfPreprint.incl(l.pub)
    assert pub in pubsOfPreprint, "published-of forward"

  echo "  NA gate, consistency, idempotency, duality hold"

  # --- Part 2: loader write path over a JSON snippet ---
  echo "--- loader path ---"
  let j = parseJson("""{
    "collection": [
      {"doi":"10.1101/a","title":"Alpha preprint","server":"medRxiv","published":"10.1016/b"},
      {"doi":"10.1101/c","title":"Gamma arXiv","server":"medRxiv","published":"NA"}
    ]
  }""")
  var g = newGlobals("")
  for item in j["collection"]:
    let doi = item{"doi"}.getStr("")
    g.set("^BIORXIV", @[doi, "title"], item{"title"}.getStr(""))
    g.set("^BIORXIV", @[doi, "server"], item{"server"}.getStr(""))
    let published = item{"published"}.getStr("")
    if isPublished(published):
      g.set("^BIORXIV", @[doi, "published"], published)

  # Published-preprint got the link; the "NA" preprint did NOT.
  assert g.get("^BIORXIV", @["10.1101/a", "published"]) == "10.1016/b",
    "published DOI stored for published preprint"
  assert g.get("^BIORXIV", @["10.1101/c", "published"]) == "",
    "NA preprint has NO published link (join gate)"

  echo "  loader join gate holds"
  echo "biorxiv_link mirror test passed!"

main()
