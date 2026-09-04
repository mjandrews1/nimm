# build_pubmed_baseline.nim — load the full PubMed baseline into ^PUBMED in ONE
# process (#474/#478). Opens the DB once (nosync, disposable load) and walks all
# staged .xml.gz files, calling loadXmlData per file in-process — avoiding the
# 1334-process re-open tax and the long-lived-reader contention (#478) that made
# the per-file script approach multi-day-slow.
#
# Usage: nim c -d:release -d:ssl --path:. -o:bin/build_pubmed_baseline \
#          future_search_tool/src/build_pubmed_baseline.nim
#        ./bin/build_pubmed_baseline <db> <baseline_dir>

import os
import streams
import strutils
import ../../globals
import ../../xmlload

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_pubmed_baseline <db> <baseline_dir>"
    quit(1)
  let db = p[0]
  let dir = p[1]

  var g = newGlobals(db, nosync = true)   # disposable load; MDB_NOSYNC (#461)
  var files = 0
  var records = 0
  for path in walkFiles(dir & "/*.xml.gz"):
    let n = g.loadXmlData(path, "^PUBMED", "pubmed")
    records += n
    inc files
    if files mod 25 == 0:
      stderr.writeLine("  [pubmed] ", files, " files / ", records, " records")
      echo "[pubmed] ", files, " files / ", records, " records"
  echo "pubmed-baseline DONE files=", files, " records=", records
  g.close()

when isMainModule:
  main()
