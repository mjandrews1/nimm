# build_medicare.nim — load the Medicare Provider Directory into ^PROVIDER (#462).
#
# providers.json is {"results":[ {npi, ...}, ... ], "count": N}. NPI is the
# provider NPI registry key. Loads a flat record keyed by NPI:
#   ^PROVIDER(npi, "last"|"first"|"gndr"|"pri_spec"|"state"|"zip"|"telephone") = v
#   ^PROVIDER(npi, "specialty", spec) = "1"     (pri + sec_1..4)
# Standalone: no deterministic join key to the MeSH/PubMed graph (provider NPI
# does not appear elsewhere), so this is a self-contained reference global.
#
# Usage: nim c -d:release --path:. -o:bin/build_medicare \
#          future_search_tool/src/build_medicare.nim
#        ./bin/build_medicare <db> <providers.json>

import os
import json
import sets
import strutils
import ../../globals

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_medicare <db> <providers.json>"
    quit(1)
  let db = p[0]
  let file = p[1]

  var g = newGlobals(db)
  var providers = 0

  let node = parseJson(readFile(file))
  let results = node["results"]
  g.beginWriteBatch()
  for item in results:
    let npi = item{"npi"}.getStr("")
    if npi.len == 0: continue
    proc fld(k: string): string = item{k}.getStr("")
    g.set("^PROVIDER", @[npi, "last"], fld("provider_last_name"))
    g.set("^PROVIDER", @[npi, "first"], fld("provider_first_name"))
    g.set("^PROVIDER", @[npi, "gndr"], fld("gndr"))
    g.set("^PROVIDER", @[npi, "pri_spec"], fld("pri_spec"))
    g.set("^PROVIDER", @[npi, "state"], fld("state"))
    g.set("^PROVIDER", @[npi, "zip"], fld("zip_code"))
    g.set("^PROVIDER", @[npi, "telephone"], fld("telephone_number"))
    for spec in @[fld("pri_spec"), fld("sec_spec_1"), fld("sec_spec_2"),
                  fld("sec_spec_3"), fld("sec_spec_4"), fld("sec_spec_all")]:
      if spec.len > 0:
        g.set("^PROVIDER", @[npi, "specialty", spec], "1")
    inc providers
    if providers mod 50000 == 0:
      g.endWriteBatch()
      g.beginWriteBatch()
      stderr.writeLine("  [providers] ", providers)
  g.endWriteBatch()

  echo "medicare DONE providers=", providers
  g.close()

when isMainModule:
  main()
