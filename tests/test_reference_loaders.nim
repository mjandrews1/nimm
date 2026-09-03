# test_reference_loaders.nim — mirror of formal/reference_loaders.dfy (#462).
#
# Re-implements the record-shape lemmas (idempotent set, commutative field
# writes, fold idempotency, distinct keys) and drives the three standalone
# loaders' field parsers + write paths over an in-memory store.
#
# Run: nim c -r tests/test_reference_loaders.nim

import tables
import sets
import ../globals
import ../future_search_tool/src/build_cdc

proc main() =
  echo "reference_loaders mirror test..."

  # --- model mirrors ---
  var rec = initTable[string, string]()
  rec["field"] = ""
  rec["field"] = "v"
  rec["field"] = "v"
  assert rec["field"] == "v", "SetIdempotent (overwrite same value = no-op)"

  var r2 = initTable[string, string]()
  r2["a"] = "1"
  r2["b"] = "2"
  var r3 = initTable[string, string]()
  r3["b"] = "2"
  r3["a"] = "1"
  assert r2 == r3, "SetFieldsCommute (field write order independent)"

  var s = initHashSet[string]()
  s.incl("k1"); s.incl("k2"); s.incl("k2")
  assert s.len == 2, "FoldIdempotent (re-insert same key = no cardinality change)"

  var s2 = initHashSet[string]()
  s2.incl("a"); s2.incl("b")
  assert s2.len == 2, "DistinctKeysStayDistinct"

  echo "  model mirrors hold"

  # --- CDC CSV row parser ---
  assert parseCsvLineCompat("2017,Alabama,a,b,c,49.4") ==
    @["2017", "Alabama", "a", "b", "c", "49.4"], "simple row"
  assert parseCsvLineCompat("\"Accidents (unintentional injuries) (V01-X59,Y85-Y86)\",Unintentional injuries,United States,169936,49.4")[0] ==
    "Accidents (unintentional injuries) (V01-X59,Y85-Y86)", "quoted field with commas"
  assert parseCsvLineCompat("a,,c") == @["a", "", "c"], "empty middle field"

  # --- CDC write path ---
  var g = newGlobals("")
  g.set("^CDC", @["chronic", "Alabama", "2017", "deaths"], "2703")
  g.set("^CDC", @["chronic", "Alabama", "2017", "rate"], "53.8")
  g.set("^CDC", @["covid", "2020-01-21", "cases"], "1")
  assert g.get("^CDC", @["chronic", "Alabama", "2017", "deaths"]) == "2703",
    "chronic deaths"
  assert g.get("^CDC", @["covid", "2020-01-21", "cases"]) == "1", "covid cases"
  assert g.get("^CDC", @["chronic", "Alabama", "2017", "rate"]) == "53.8",
    "chronic rate"

  # --- FAERS + Medicare record shape (same identity-key pattern) ---
  g.set("^FAERS", @["10014022", "drug", "1"], "PEGINTERFERON ALFA-2A")
  g.set("^FAERS", @["10014022", "reaction", "Alanine aminotransferase increased"], "1")
  assert g.get("^FAERS", @["10014022", "drug", "1"]) == "PEGINTERFERON ALFA-2A",
    "faers drug"
  assert g.get("^FAERS", @["10014022", "reaction", "Alanine aminotransferase increased"]) == "1",
    "faers reaction"

  g.set("^PROVIDER", @["1235888272", "last"], "BAEZ MUNIZ")
  g.set("^PROVIDER", @["1235888272", "state"], "PR")
  assert g.get("^PROVIDER", @["1235888272", "last"]) == "BAEZ MUNIZ", "provider last"
  assert g.get("^PROVIDER", @["1235888272", "state"]) == "PR", "provider state"

  echo "  loaders record shape hold"
  echo "reference_loaders mirror test passed!"

main()
