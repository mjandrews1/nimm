# fst_load_nim.nim — NimM XML processor using string operations
# Parses MeSH XML without parsexml module
# Usage: nim c -d:release --path:. -o:bin/fst_load_nim future_search_tool/src/fst_load_nim.nim
#        ./bin/fst_load_nim <db_path> <desc_xml> [qual_xml]

import std/[os, strutils, times]
import storage/lmdb_store

const BATCH_SIZE = 5000

proc extractBetween(s: string, startTag: string, endTag: string): string =
  ## Extract text between two tags (handles attributes in start tag)
  let startIdx = s.find(startTag)
  if startIdx < 0: return ""
  # Find the closing > of the start tag
  let closeIdx = s.find(">", startIdx)
  if closeIdx < 0: return ""
  let contentStart = closeIdx + 1
  let endIdx = s.find(endTag, contentStart)
  if endIdx < 0: return ""
  return s[contentStart ..< endIdx].strip()

proc extractAll(s: string, startTag: string, endTag: string): seq[string] =
  ## Extract all occurrences of text between two tags
  result = @[]
  var pos = 0
  while pos < s.len:
    let startIdx = s.find(startTag, pos)
    if startIdx < 0: break
    # Find the closing > of the start tag
    let closeIdx = s.find(">", startIdx)
    if closeIdx < 0: break
    let contentStart = closeIdx + 1
    let endIdx = s.find(endTag, contentStart)
    if endIdx < 0: break
    result.add(s[contentStart ..< endIdx].strip())
    pos = endIdx + endTag.len

proc loadMeshDescriptors(store: var LmdbStore, path: string, maxRecords: int = 0): int =
  echo "Loading MeSH descriptors from ", path
  let startTime = cpuTime()
  
  # Read entire file
  let content = readFile(path)
  echo "  File size: ", content.len, " bytes"
  
  var count = 0
  store.beginWriteBatch()
  
  # Find all DescriptorRecord blocks
  var pos = 0
  while pos < content.len:
    let recordStart = content.find("<DescriptorRecord", pos)
    if recordStart < 0: break
    
    let recordEnd = content.find("</DescriptorRecord>", recordStart)
    if recordEnd < 0: break
    
    let record = content[recordStart ..< recordEnd + "</DescriptorRecord>".len]
    pos = recordEnd + "</DescriptorRecord>".len
    
    # Extract fields
    let ui = extractBetween(record, "<DescriptorUI>", "</DescriptorUI>")
    let name = extractBetween(record, "<String>", "</String>")
    let scope = extractBetween(record, "<ScopeNote>", "</ScopeNote>")
    
    if ui.len == 0 or name.len == 0:
      continue
    
    # Write to LMDB
    store.putBatch("^MESH", @[ui, "name"], name)
    if scope.len > 0:
      store.putBatch("^MESH", @[ui, "scopeNote"], scope)
    
    # Extract tree numbers
    let trees = extractAll(record, "<TreeNumber>", "</TreeNumber>")
    for tree in trees:
      store.putBatch("^MESH", @[ui, "treeNumber", tree], "1")
    
    # Extract qualifiers
    let quals = extractAll(record, "<QualifierUI>", "</QualifierUI>")
    for qual in quals:
      store.putBatch("^MESH", @[ui, "qualifier", qual], "1")
    
    count += 1
    if count mod 1000 == 0:
      let elapsed = cpuTime() - startTime
      echo "  Loaded ", count, " descriptors (", formatFloat(elapsed, ffDecimal, 1), "s)"
    
    if maxRecords > 0 and count >= maxRecords:
      break
  
  store.endWriteBatch()
  
  let elapsed = cpuTime() - startTime
  echo "  Loaded ", count, " MeSH descriptors in ", formatFloat(elapsed, ffDecimal, 1), "s"
  return count

proc loadMeshQualifiers(store: var LmdbStore, path: string): int =
  echo "Loading MeSH qualifiers from ", path
  let content = readFile(path)
  
  var count = 0
  store.beginWriteBatch()
  
  var pos = 0
  while pos < content.len:
    let recordStart = content.find("<QualifierRecord>", pos)
    if recordStart < 0: break
    
    let recordEnd = content.find("</QualifierRecord>", recordStart)
    if recordEnd < 0: break
    
    let record = content[recordStart ..< recordEnd + "</QualifierRecord>".len]
    pos = recordEnd + "</QualifierRecord>".len
    
    let ui = extractBetween(record, "<QualifierUI>", "</QualifierUI>")
    let name = extractBetween(record, "<String>", "</String>")
    let abbrev = extractBetween(record, "<Abbreviation>", "</Abbreviation>")
    
    if ui.len == 0 or name.len == 0:
      continue
    
    store.putBatch("^QUAL", @[ui, "name"], name)
    if abbrev.len > 0:
      store.putBatch("^QUAL", @[ui, "abbreviation"], abbrev)
    
    count += 1
  
  store.endWriteBatch()
  echo "  Loaded ", count, " MeSH qualifiers"
  return count

proc main() =
  let params = commandLineParams()
  if params.len < 2:
    echo "Usage: fst_load_nim <db_path> <desc_xml> [qual_xml]"
    quit(1)
  
  let dbPath = params[0]
  let descPath = params[1]
  
  var store: LmdbStore
  store.init(dbPath)
  
  store.put("^FST", @["status"], "loading")
  
  var total = 0
  total += store.loadMeshDescriptors(descPath)
  
  if params.len > 2:
    total += store.loadMeshQualifiers(params[2])
  
  store.put("^FST", @["status"], "loaded")
  store.put("^FST", @["records"], $total)
  
  store.close()
  
  echo()
  echo "Total records loaded: ", total
  echo "Done!"

main()
