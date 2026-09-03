# build_clinicaltrials.nim — load ClinicalTrials.gov studies into ^CTRIAL (#462).
#
# Streams the (pretty-printed) JSON studies array. Each study links to MeSH via
# the NLM-curated conditionBrowseModule: `meshes[].id` and `ancestors[].id` are
# MeSH descriptor UIs, so a study is linked to every descriptor it is tagged
# with (primary + broader):
#   ^CTRIAL(nct, "title"|"status"|...) = value
#   ^LINK("CTRIAL", nct, "MESH", dui) = "condition"    (forward)
#   ^MESH(dui, "ctrial", nct) = "1"                    (reverse)
#
# The input JSON needs no full in-memory parse: the studies array is
# brace-balanced per study, so we accumulate one study object at a time.
#
# Usage: nim c -d:release --path:. -o:bin/build_clinicaltrials \
#          future_search_tool/src/build_clinicaltrials.nim
#        ./bin/build_clinicaltrials <db> <file>

import os
import sets
import strutils
import ../../globals

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_clinicaltrials <db> <file>"
    quit(1)
  let db = p[0]
  let file = p[1]

  var g = newGlobals(db)
  var studies = 0
  var links = 0
  var distinctDui = initHashSet[string]()

  proc jsonStr(hay: string, key: string): string =
    ## Extract a JSON string value for `key` via a naive scanner sufficient for
    ## the (deterministic) API output: reads from  `"key": "` to the closing `"`.
    let start = hay.find("\"" & key & "\"")
    if start < 0: return ""
    let colon = hay.find(':', start)
    if colon < 0: return ""
    var i = colon + 1
    while i < hay.len and hay[i] in {' ', '\t', '\n', '\r'}: inc i
    if i >= hay.len or hay[i] != '"': return ""
    var j = i + 1
    while j < hay.len:
      if hay[j] == '\\':
        j += 2
      elif hay[j] == '"':
        break
      else:
        inc j
    return hay[i + 1 ..< j]

  proc jsonStrs(hay: string, key: string): seq[string] =
    ## All `"key": "v"` string values (for id fields under meshes/ancestors).
    result = @[]
    var pos = 0
    while true:
      let start = hay.find("\"" & key & "\"", pos)
      if start < 0: break
      let colon = hay.find(':', start)
      if colon < 0: break
      var i = colon + 1
      while i < hay.len and hay[i] in {' ', '\t', '\n', '\r'}: inc i
      if i >= hay.len or hay[i] != '"':
        pos = colon + 1
        continue
      var j = i + 1
      while j < hay.len:
        if hay[j] == '\\': j += 2
        elif hay[j] == '"': break
        else: inc j
      let v = hay[i + 1 ..< j]
      if v.len > 0: result.add(v)
      pos = j + 1

  # Stream the file; split study objects by brace depth. The top-level object is
  # `{"studies": [ {study}, {study}, ... ]}`. Skip the wrapper: a study begins at
  # the first `{` whose enclosing depth is 1 (inside the `studies` array), i.e.
  # every `{` after the array has begun is a study object.
  var depth = 0
  var inStudy = false
  var studyDepth = 0
  var inStudies = false
  var buf = ""
  var line = ""
  let f = open(file)
  g.beginWriteBatch()
  while f.readLine(line):
    for c in line:
      if c == '{':
        if inStudies and not inStudy:
          inStudy = true
          studyDepth = depth
          buf = ""
        inc depth
      elif c == '}':
        dec depth
        if inStudy and depth == studyDepth:
          # complete study object
          let nct = jsonStr(buf, "nctId")
          if nct.len > 0:
            let title = jsonStr(buf, "briefTitle")
            let status = jsonStr(buf, "overallStatus")
            if title.len > 0:
              g.set("^CTRIAL", @[nct, "title"], title)
            if status.len > 0:
              g.set("^CTRIAL", @[nct, "status"], status)
            # MeSH condition descriptors: every `"id": "D..."` under the study's
            # derivedSection (meshes + ancestors) is a MeSH DUI.
            var seen = initHashSet[string]()
            for id in jsonStrs(buf, "id"):
              if id.len > 0 and id[0] == 'D':
                if id in seen: continue
                seen.incl(id)
                g.set("^LINK", @["CTRIAL", nct, "MESH", id], "condition")
                g.set("^MESH", @[id, "ctrial", nct], "1")
                distinctDui.incl(id)
                inc links
            inc studies
            if studies mod 5000 == 0:
              g.endWriteBatch()
              g.beginWriteBatch()
              stderr.writeLine("  [studies] ", studies)
          inStudy = false
          buf = ""
        else:
          buf.add(c)
      elif c == '[':
        inc depth
        if depth == 2:
          inStudies = true
      elif c == ']':
        dec depth
      elif inStudy:
        buf.add(c)
  f.close()
  g.endWriteBatch()

  echo "clinicaltrials DONE studies=", studies,
       " links=", links,
       " distinct_mesh_dui=", distinctDui.len
  g.close()

when isMainModule:
  main()
