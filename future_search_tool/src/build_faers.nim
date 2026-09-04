# build_faers.nim — load FAERS quarterly ASCII tables into ^FAERS (#462).
#
# FAERS ships per-quarter `$`-delimited ASCII tables (DEMO/DRUG/REAC/INDI/OUT/
# THER). Loads DRUG and REAC centered on the case id:
#   ^FAERS(caseid, "drug", seq) = drugname
#   ^FAERS(caseid, "reaction", meddraPT) = "1"
#   ^FAERS(caseid, "meta", "quarter") = "20xxqN"
# Documents *no* deterministic cross-link to RxNorm/MeSH (FAERS drug names are
# free-text; the UNII join lives in RxNorm, pending a UTS key).
#
# The directory is expected to contain faers_ascii_20xxqN.zip files; each holds
# ASCII/DRUG*.txt and ASCII/REAC*.txt. Stream-unzips like build_reporter_link.
#
# Usage: nim c -d:release --path:. -o:bin/build_faers \
#          future_search_tool/src/build_faers.nim
#        ./bin/build_faers <db> <faers_dir>

import os
import osproc
import streams
import strutils
import sets
import ../../globals

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_faers <db> <faers_dir>"
    quit(1)
  let db = p[0]
  let dir = p[1]

  var g = newGlobals(db)
  var drugs = 0
  var reactions = 0
  var zips = 0

  proc ingestOne(entry, member, quarter, kind: string): int =
    let uz = startProcess("unzip", args = ["-p", entry, member],
                          options = {poStdErrToStdOut, poUsePath})
    let s = uz.outputStream
    var line = ""
    var first = true
    var n = 0
    var seenCases = initHashSet[string]()
    while s.readLine(line):
      if first: first = false; continue
      let f = line.strip(leading=false, trailing=true).split('$')
      if f.len < 2: continue
      let caseid = f[1]
      if caseid.len == 0: continue
      if kind == "drug" and f.len > 4:
        g.set("^FAERS", @[caseid, "drug", f[2]], f[4])   # role field 2, drugname field 4
      elif kind == "reac" and f.len > 3 and f[3].len > 0:
        g.set("^FAERS", @[caseid, "reaction", f[3]], "1")  # MedDRA PT field 3
      if caseid notin seenCases:
        seenCases.incl(caseid)
        g.set("^FAERS", @[caseid, "meta", "quarter"], quarter)
      inc n
      if n mod 20000 == 0:
        g.endWriteBatch()
        g.beginWriteBatch()
    discard uz.waitForExit(); uz.close()
    return n

  g.beginWriteBatch()
  for entry in walkFiles(dir & "/*.zip"):
    if "faers_ascii_" notin extractFilename(entry):
      continue
    let quarter = extractFilename(entry).split("faers_ascii_")[1].split(".zip")[0]
    inc zips
    # list table names inside the zip to find DRUG*/REAC* member paths
    let ls = startProcess("unzip", args = ["-Z1", entry], options = {poUsePath})
    let lsStream = ls.outputStream
    var zline = ""
    var drugMembers: seq[string] = @[]
    var reacMembers: seq[string] = @[]
    while lsStream.readLine(zline):
      if "ASCII/DRUG" in zline: drugMembers.add(zline)
      if "ASCII/REAC" in zline: reacMembers.add(zline)
    discard ls.waitForExit(); ls.close()

    for m in drugMembers:
      drugs += ingestOne(entry, m, quarter, "drug")
    for m in reacMembers:
      reactions += ingestOne(entry, m, quarter, "reac")
    stderr.writeLine("  [", quarter, "] ", extractFilename(entry))
  g.endWriteBatch()

  echo "faers DONE zips=", zips, " drugs=", drugs, " reactions=", reactions
  g.markUpdated("faers")
  g.close()

when isMainModule:
  main()
