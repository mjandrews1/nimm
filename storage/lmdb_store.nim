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
  
  result = newString(mdbVal.mvSize)
  copyMem(addr result[0], mdbVal.mvData, mdbVal.mvSize)

proc put*(store: LmdbStore, global: string, subs: seq[string], value: string) =
  ## Set value for global[sub1,sub2,...]
  let key = encodeKey(global, subs)
  
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
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

proc delete*(store: LmdbStore, global: string, subs: seq[string] = @[]) =
  ## Delete global[sub1,sub2,...]
  let key = encodeKey(global, subs)
  
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
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

proc sync*(store: LmdbStore) =
  ## Flush data to disk
  discard envSync(store.env, 1)
