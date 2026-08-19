# record_loader.nim — Record loader for nimm
# Loads data from various formats into LMDB

import os
import strutils
import json
import storage/lmdb_store

type
  RecordLoader* = ref object
    ## Record loader
    store*: LmdbStore

proc newRecordLoader*(store: LmdbStore): RecordLoader =
  result.store = store

proc loadCsv*(loader: RecordLoader, filePath: string, globalPrefix: string = "^DATA") =
  ## Load records from CSV file
  if not fileExists(filePath):
    raise newException(IOError, "File not found: " & filePath)
  
  let f = open(filePath)
  defer: f.close()
  
  var lineNum = 0
  var headers: seq[string] = @[]
  
  while not f.endOfFile:
    let line = f.readLine()
    inc lineNum
    
    if lineNum == 1:
      # Header line
      headers = line.split(',')
      continue
    
    let fields = line.split(',')
    let recordId = $lineNum
    
    for i, field in fields:
      if i < headers.len:
        let key = headers[i].strip()
        let subs = @[$i]
        loader.store.put(globalPrefix & recordId, subs, field.strip())

proc loadJson*(loader: RecordLoader, filePath: string, globalPrefix: string = "^DATA") =
  ## Load records from JSON file
  if not fileExists(filePath):
    raise newException(IOError, "File not found: " & filePath)
  
  let content = readFile(filePath)
  let data = parseJson(content)
  
  if data.kind == JArray:
    for i, record in data:
      let recordId = $(i + 1)
      if record.kind == JObject:
        for key, value in record:
          let subs = @[key]
          loader.store.put(globalPrefix & recordId, subs, value.getStr())
      elif record.kind == JString:
        loader.store.put(globalPrefix & recordId, @[], record.getStr())

proc loadText*(loader: RecordLoader, filePath: string, globalPrefix: string = "^TEXT") =
  ## Load text file as single record
  if not fileExists(filePath):
    raise newException(IOError, "File not found: " & filePath)
  
  let content = readFile(filePath)
  loader.store.put(globalPrefix, @[], content)

proc loadDirectory*(loader: RecordLoader, dirPath: string, globalPrefix: string = "^FILES") =
  ## Load all files in a directory
  if not dirExists(dirPath):
    raise newException(IOError, "Directory not found: " & dirPath)
  
  for entry in walkDir(dirPath):
    if entry.kind == pcFile:
      let filename = extractFilename(entry.path)
      let content = readFile(entry.path)
      loader.store.put(globalPrefix, @[filename], content)
