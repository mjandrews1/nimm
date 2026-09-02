# build_serial_link.nim — build the CATLINE→SERLINE "serial" link via ISSN join (#465).
#
# A journal (^CATLINE) and its serial holdings (^SERLINE) share the same ISSN
# (MARC 022 $a). Build an in-memory ISSN→SERLINE-NLMID index, then walk CatLine
# and write ^LINK("CATLINE", nlmID, "SERLINE", serialID) = "serial" for each
# matching ISSN. Reports coverage so the ISSN-overlap question is answered in
# the same pass.
#
# Usage: nim c -d:release --path:. -o:bin/build_serial_link \
#          future_search_tool/src/build_serial_link.nim
#        ./bin/build_serial_link <db>

import os
import tables
import ../../globals

proc main() =
  let p = commandLineParams()
  if p.len < 1:
    echo "usage: build_serial_link <db>"
    quit(1)
  var g = newGlobals(p[0])

  # Pass 1: ISSN -> SERLINE NLMID index.
  var issnToSerial = initTable[string, string]()
  var serlineWithIssn = 0
  var serialId = g.order("^SERLINE", @[], forward = true)
  while serialId.len > 0:
    let issn = g.get("^SERLINE", @[serialId, "issn"])
    if issn.len > 0:
      inc serlineWithIssn
      if issn notin issnToSerial:
        issnToSerial[issn] = serialId
    serialId = g.order("^SERLINE", @[serialId], forward = true)

  # Pass 2: walk CatLine, link by ISSN.
  var catlineTotal = 0
  var catlineWithIssn = 0
  var linked = 0
  g.beginWriteBatch()
  var nlmId = g.order("^CATLINE", @[], forward = true)
  while nlmId.len > 0:
    inc catlineTotal
    let issn = g.get("^CATLINE", @[nlmId, "issn"])
    if issn.len > 0:
      inc catlineWithIssn
      if issn in issnToSerial:
        let serialId = issnToSerial[issn]
        g.set("^LINK", @["CATLINE", nlmId, "SERLINE", serialId], "serial")
        inc linked
    nlmId = g.order("^CATLINE", @[nlmId], forward = true)
  g.endWriteBatch()
  g.close()

  echo "serial-link DONE serline_with_issn=", serlineWithIssn,
       " catline_total=", catlineTotal,
       " catline_with_issn=", catlineWithIssn,
       " linked=", linked

main()
