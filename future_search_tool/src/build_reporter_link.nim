# build_reporter_link.nim — build the PUBMED→REPORTER "funding" link from the
# NIH ExPORTER publications link tables (#462, RePORTER→PubMed by PMID).
#
# The ExPORTER "RePORTER Publications <year> link tables" files are CSVs of
#   "PMID","PROJECT_NUMBER"
# mapping each PubMed article to the NIH grant(s) that funded it (many-to-many).
# This writes, following the #466 PUBMED-outbound convention:
#   ^LINK("PUBMED", pmid, "REPORTER", project) = "funding"
#   ^REPORTER(project, "pubmed", pmid) = "1"          (reverse)
#
# Input: a directory of RePORTER_PUBLNK_C_FY*.zip files (each holds one CSV).
# Reports link totals and how many cited PMIDs are present in ^PUBMED.
#
# Usage: nim c -d:release --path:. -o:bin/build_reporter_link \
#          future_search_tool/src/build_reporter_link.nim
#        ./bin/build_reporter_link <db> <linktables_dir>

import os
import osproc
import strutils
import streams
import sets
import ../../globals

proc parseCsvLine*(line: string): tuple[pmid, project: string] =
  ## Parse a '"PMID","PROJECT_NUMBER"' line into (pmid, project). Tolerates an
  ## unquoted first field (older ExPORTER files: `3489745,"N01HV062923"`).
  var s = line
  if s.endsWith("\r"): s = s[0 ..^ 2]
  if s.len == 0: return ("", "")
  var first = ""
  var second = ""
  if s[0] == '"':
    # quoted first field
    let comma = s.find("\",\"")
    if comma < 0: return ("", "")
    first = s[1 ..< comma]
    var rest = s[(comma + 3) ..^ 1]
    if rest.len > 0 and rest[^1] == '"': rest = rest[0 ..^ 2]
    second = rest
  else:
    # unquoted first field: everything up to the first comma
    let comma = s.find(',')
    if comma < 0: return ("", "")
    first = s[0 ..< comma]
    var rest = s[(comma + 1) ..^ 1]
    if rest.len > 0 and rest[0] == '"': rest = rest[1 ..^ 1]
    if rest.len > 0 and rest[^1] == '"': rest = rest[0 ..^ 2]
    second = rest
  return (first, second)

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_reporter_link <db> <linktables_dir>"
    quit(1)
  let db = p[0]
  let dir = p[1]

  var g = newGlobals(db)
  var totalLinks = 0
  var totalCited = 0
  var distinctProjects = initHashSet[string]()
  var citedPmids = initHashSet[string]()
  var citedInPubmed = initHashSet[string]()
  var files = 0

  for entry in walkFiles(dir & "/*.zip"):
    inc files
    let uz = startProcess("unzip", args = ["-p", entry],
                          options = {poStdErrToStdOut, poUsePath})
    let stream = uz.outputStream
    var line = ""
    var first = true
    g.beginWriteBatch()
    var n = 0
    while stream.readLine(line):
      if first:
        first = false
        continue
      let (pmid, project) = parseCsvLine(line)
      if pmid.len == 0 or project.len == 0:
        continue
      if pmid == "PMID" and project == "PROJECT_NUMBER":
        continue
      g.set("^LINK", @["PUBMED", pmid, "REPORTER", project], "funding")
      g.set("^REPORTER", @[project, "pubmed", pmid], "1")
      distinctProjects.incl(project)
      citedPmids.incl(pmid)
      if g.get("^PUBMED", @[pmid, "title"]).len > 0:
        citedInPubmed.incl(pmid)
      inc n
      inc totalLinks
      if n mod 50000 == 0:
        g.endWriteBatch()
        g.beginWriteBatch()
    g.endWriteBatch()
    discard uz.waitForExit()
    uz.close()
    echo "  ", extractFilename(entry), ": ", n, " links"

  echo "reporter-link DONE files=", files,
       " links=", totalLinks,
       " distinct_pmids=", citedPmids.len,
       " distinct_projects=", distinctProjects.len,
       " cited_pmids_in_pubmed=", citedInPubmed.len
  g.close()

when isMainModule:
  main()
