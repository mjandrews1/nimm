# build_bm25.nim — CLI: build the ^BM25* index with the Nim builder.
# Mirrors bm25idx.m COMMON (BUILDMESH/BUILDCAT/BUILDSER/BUILDPUB) but runs the
# build in-process over globals.nim, flushing the LMDB write txn every N docs.
#
# Usage: nim c -d:release -o:bin/build_bm25 \
#          future_search_tool/src/build_bm25.nim
#        ./bin/build_bm25 <db> <src> <glob> <flist> [flushEvery] [--nosync]

import os
import strutils
import times
import ../../globals
import global_bm25

proc main() =
  let p = commandLineParams()
  var args: seq[string] = @[]
  var nosync = false
  var posOnly = false
  for a in p:
    if a == "--nosync": nosync = true
    elif a == "--pos": posOnly = true
    else: args.add(a)
  if args.len < 4:
    echo "usage: build_bm25 <db> <src> <glob> <flist> [flushEvery] [--nosync] [--pos]"
    quit(1)
  let db = args[0]
  let src = args[1]
  let glob = args[2]
  let flist = args[3]
  let flushEvery = if args.len >= 5: parseInt(args[4]) else: 1000

  var g = newGlobals(db, nosync = nosync)
  let start = epochTime()
  if posOnly:
    let (docs, tokens) = g.buildPositions(src, glob, flist, flushEvery)
    let elapsed = epochTime() - start
    echo "BMPOS DONE ", src, " docs=", docs, " tokens=", tokens,
         " elapsed=", formatFloat(elapsed, ffDecimal, 1), "s",
         (if nosync: " [nosync]" else: "")
  else:
    let (docs, tokens, avgdl) = g.buildIndex(src, glob, flist, flushEvery)
    let elapsed = epochTime() - start
    echo "BM25IDX DONE ", src, " docs=", docs, " tokens=", tokens,
         " avgdl=", formatFloat(avgdl, ffDecimal, 2),
         " elapsed=", formatFloat(elapsed, ffDecimal, 1), "s",
         (if nosync: " [nosync]" else: "")
  g.close()

main()
