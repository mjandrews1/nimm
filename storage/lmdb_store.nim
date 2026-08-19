# lmdb_store.nim — LMDB storage backend for nimm
# Provides persistent storage for M/MUMPS globals

import lmdb
import os
import strutils
import key_encoding

type
  LmdbStore* = object
    env: ptr Env
    dbi: Dbi
    path: string
    mapSize: int64

proc init*(store: var LmdbStore, path: string, mapSize: int64 = 50_000_000_000) =
  ## Initialize LMDB store
  if mapSize <= 0:
    raise newException(ValueError, "LMDB mapSize must be positive: " & $mapSize)
  store.path = path
  store.mapSize = mapSize
  
  # Create directory if needed
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  
  # Create environment
  var rc = envCreate(addr store.env)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB env_create failed: " & $rc)
  
  rc = envSetMapsize(store.env, cast[uint](mapSize))
  if rc != SUCCESS:
    raise newException(IOError, "LMDB set_mapsize failed: " & $rc)
  
  rc = envOpen(store.env, path, NOSUBDIR, 0o664)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB env_open failed: " & path)
  
  # Open database
  var txn: ptr Txn
  rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
  rc = dbiOpen(txn, nil, CREATE, addr store.dbi)
  if rc != SUCCESS:
    abort(txn)
    raise newException(IOError, "LMDB dbi_open failed")
  
  rc = txnCommit(txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_commit failed")

proc close*(store: var LmdbStore) =
  ## Close LMDB store
  if store.env != nil:
    dbiClose(store.env, store.dbi)
    envClose(store.env)
    store.env = nil

proc get*(store: LmdbStore, global: string, subs: seq[string] = @[]): string =
  ## Get value for global[sub1,sub2,...]
  let key = encodeKey(global, subs)
  
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, RDONLY, addr txn)
  if rc != SUCCESS:
    return ""
  
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](key.len)
  mdbKey.mvData = cast[pointer](unsafeAddr key[0])
  
  var mdbVal: Val
  rc = get(txn, store.dbi, addr mdbKey, addr mdbVal)
  abort(txn)
  
  if rc != SUCCESS:
    return ""
  
  if mdbVal.mvSize > 0:
    result = newString(mdbVal.mvSize)
    copyMem(addr result[0], mdbVal.mvData, mdbVal.mvSize)
  else:
    result = ""

proc put*(store: LmdbStore, global: string, subs: seq[string], value: string) =
  ## Set value for global[sub1,sub2,...]
  let key = encodeKey(global, subs)
  
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
  try:
    var mdbKey: Val
    mdbKey.mvSize = cast[uint](key.len)
    mdbKey.mvData = cast[pointer](unsafeAddr key[0])
    
    var mdbVal: Val
    mdbVal.mvSize = cast[uint](value.len)
    if value.len > 0:
      mdbVal.mvData = cast[pointer](unsafeAddr value[0])
    
    rc = put(txn, store.dbi, addr mdbKey, addr mdbVal, 0)
    if rc != SUCCESS:
      abort(txn)
      raise newException(IOError, "LMDB put failed")
    
    rc = txnCommit(txn)
    if rc != SUCCESS:
      raise newException(IOError, "LMDB txn_commit failed")
  except:
    abort(txn)
    raise

proc delete*(store: LmdbStore, global: string, subs: seq[string] = @[]) =
  ## Delete global[sub1,sub2,...]
  let key = encodeKey(global, subs)
  
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
  try:
    var mdbKey: Val
    mdbKey.mvSize = cast[uint](key.len)
    mdbKey.mvData = cast[pointer](unsafeAddr key[0])
    
    rc = del(txn, store.dbi, addr mdbKey, nil)
    if rc != SUCCESS:
      abort(txn)
      raise newException(IOError, "LMDB delete failed")
    
    rc = txnCommit(txn)
    if rc != SUCCESS:
      raise newException(IOError, "LMDB txn_commit failed")
  except:
    abort(txn)
    raise

proc sync*(store: LmdbStore) =
  ## Flush data to disk
  discard envSync(store.env, 1)

proc order*(store: LmdbStore, global: string, subs: seq[string] = @[], forward: bool = true): string =
  ## Get next/previous key in LMDB (for $ORDER)
  let prefix = encodeKey(global, subs)
  
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, RDONLY, addr txn)
  if rc != SUCCESS:
    return ""
  
  var cursor: LMDBCursor
  rc = cursorOpen(txn, store.dbi, addr cursor)
  if rc != SUCCESS:
    abort(txn)
    return ""
  
  # Position cursor at prefix
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](prefix.len)
  mdbKey.mvData = cast[pointer](unsafeAddr prefix[0])
  
  var mdbVal: Val
  rc = cursorGet(cursor, addr mdbKey, addr mdbVal, SET_RANGE)
  
  if rc != SUCCESS:
    cursorClose(cursor)
    abort(txn)
    return ""
  
  # Move to next/previous
  if forward:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, NEXT)
  else:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, PREV)
  
  cursorClose(cursor)
  abort(txn)
  
  if rc != SUCCESS:
    return ""
  
  # Decode the key from mdbKey
  let key = newString(mdbKey.mvSize)
  copyMem(addr key[0], mdbKey.mvData, mdbKey.mvSize)
  let decoded = decodeKey(key)
  # Return the subscript (first subscript after global name)
  if decoded[1].len > 0:
    return decoded[1][0]
  return ""

proc listKeys*(store: LmdbStore, prefix: string = ""): seq[string] =
  ## List all keys with optional prefix
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, RDONLY, addr txn)
  if rc != SUCCESS:
    return @[]
  
  var cursor: LMDBCursor
  rc = cursorOpen(txn, store.dbi, addr cursor)
  if rc != SUCCESS:
    abort(txn)
    return @[]
  
  var mdbKey: Val
  var mdbVal: Val
  
  if prefix.len > 0:
    mdbKey.mvSize = cast[uint](prefix.len)
    mdbKey.mvData = cast[pointer](unsafeAddr prefix[0])
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, SET_RANGE)
  else:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, FIRST)
  
  while rc == SUCCESS:
    let key = newString(mdbKey.mvSize)
    copyMem(addr key[0], mdbKey.mvData, mdbKey.mvSize)
    if prefix.len > 0 and not key.startsWith(prefix):
      break
    result.add(decodeKey(key)[0])
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, NEXT)
  
  cursorClose(cursor)
  abort(txn)
