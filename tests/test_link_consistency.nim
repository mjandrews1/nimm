# test_link_consistency.nim — mirror of formal/link_consistency.dfy (#459).
#
# Exercises the ^LINK cross-reference design in memory before any loader code
# lands: the forward (^LINK MESH→record) and reverse (per-record "mesh"
# subscript) encodings of a link relation stay equal under link/unlink; linking
# is idempotent; name→UI resolution never emits a dangling link; and the two
# query directions are dual.
#
# Run: nim c -r tests/test_link_consistency.nim

import tables
import sets
import ../globals
import ../xmlload

type
  Target = enum tPubmed, tCatline, tSerline
  Link = tuple[dui: string, t: Target, id: string]

proc linkBoth(fwd: var HashSet[Link], rev: var HashSet[Link], l: Link) =
  fwd.incl(l)
  rev.incl(l)

proc unlinkBoth(fwd: var HashSet[Link], rev: var HashSet[Link], l: Link) =
  fwd.excl(l)
  rev.excl(l)

proc main() =
  echo "link_consistency mirror test..."

  # --- 1. forward/reverse stay equal under link + unlink ---
  var fwd: HashSet[Link]
  var rev: HashSet[Link]

  let l1: Link = ("D001", tCatline, "C1")
  let l2: Link = ("D001", tPubmed, "P1")
  linkBoth(fwd, rev, l1)
  linkBoth(fwd, rev, l2)
  assert fwd == rev, "after linkBoth, fwd == rev"

  unlinkBoth(fwd, rev, l1)
  assert fwd == rev, "after unlinkBoth, fwd == rev"
  assert l1 notin fwd and l1 notin rev, "l1 removed from both"
  assert l2 in fwd and l2 in rev, "l2 still in both"

  # --- 2. idempotent dedup ---
  let before = fwd.len
  linkBoth(fwd, rev, l2)  # already present
  assert fwd.len == before, "re-link existing pair is a no-op"
  assert fwd == rev, "still equal after idempotent re-link"

  # --- 3. name→UI resolution soundness (no dangling links) ---
  # resolve: only names in the dictionary map to a descriptor UI.
  var dict = initTable[string, string]()  # name -> dui
  dict["Hypertension"] = "D0001"
  dict["High blood pressure"] = "D0001"

  proc buildLinks(t: Target, id: string, names: seq[string]): seq[Link] =
    result = @[]
    for n in names:
      if dict.hasKey(n):
        result.add((dict[n], t, id))

  let links = buildLinks(tCatline, "C2", @["Hypertension", "Not a real heading", "High blood pressure"])
  assert links.len == 2, "only resolvable names produce links"
  for l in links:
    var known = false
    for dui in dict.values:
      if dui == l.dui: known = true
    assert known, "every built link references a known descriptor"

  # --- 4. query duality: records-of and descriptors-of are inverse views ---
  proc recordsOf(links: HashSet[Link], t: Target, dui: string): seq[string] =
    result = @[]
    for l in links:
      if l.t == t and l.dui == dui: result.add(l.id)

  proc descriptorsOf(links: HashSet[Link], t: Target, id: string): seq[string] =
    result = @[]
    for l in links:
      if l.t == t and l.id == id: result.add(l.dui)

  var all: HashSet[Link]
  all.incl(("D0001", tCatline, "C1"))
  all.incl(("D0001", tSerline, "S1"))
  all.incl(("D0002", tCatline, "C1"))
  # D0001 ↔ C1 both ways
  assert "C1" in recordsOf(all, tCatline, "D0001"), "forward: C1 in recordsOf D0001"
  assert "D0001" in descriptorsOf(all, tCatline, "C1"), "reverse: D0001 in descriptorsOf C1"

  # --- 5. loader helpers: meshSubjectNames + resolveName (#459) ---
  var g = newGlobals("")
  g.set("^MESHTERM", @["heart", "D0001"], "1")
  g.set("^MESHTERM", @["cardiac", "D0001"], "0")
  g.set("^MESHTERM", @["cardiac", "D0002"], "0")
  g.set("^MESHTERM", @["heart diseases", "D0002"], "1")

  let rec = "<marc:record>\n" &
    "<marc:datafield tag=\"650\" ind1=\"1\" ind2=\"2\"><marc:subfield code=\"a\">Heart</marc:subfield></marc:datafield>\n" &
    "<marc:datafield tag=\"650\" ind1=\"1\" ind2=\"2\"><marc:subfield code=\"a\">Cardiac</marc:subfield></marc:datafield>\n" &
    "<marc:datafield tag=\"610\" ind1=\"2\" ind2=\"2\"><marc:subfield code=\"a\">Heart Diseases</marc:subfield></marc:datafield>\n" &
    "<marc:datafield tag=\"650\" ind1=\"1\" ind2=\"0\"><marc:subfield code=\"a\">Not MeSH</marc:subfield></marc:datafield>\n" &
    "<marc:datafield tag=\"700\" ind1=\"1\" ind2=\" \"><marc:subfield code=\"a\">Smith, John</marc:subfield></marc:datafield>\n" &
    "</marc:record>"

  # MeSH 6xx headings only (650 ind2=2 + 610 ind2=2); LCSH 650 ind2=0 and the
  # 700 name authority are excluded.
  let heads = meshSubjectNames(rec)
  assert heads == @["Heart", "Cardiac", "Heart Diseases"], "meshSubjectNames: got " & $heads

  # Exact-name resolution; ambiguous synonym (Cardiac → two descriptors) → "".
  assert resolveName(g, "Heart") == "D0001", "resolve Heart"
  assert resolveName(g, "Heart Diseases") == "D0002", "resolve Heart Diseases"
  assert resolveName(g, "Cardiac") == "", "resolve Cardiac (ambiguous)"
  assert resolveName(g, "Not a heading") == "", "resolve absent name"

  echo "  forward/reverse consistency, dedup, soundness, duality, loader helpers all hold"
  echo "link_consistency mirror test passed!"

main()
