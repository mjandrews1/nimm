# db_audit.nim — read-only consistency probe over a live LMDB DB (#464).
#
# Sampled checks of invariants the Dafny models prove, run against the actual
# artifact. Opens the DB read-only (never blocks a writer).
#
#   Probe 1: ^LINK forward↔reverse symmetry. Every MeSH-outbound link
#            ^LINK("MESH",dui,type,id) must have the matching per-record
#            subscript ^TYPE(id,"mesh",dui)="1" (link_consistency.dfy).
#   Probe 2: ^BM25DF(term,src) must equal the distinct-doc count of
#            ^BM25(term,src,*) (search_engine.dfy df-vs-tf).
#
# Usage: nim c -d:release --path:. -o:bin/db_audit future_search_tool/src/db_audit.nim
#        ./bin/db_audit <db_path> [link_sample] [df_sample]

import os
import strutils
import ../../globals

proc parseIntOr(s: string, def: int): int =
  try: parseInt(s) except: def

proc main() =
  let p = commandLineParams()
  if p.len < 1:
    echo "usage: db_audit <db> [link_sample] [df_sample]"
    quit(1)
  let linkSample = if p.len > 1: parseInt(p[1]) else: 2000
  let dfSample = if p.len > 2: parseInt(p[2]) else: 500

  var g = newGlobals(p[0], readOnly = true)

  # --- Probe 1: ^LINK forward -> reverse symmetry ---
  # ^LINK(fromType, fromId, toType, toId). Iterate fromId (level 1) under
  # fromType="MESH", then toType (level 2), then toId (level 3) — using the
  # null-subscript start convention $ORDER(^LINK("MESH","")) mirrors.
  var checked = 0
  var linkMis = 0
  var dui = g.order("^LINK", @["MESH", ""], forward = true)
  while dui.len > 0 and checked < linkSample:
    var gtype = g.order("^LINK", @["MESH", dui, ""], forward = true)
    while gtype.len > 0 and checked < linkSample:
      var id = g.order("^LINK", @["MESH", dui, gtype, ""], forward = true)
      while id.len > 0 and checked < linkSample:
        let rev = g.get("^" & gtype, @[id, "mesh", dui])
        if rev != "1":
          inc linkMis
        inc checked
        id = g.order("^LINK", @["MESH", dui, gtype, id], forward = true)
      gtype = g.order("^LINK", @["MESH", dui, gtype], forward = true)
    dui = g.order("^LINK", @["MESH", dui], forward = true)
  echo "LINK symmetry: checked=", checked, " mismatches=", linkMis

  # --- Probe 2: ^BM25DF == distinct doc count ---
  # ^BM25DF(term, src); ^BM25(term, src, id). Iterate term (level 0), then for a
  # term iterate src (level 1), then id (level 2).
  var dfChecked = 0
  var dfMis = 0
  var term = g.order("^BM25DF", @[], forward = true)
  while term.len > 0 and dfChecked < dfSample:
    for src in ["PUBMED", "MESH", "CATLINE", "SERLINE"]:
      if dfChecked >= dfSample: break
      let df = g.get("^BM25DF", @[term, src])
      if df.len == 0: continue
      var docCount = 0
      var id = g.order("^BM25", @[term, src, ""], forward = true)
      while id.len > 0:
        inc docCount
        id = g.order("^BM25", @[term, src, id], forward = true)
      if docCount != parseIntOr(df, -1):
        inc dfMis
      inc dfChecked
    term = g.order("^BM25DF", @[term], forward = true)
  echo "BM25DF==doccount: checked=", dfChecked, " mismatches=", dfMis

  g.close()
  echo "db_audit done"

main()
