# build_cdc.nim — load the staged CDC CSV aggregates into ^CDC (#462).
#
# Three standalone CSVs, each a state×period aggregate keyed naturally:
#   ^CDC("chronic", state, year, "deaths"|"rate") = value
#   ^CDC("covid",  date, "cases"|"deaths") = value
#   ^CDC("natality", state, year, month, indicator) = value
# Standalone reference tables (no deterministic join to the clinical graph).
#
# Usage: nim c -d:release --path:. -o:bin/build_cdc \
#          future_search_tool/src/build_cdc.nim
#        ./bin/build_cdc <db> <cdc_dir>

import os
import sets
import strutils
import ../../globals

# Minimal RFC-4180-ish row splitter that tolerates the CDC quoting.
proc parseCsvLineCompat*(line: string): seq[string] =
  result = @[]
  var cur = ""
  var inQ = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if inQ:
      if c == '"':
        if i + 1 < line.len and line[i + 1] == '"':
          cur.add('"'); inc i
        else:
          inQ = false
      else:
        cur.add(c)
    else:
      if c == '"':
        inQ = true
      elif c == ',':
        result.add(cur); cur = ""
      else:
        cur.add(c)
    inc i
  result.add(cur)

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_cdc <db> <cdc_dir>"
    quit(1)
  let db = p[0]
  let dir = p[1]

  var g = newGlobals(db)
  var chronic = 0
  var covid = 0
  var natality = 0

  g.beginWriteBatch()

  if fileExists(dir / "chronic_disease_indicators.csv"):
    var first = true
    for line in lines(dir / "chronic_disease_indicators.csv"):
      if first: first = false; continue
      let f = parseCsvLineCompat(line)
      if f.len < 6: continue
      let year = f[0]
      let state = f[3]
      let deaths = f[4]
      let rate = f[5]
      g.set("^CDC", @["chronic", state, year, "deaths"], deaths)
      g.set("^CDC", @["chronic", state, year, "rate"], rate)
      inc chronic

  if fileExists(dir / "covid_states.csv"):
    var first = true
    for line in lines(dir / "covid_states.csv"):
      if first: first = false; continue
      let f = parseCsvLineCompat(line)
      if f.len < 5: continue
      let date = f[0]
      let cases = f[3]
      let deaths = f[4]
      g.set("^CDC", @["covid", date, "cases"], cases)
      g.set("^CDC", @["covid", date, "deaths"], deaths)
      inc covid

  if fileExists(dir / "national_death_index.csv"):
    var first = true
    for line in lines(dir / "national_death_index.csv"):
      if first: first = false; continue
      let f = parseCsvLineCompat(line)
      if f.len < 6: continue
      let state0 = f[0]
      let year = f[1]
      let month = f[2]
      let indicator = f[4]
      let value = f[5]
      g.set("^CDC", @["natality", state0, year, month, indicator], value)
      inc natality

  g.endWriteBatch()

  echo "cdc DONE chronic=", chronic, " covid=", covid, " natality=", natality
  g.markUpdated("cdc")
  g.close()

when isMainModule:
  main()
