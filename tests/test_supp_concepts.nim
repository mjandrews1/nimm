# test_supp_concepts.nim — mirror of formal/supp_concepts.dfy (#462 Phase 1).
#
# Part 1 re-implements the model's StripStar/Mapped/Consistent/query-duality as
# pure Nim and asserts the lemmas (idempotency, bare-DUI soundness,
# link/unlink consistency, idempotent dedup, inverse query views).
#
# Part 2 drives the actual loader (loadXmlData "scr" format) on a small
# SupplementalRecordSet and checks the ^SUPP record fields, the star-stripped
# MESH→SUPP ^LINK, and the reverse per-record subscript.
#
# Run: nim c -r tests/test_supp_concepts.nim

import os
import sets
import ../globals
import ../xmlload

# --- Part 1: pure mirrors ---

proc stripStar(s: string): string =
  var i = 0
  while i < s.len and s[i] == '*':
    inc i
  return (if i >= s.len: "" else: s[i ..^ 1])

proc mapped(raw: seq[string]): HashSet[string] =
  result = initHashSet[string]()
  for u in raw:
    result.incl(stripStar(u))

type Link = tuple[dui, scrui: string]

proc recordsOf(links: HashSet[Link], dui: string): HashSet[string] =
  result = initHashSet[string]()
  for l in links:
    if l.dui == dui: result.incl(l.scrui)

proc descriptorsOf(links: HashSet[Link], scrui: string): HashSet[string] =
  result = initHashSet[string]()
  for l in links:
    if l.scrui == scrui: result.incl(l.dui)

proc main() =
  echo "supp_concepts mirror test..."

  # StripStarIdempotent + BareDui.
  for s in ["", "D001561", "*D001561", "**D001561"]:
    assert stripStar(stripStar(s)) == stripStar(s), "idempotent: " & s
    assert stripStar(s) == "" or stripStar(s)[0] != '*', "bare: " & s

  # MappedSound: every mapped DUI is bare.
  let raw = @["*D001561", "D000894", "**D002"]
  let m = mapped(raw)
  assert "*D001561" notin m and "D001561" in m, "star stripped from first"
  assert "D000894" in m, "bare already"
  assert "D002" in m and "**D002" notin m, "all stars stripped"
  for u in m:
    assert u == "" or u[0] != '*', "mapped sound: " & u

  # LinkBothPreserves / UnlinkBothPreserves / LinkBothIdempotent.
  var fwd = initHashSet[Link]()
  var rev = initHashSet[Link]()
  let l1: Link = ("D001561", "C000001")
  let l2: Link = ("D000894", "C000001")
  proc linkBoth(p: Link) =
    fwd.incl(p); rev.incl(p)
  proc unlinkBoth(p: Link) =
    fwd.excl(p); rev.excl(p)
  linkBoth(l1); linkBoth(l2)
  assert fwd == rev, "consistent after linkBoth"
  unlinkBoth(l1)
  assert fwd == rev, "consistent after unlinkBoth"
  assert l1 notin fwd and l2 in fwd, "l1 removed, l2 kept"
  let n = fwd.len
  linkBoth(l2)  # already present
  assert fwd.len == n, "idempotent re-link"

  # QueryDuality.
  var links = initHashSet[Link]()
  links.incl(("D001561", "C000001"))
  links.incl(("D001561", "C000002"))
  links.incl(("D000894", "C000001"))
  let r = recordsOf(links, "D001561")
  assert r == toHashSet(["C000001", "C000002"]), "recordsOf"
  let d = descriptorsOf(links, "C000001")
  assert d == toHashSet(["D001561", "D000894"]), "descriptorsOf"
  for dui in ["D001561", "D000894"]:
    for scrui in ["C000001", "C000002"]:
      assert (scrui in recordsOf(links, dui)) == (dui in descriptorsOf(links, scrui)),
        "duality: " & dui & " / " & scrui

  echo "  model mirrors hold"

  # --- Part 2: loader end-to-end ---
  echo "--- loader test ---"
  let xml = "<?xml version=\"1.0\"?>\n" &
    "<SupplementalRecordSet>\n" &
    "<SupplementalRecord SCRClass = \"1\">\n" &
    "  <SupplementalRecordUI>C000001</SupplementalRecordUI>\n" &
    "  <SupplementalRecordName><String>bevonium</String></SupplementalRecordName>\n" &
    "  <Note>test note</Note>\n" &
    "  <Frequency>1</Frequency>\n" &
    "  <HeadingMappedToList><HeadingMappedTo><DescriptorReferredTo>\n" &
    "    <DescriptorUI>*D001561</DescriptorUI>\n" &
    "    <DescriptorName><String>Benzilates</String></DescriptorName>\n" &
    "  </DescriptorReferredTo></HeadingMappedTo></HeadingMappedToList>\n" &
    "  <PharmacologicalActionList><PharmacologicalAction><DescriptorReferredTo>\n" &
    "    <DescriptorUI>D000894</DescriptorUI>\n" &
    "  </DescriptorReferredTo></PharmacologicalAction></PharmacologicalActionList>\n" &
    "  <ConceptList><Concept><ConceptUI>M0040005</ConceptUI>\n" &
    "    <RegistryNumberList><RegistryNumber>34B0471E08</RegistryNumber></RegistryNumberList>\n" &
    "  </Concept></ConceptList>\n" &
    "</SupplementalRecord>\n" &
    "</SupplementalRecordSet>\n"

  let path = getTempDir() / "test_supp_concepts.xml"
  writeFile(path, xml)
  var g = newGlobals("")
  let count = loadXmlData(g, path, "^SUPP", "scr")
  removeFile(path)
  assert count == 1, "loaded 1 record, got " & $count
  assert g.get("^SUPP", @["C000001", "name"]) == "bevonium", "name"
  assert g.get("^SUPP", @["C000001", "class"]) == "1", "class"
  assert g.get("^SUPP", @["C000001", "note"]) == "test note", "note"
  assert g.get("^SUPP", @["C000001", "frequency"]) == "1", "frequency"
  assert g.get("^SUPP", @["C000001", "regnum", "34B0471E08"]) == "1", "regnum"
  assert g.get("^SUPP", @["C000001", "concept", "M0040005"]) == "1", "concept"
  assert g.get("^SUPP", @["C000001", "mesh", "D001561"]) == "1", "mesh (star stripped)"
  assert g.get("^SUPP", @["C000001", "pharmaction", "D000894"]) == "1", "pharmaction"
  assert g.get("^LINK", @["MESH", "D001561", "SUPP", "C000001"]) == "supplemental", "fwd link"
  assert g.get("^SUPP", @["C000001", "mesh", "*D001561"]) == "", "no starred key in mesh"

  echo "  loader fields + links hold"
  echo "supp_concepts mirror test passed!"

main()
