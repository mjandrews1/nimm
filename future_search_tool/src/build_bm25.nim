# build_bm25.nim — CLI: build the ^BM25* index with the Nim builder.
# Mirrors bm25idx.m COMMON (BUILDMESH/BUILDCAT/BUILDSER/BUILDPUB) but runs the
# build in-process over globals.nim, flushing the LMDB write txn every N docs.
#
# Usage: nim c -d:release -o:future_search_tool/src/build_bm25 \
#          future_search_tool/src/build_bm25.nim
#        ./future_search_tool/src/build_bm25 <db> <src> <glob> <flist> [flushEvery]

import os
import strutils
import times
import ../../globals
import global_bm25

proc main() =
  let p = commandLineParams()
  if p.len < 4:
    echo "usage: build_bm25 <db> <src> <glob> <flist> [flushEvery]"
    quit(1)
  let db = p[0]
  let src = p[1]
  let glob = p[2]
  let flist = p[3]
  let flushEvery = if p.len >= 5: parseInt(p[4]) else: 1000

  var g = newGlobals(db)
  let start = epochTime()
  let (docs, tokens, avgdl) = g.buildIndex(src, glob, flist, flushEvery)
  let elapsed = epochTime() - start
  echo "BM25IDX DONE ", src, " docs=", docs, " tokens=", tokens,
       " avgdl=", formatFloat(avgdl, ffDecimal, 2),
       " elapsed=", formatFloat(elapsed, ffDecimal, 1), "s"
  g.close()

main()
