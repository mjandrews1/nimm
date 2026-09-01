# xmlload.nim — Shared XML loading for ZLOADXML
# Single implementation used by both AST engine and bytecode VM.
# Formats: mesh, qualifier (mesh-qualifier), catline (marc), pubmed
# Supports plain and .gz inputs (gunzip via pipe; no new library deps).

import strutils
import streams
import os
import osproc
import globals

const BATCH_SIZE = 1000

proc extractBetween*(s: string, startTag: string, endTag: string): string =
  ## Text between startTag's closing '>' and endTag (attribute-tolerant)
  let startIdx = s.find(startTag)
  if startIdx < 0: return ""
  let closeIdx = s.find(">", startIdx)
  if closeIdx < 0: return ""
  let contentStart = closeIdx + 1
  let endIdx = s.find(endTag, contentStart)
  if endIdx < 0: return ""
  return s[contentStart ..< endIdx].strip()

proc extractAll*(s: string, startTag: string, endTag: string): seq[string] =
  result = @[]
  var pos = 0
  while pos < s.len:
    let startIdx = s.find(startTag, pos)
    if startIdx < 0: break
    let closeIdx = s.find(">", startIdx)
    if closeIdx < 0: break
    let contentStart = closeIdx + 1
    let endIdx = s.find(endTag, contentStart)
    if endIdx < 0: break
    result.add(s[contentStart ..< endIdx].strip())
    pos = endIdx + endTag.len

proc findBlock*(s: string, marker: string, endA: string, endB: string): string =
  ## Substring from first occurrence of `marker` to whichever of endA/endB
  ## comes next (exclusive). Empty when either bound is missing.
  let i = s.find(marker)
  if i < 0: return ""
  let jA = if endA.len > 0: s.find(endA, i) else: -1
  let jB = if endB.len > 0: s.find(endB, i) else: -1
  var j = -1
  if jA >= 0 and (jB < 0 or jA < jB): j = jA
  elif jB >= 0: j = jB
  if j < 0: return ""
  return s[i ..< j]

proc elemText*(s: string, name: string): string =
  ## Content of first <name [attrs]>...</name>, attribute-tolerant.
  ## Matches '<PMID Version="1">30970</PMID>' as well as bare '<PMID>x</PMID>'.
  let open = "<" & name
  let i = s.find(open)
  if i < 0: return ""
  # must not be a longer tag sharing this prefix (e.g. <Title vs <TitleX)
  let afterOpen = s[i + open.len]
  let gt = s.find(">", i)
  if gt < 0 or afterOpen in ['-', ':'] : return ""
  let cs = gt + 1
  let close = "</" & name & ">"
  let en = s.find(close, cs)
  if en < 0: return ""
  return s[cs ..< en].strip()

proc tagAttr*(s: string, tagStart: string, attr: string): string =
  ## Attribute value inside first tag matching tagStart, e.g. UI="D001"
  let i = s.find(tagStart)
  if i < 0: return ""
  let close = s.find(">", i)
  if close < 0: return ""
  let tag = s[i .. close]
  let key = attr & "=\""
  let j = tag.find(key)
  if j < 0: return ""
  let rest = tag[j + key.len ..^ 1]
  let e = rest.find('"')
  if e < 0: return ""
  return rest[0 ..< e]

type LineSource = object
  file: File
  gzProc: Process   # non-nil when reading .gz via gunzip pipe
  stream: Stream

proc openSource(path: string): LineSource =
  result.gzProc = nil
  if path.endsWith(".gz"):
    result.gzProc = startProcess("gunzip", args = ["-c", path],
                                options = {poStdErrToStdOut, poUsePath})
    result.stream = result.gzProc.outputStream
  else:
    if not open(result.file, path, fmRead):
      raise newException(IOError, "Cannot open: " & path)
    result.stream = newFileStream(result.file)

proc closeSource(src: var LineSource) =
  if src.gzProc != nil:
    discard src.gzProc.waitForExit()
    src.gzProc.close()
  src.stream.close()

iterator sourceLines(src: var LineSource): string =
  var line = ""
  # Blocking readLine(var): false only at true EOF — reliable for
  # both FileStreams and process pipes (unlike atEnd()).
  while src.stream.readLine(line):
    yield line

proc subfieldsOf(blockText: string, code: string): seq[string] =
  ## All subfield values with given code, namespace-tolerant (marc: or bare)
  let openers = ["code=\"" & code & "\">"]
  result = @[]
  for opener in openers:
    var pos = 0
    while true:
      let st = blockText.find(opener, pos)
      if st < 0: break
      let cs = st + opener.len
      let enA = blockText.find("</subfield>", cs)
      let enB = blockText.find("</marc:subfield>", cs)
      var en = -1
      if enA >= 0 and (enB < 0 or enA < enB): en = enA
      elif enB >= 0: en = enB
      if en < 0: break
      let v = blockText[cs ..< en].strip()
      if v.len > 0: result.add(v)
      pos = en

proc extractEntryTerms(s: string): seq[string] =
  ## Entry terms (synonyms) from TermList/Term/String, attribute-tolerant on
  ## the <Term ...> opener. Used to build the ^MESHTERM search dictionary (#390).
  result = @[]
  var pos = 0
  while true:
    let st = s.find("<Term", pos)
    if st < 0: break
    let cs = s.find(">", st)
    if cs < 0: break
    let en = s.find("</Term>", cs)
    if en < 0: break
    let term = extractBetween(s[cs + 1 ..< en], "<String>", "</String>")
    if term.len > 0: result.add(term)
    pos = en + 7  # len("</Term>")

proc meshSubjectNames*(record: string): seq[string] =
  ## `$a` values of every MeSH subject heading in a record. MeSH headings are
  ## the 6xx subject-added-entry fields (600/610/611/630/650/651/655) whose
  ## second indicator is "2" (MeSH thesaurus). These names resolve to descriptor
  ## UIs for the ^LINK table (#459).
  ##
  ## Other authority-controlled fields are deliberately NOT matched: name
  ## authorities (100/110/111/700/710/711) link to a name authority file, and
  ## series/uniform titles (130/240/490/800/810/811/830) link to title authority
  ## files — neither is MeSH, and the FST schema has no such record types.
  const meshTags = ["600", "610", "611", "630", "650", "651", "655"]
  result = @[]
  var pos = 0
  while true:
    let tagPos = record.find("tag=\"", pos)
    if tagPos < 0: break
    let gt = record.find(">", tagPos)
    if gt < 0: break
    let openTag = record[tagPos .. gt]
    let endA = record.find("</datafield>", gt)
    let endB = record.find("</marc:datafield>", gt)
    var en = -1
    if endA >= 0 and (endB < 0 or endA < endB): en = endA
    elif endB >= 0: en = endB
    if en < 0: break
    var isMesh = false
    for t in meshTags:
      if "tag=\"" & t & "\"" in openTag: isMesh = true
    if isMesh and "ind2=\"2\"" in openTag:
      for n in subfieldsOf(record[tagPos ..< en], "a"):
        if n.len > 0: result.add(n)
    pos = en

proc resolveName*(g: var Globals, name: string): string =
  ## Resolve a MeSH heading name to a descriptor UI via ^MESHTERM. Returns ""
  ## when the name does not map to a single descriptor. This is the
  ## `resolve: string -> Option<DUI>` function of link_consistency.dfy.
  ##
  ## Prefers an exact descriptor-name match (^MESHTERM value "1"), then a
  ## unique synonym ("0"); anything else (zero or multiple) is ambiguous → "".
  ## MARC ind2="2" headings use the descriptor's preferred name, so the "1"
  ## match is the correct resolution even when the same string is also an
  ## entry term of another descriptor.
  let key = name.toLowerAscii
  var exact: seq[string] = @[]
  var syn: seq[string] = @[]
  var ui = g.order("^MESHTERM", @[key, ""], forward = true)
  while ui.len > 0:
    let v = g.get("^MESHTERM", @[key, ui])
    if v == "1": exact.add(ui)
    elif v == "0": syn.add(ui)
    ui = g.order("^MESHTERM", @[key, ui], forward = true)
  if exact.len == 1: return exact[0]
  if syn.len == 1: return syn[0]
  return ""

proc loadXmlData*(g: var Globals, filePath: string, globalName: string,
                  format: string): int =
  ## Stream-parse an NLM XML file into globals. Returns record count.
  ## Tracks load state in ^FST("load",<basename>) so partial loads
  ## (killed mid-run) are detectable: "in-progress" before, "complete:N" after.
  let loadKey = extractFilename(filePath)
  # Mark in-progress in its own transaction so it persists even if the
  # process is killed mid-load (the data batch below has not yet begun).
  g.set("^FST", @["load", loadKey], "in-progress")

  var src = openSource(filePath)
  defer: closeSource(src)

  var count = 0
  var batchCount = 0
  var buffer = ""
  g.beginWriteBatch()

  template flushBatch() {.dirty.} =
    inc batchCount
    if batchCount >= BATCH_SIZE:
      g.endWriteBatch()
      g.beginWriteBatch()
      batchCount = 0

  case format.toLowerAscii

  of "mesh-descriptor", "mesh":
    for line in src.sourceLines:
      buffer.add(line); buffer.add("\n")
      if "</DescriptorRecord>" in buffer:
        let ui = extractBetween(buffer, "<DescriptorUI>", "</DescriptorUI>")
        let name = extractBetween(buffer, "<String>", "</String>")
        let scope = extractBetween(buffer, "<ScopeNote>", "</ScopeNote>")
        if ui.len > 0 and name.len > 0:
          g.set(globalName, @[ui, "name"], name)
          if scope.len > 0:
            g.set(globalName, @[ui, "scopeNote"], scope)
          for tree in extractAll(buffer, "<TreeNumber>", "</TreeNumber>"):
            g.set(globalName, @[ui, "treeNumber", tree], "1")
          for qual in extractAll(buffer, "<QualifierUI>", "</QualifierUI>"):
            g.set(globalName, @[ui, "qualifier", qual], "1")
          # entry-term search dictionary (#390): name="1", synonyms="0"
          g.set("^MESHTERM", @[name.toLowerAscii, ui], "1")
          for term in extractEntryTerms(buffer):
            let t = term.toLowerAscii
            if t.len > 0 and t != name.toLowerAscii:
              g.set("^MESHTERM", @[t, ui], "0")
          inc count; flushBatch()
        buffer = ""

  of "mesh-qualifier", "qualifier":
    for line in src.sourceLines:
      buffer.add(line); buffer.add("\n")
      if "</QualifierRecord>" in buffer:
        let ui = extractBetween(buffer, "<QualifierUI>", "</QualifierUI>")
        let name = extractBetween(buffer, "<String>", "</String>")
        let abbrev = extractBetween(buffer, "<Abbreviation>", "</Abbreviation>")
        if ui.len > 0 and name.len > 0:
          g.set(globalName, @[ui, "name"], name)
          if abbrev.len > 0:
            g.set(globalName, @[ui, "abbreviation"], abbrev)
          inc count; flushBatch()
        buffer = ""

  of "catline", "marc":
    for line in src.sourceLines:
      buffer.add(line); buffer.add("\n")
      if "</record>" in buffer or "</marc:record>" in buffer:
        var nlmId = extractBetween(buffer,
          "<controlfield tag=\"001\">", "</controlfield>")
        if nlmId.len == 0:
          nlmId = extractBetween(buffer,
            "<marc:controlfield tag=\"001\">", "</marc:controlfield>")
        if nlmId.len > 0:
          # Title: concatenate 245$a then $b pieces, space-separated
          var t245 = ""
          var dfPos = 0
          while true:
            let blk = findBlock(buffer[dfPos..^1], "tag=\"245\"",
                                "</datafield>", "</marc:datafield>")
            if blk.len == 0: break
            for piece in subfieldsOf(blk, "a") & subfieldsOf(blk, "b"):
              if t245.len > 0: t245.add(" ")
              t245.add(piece)
            break  # first 245 only
          if t245.len > 0:
            g.set(globalName, @[nlmId, "title"], t245)
          # ISSN from 022$a
          let issnBlk = findBlock(buffer, "tag=\"022\"",
                                  "</datafield>", "</marc:datafield>")
          if issnBlk.len > 0:
            let vals = subfieldsOf(issnBlk, "a")
            if vals.len > 0:
              g.set(globalName, @[nlmId, "issn"], vals[0])
          # MeSH subject headings (6xx ind2="2") -> ^LINK + per-record "mesh"
          # subscript (#459). Only headings that resolve to a single descriptor
          # UI are linked; the rest are skipped (link_consistency.dfy soundness).
          let toType = globalName[1 .. ^1]  # "CATLINE" / "SERLINE"
          for heading in meshSubjectNames(buffer):
            let dui = resolveName(g, heading)
            if dui.len > 0:
              g.set(globalName, @[nlmId, "mesh", dui], "1")
              g.set("^LINK", @["MESH", dui, toType, nlmId], "subject")
          inc count; flushBatch()
        buffer = ""

  of "pubmed", "pubmed-baseline":
    for line in src.sourceLines:
      buffer.add(line); buffer.add("\n")
      if "</PubmedArticle>" in buffer:
        let pmid = elemText(buffer, "PMID")
        if pmid.len > 0:
          let title = elemText(buffer, "ArticleTitle")
          let jblk = findBlock(buffer, "<Journal>", "</Journal>", "")
          let journal = extractBetween(jblk, "<Title>", "</Title>")
          let abstract = elemText(buffer, "AbstractText")
          if title.len > 0:
            g.set(globalName, @[pmid, "title"], title)
          if journal.len > 0:
            g.set(globalName, @[pmid, "journal"], journal)
          if abstract.len > 0:
            g.set(globalName, @[pmid, "abstract"], abstract)
          # Authors: up to 10 as "Last ForeName", ';'-joined
          var authors = ""
          var apos = 0
          var taken = 0
          var moreAuthors = false
          while true:
            let aStart = buffer.find("<Author>", apos)
            if aStart < 0: break
            let aEnd = buffer.find("</Author>", aStart)
            if aEnd < 0: break
            let ablk = buffer[aStart ..< aEnd]
            let last = extractBetween(ablk, "<LastName>", "</LastName>")
            let fore = extractBetween(ablk, "<ForeName>", "</ForeName>")
            if last.len > 0:
              if taken < 10:
                if authors.len > 0: authors.add(";")
                if fore.len > 0: authors.add(last & " " & fore)
                else: authors.add(last)
              else:
                moreAuthors = true
              inc taken
            apos = aEnd
          if moreAuthors:
            authors.add(";et al.")
          if authors.len > 0:
            g.set(globalName, @[pmid, "authors"], authors)
          # MeSH headings -> field + ^LINK per FST schema
          var hpos = 0
          while true:
            let hStart = buffer.find("<MeshHeading>", hpos)
            if hStart < 0: break
            let hEnd = buffer.find("</MeshHeading>", hStart)
            if hEnd < 0: break
            let hblk = buffer[hStart ..< hEnd]
            let dui = tagAttr(hblk, "<DescriptorName", "UI")
            if dui.len > 0:
              g.set(globalName, @[pmid, "mesh", dui], "1")
              g.set("^LINK", @["MESH", dui, "PUBMED", pmid], "mesh_term")
            hpos = hEnd
          inc count; flushBatch()
        buffer = ""

  else:
    raise newException(ValueError, "Unknown XML format: " & format)

  if g.writeTxnActive():
    g.endWriteBatch()
  # Mark load complete (own transaction, after data committed)
  g.set("^FST", @["load", loadKey], "complete:" & $count)
  return count
