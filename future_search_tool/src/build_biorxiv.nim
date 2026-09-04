# build_biorxiv.nim — load medRxiv (and later bioRxiv) preprints into ^BIORXIV (#469).
#
# Walks the bioRxiv API (`api.biorxiv.org/details/<server>/<interval>/<cursor>`)
# which returns JSON. Each preprint is keyed by DOI:
#   ^BIORXIV(doi, "title"|"abstract"|"authors"|"category"|"date"|"server"|"version") = v
#   ^BIORXIV(doi, "published") = publishedDOI   (only when != "NA"; post-publication)
#
# The summary API has NO PMID; the preprint->journal PMID lives only in the
# full-source jatsxml, deferred. So v1 stores the preprint record + its
# `published` DOI with no ^LINK (no reliable cross-key to ^PUBMED yet).
#
# Usage: nim c -d:release --path:. -o:bin/build_biorxiv \
#          future_search_tool/src/build_biorxiv.nim
#        ./bin/build_biorxiv <db> <server> <startDate> <endDate>

import os
import json
import strutils
import httpclient
import ../../globals

proc main() =
  let p = commandLineParams()
  if p.len < 4:
    echo "usage: build_biorxiv <db> <server(medrxiv|biorxiv)> <startYYYY-MM-DD> <endYYYY-MM-DD>"
    quit(1)
  let db = p[0]
  let server = p[1]
  let startDate = p[2]
  let endDate = p[3]

  var g = newGlobals(db)
  var records = 0
  var cursor = 0
  var client = newHttpClient()

  g.beginWriteBatch()
  while true:
    let url = "https://api.biorxiv.org/details/" & server & "/" &
              startDate & "/" & endDate & "/" & $cursor
    var body = ""
    try:
      body = client.getContent(url)
    except:
      stderr.writeLine("  [http] fetch failed at cursor ", cursor)
      break

    let node = try: parseJson(body) except: (stderr.writeLine("  [json] parse failed"); break)
    let collection = node.getOrDefault("collection")
    if collection.kind != JArray or collection.len == 0:
      break

    for item in collection:
      let doi = item{"doi"}.getStr("")
      if doi.len == 0:
        continue
      proc f(k: string): string = item{k}.getStr("")
      g.set("^BIORXIV", @[doi, "title"], f("title"))
      g.set("^BIORXIV", @[doi, "abstract"], f("abstract"))
      g.set("^BIORXIV", @[doi, "authors"], f("authors"))
      g.set("^BIORXIV", @[doi, "category"], f("category"))
      g.set("^BIORXIV", @[doi, "date"], f("date"))
      g.set("^BIORXIV", @[doi, "server"], f("server"))
      g.set("^BIORXIV", @[doi, "version"], f("version"))
      let published = f("published")
      if published.len > 0 and published != "NA":
        g.set("^BIORXIV", @[doi, "published"], published)
      inc records

    # Advance the cursor by the message count (the API returns `count` per page).
    var count = 0
    if "messages" in node and node["messages"].kind == JArray and node["messages"].len > 0:
      let m = node["messages"][0]
      count = m{"count"}.getInt(0)
    cursor += count
    if count == 0:
      break
    g.endWriteBatch()
    g.beginWriteBatch()
    stderr.writeLine("  [", server, "] ", records, " records (cursor ", cursor, ")")

  g.endWriteBatch()
  client.close()
  echo "biorxiv DONE server=", server, " records=", records
  g.close()

when isMainModule:
  main()
