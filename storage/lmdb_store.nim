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
    lockDbi: Dbi        # Lock table DBI for cross-process LOCK (#307)
    path: string
    mapSize: int64
    readTxn: ptr Txn    # Cached read transaction for batch reads
    readTxnActive*: bool # True when cached read transaction is active
    writeTxn: ptr Txn   # Cached write transaction for batch writes
    writeTxnActive*: bool # True when cached write transaction is active

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
  
  # Open LMDB environment — accept both file and directory paths
  # Python lmdb creates directories by default; NimM previously used NOSUBDIR
  var flags: cuint = NOTLS
  if not dirExists(path):
    flags = flags or NOSUBDIR
  rc = envOpen(store.env, path, flags, 0o664)
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
  
  # Lock table uses main DBI with encoded key format
  store.lockDbi = store.dbi
  
  rc = txnCommit(txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_commit failed")

proc close*(store: var LmdbStore) =
  ## Close LMDB store
  if store.env != nil:
    if store.readTxnActive:
      abort(store.readTxn)
      store.readTxnActive = false
    dbiClose(store.env, store.dbi)
    dbiClose(store.env, store.lockDbi)
    envClose(store.env)
    store.env = nil

# --- Cross-process LOCK operations (#307) ---

proc lockKey(name: string): string =
  ## Lock table key — uses a null-byte prefix that cannot collide with
  ## global keys (which always start with '^').
  return "\x00LOCK:" & name

proc acquireLock*(store: var LmdbStore, name: string, pid: int): bool =
  ## Acquire a lock on resource name. Returns true if acquired, false if held by other.
  ## Writes PID to lock table. If already held by another PID, returns false.
  let key = lockKey(name)
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS: return false
  
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](key.len)
  mdbKey.mvData = cast[pointer](unsafeAddr key[0])
  
  # Check if already held
  var mdbVal: Val
  rc = get(txn, store.lockDbi, addr mdbKey, addr mdbVal)
  if rc == SUCCESS:
    # Lock exists — check if held by this PID
    let holder = newString(mdbVal.mvSize)
    copyMem(addr holder[0], mdbVal.mvData, mdbVal.mvSize)
    if holder != $pid:
      abort(txn)
      return false
    # Already held by this PID — reacquire (idempotent)
    abort(txn)
    return true
  
  # Not held — acquire
  let pidStr = $pid
  var newVal: Val
  newVal.mvSize = cast[uint](pidStr.len)
  newVal.mvData = cast[pointer](unsafeAddr pidStr[0])
  
  rc = put(txn, store.lockDbi, addr mdbKey, addr newVal, 0)
  if rc != SUCCESS:
    abort(txn)
    return false
  
  rc = txnCommit(txn)
  return rc == SUCCESS

proc releaseLock*(store: var LmdbStore, name: string, pid: int): bool =
  ## Release a lock on resource name. Returns true if released.
  let key = lockKey(name)
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS: return false
  
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](key.len)
  mdbKey.mvData = cast[pointer](unsafeAddr key[0])
  
  # Check if held by this PID
  var mdbVal: Val
  rc = get(txn, store.lockDbi, addr mdbKey, addr mdbVal)
  if rc != SUCCESS:
    abort(txn)
    return false  # Not held
  
  let holder = newString(mdbVal.mvSize)
  copyMem(addr holder[0], mdbVal.mvData, mdbVal.mvSize)
  if holder != $pid:
    abort(txn)
    return false  # Held by other PID
  
  # Release
  rc = del(txn, store.lockDbi, addr mdbKey, nil)
  if rc != SUCCESS:
    abort(txn)
    return false
  
  rc = txnCommit(txn)
  return rc == SUCCESS

proc releaseAllLocks*(store: var LmdbStore, pid: int): int =
  ## Release all locks held by this PID. Returns count of released locks.
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS: return 0
  
  var cursor: LMDBCursor
  rc = cursorOpen(txn, store.lockDbi, addr cursor)
  if rc != SUCCESS:
    abort(txn)
    return 0
  
  var mdbKey: Val
  var mdbVal: Val
  var released = 0
  var toDelete: seq[string] = @[]
  
  # Collect all locks held by this PID
  rc = cursorGet(cursor, addr mdbKey, addr mdbVal, FIRST)
  while rc == SUCCESS:
    let key = newString(mdbKey.mvSize)
    copyMem(addr key[0], mdbKey.mvData, mdbKey.mvSize)
    # Only process lock keys
    if key.startsWith("\x00LOCK\x00"):
      let holder = newString(mdbVal.mvSize)
      copyMem(addr holder[0], mdbVal.mvData, mdbVal.mvSize)
      if holder == $pid:
        toDelete.add(key)
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, NEXT)
  
  cursorClose(cursor)
  
  # Delete collected locks
  for key in toDelete:
    var delKey: Val
    delKey.mvSize = cast[uint](key.len)
    delKey.mvData = cast[pointer](unsafeAddr key[0])
    rc = del(txn, store.lockDbi, addr delKey, nil)
    if rc == SUCCESS:
      inc released
  
  rc = txnCommit(txn)
  if rc != SUCCESS: return 0
  return released

proc lockHeld*(store: var LmdbStore, name: string, pid: int): bool =
  ## Check if a lock is held by this PID.
  let key = lockKey(name)
  var readTxn: ptr Txn
  var rc = txnBegin(store.env, nil, RDONLY, addr readTxn)
  if rc != SUCCESS: return false
  
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](key.len)
  mdbKey.mvData = cast[pointer](unsafeAddr key[0])
  
  var mdbVal: Val
  rc = get(readTxn, store.lockDbi, addr mdbKey, addr mdbVal)
  if rc != SUCCESS:
    abort(readTxn)
    return false
  
  let holder = newString(mdbVal.mvSize)
  copyMem(addr holder[0], mdbVal.mvData, mdbVal.mvSize)
  abort(readTxn)
  return holder == $pid

proc beginReadBatch*(store: var LmdbStore) =
  ## Begin a read batch — cache the read transaction for multiple reads.
  ## Call endReadBatch() when done. Nested calls are allowed (ref-counted).
  if not store.readTxnActive:
    var rc = txnBegin(store.env, nil, RDONLY, addr store.readTxn)
    if rc == SUCCESS:
      store.readTxnActive = true

proc endReadBatch*(store: var LmdbStore) =
  ## End a read batch — abort the cached read transaction.
  if store.readTxnActive:
    abort(store.readTxn)
    store.readTxnActive = false

proc getReadTxn(store: var LmdbStore): ptr Txn =
  ## Get a read transaction — use cached if in batch, else create new.
  if store.readTxnActive:
    return store.readTxn
  # Create a new read transaction for single reads
  var readTxn: ptr Txn
  var rc = txnBegin(store.env, nil, RDONLY, addr readTxn)
  if rc != SUCCESS: return nil
  return readTxn

proc abortIfNotBatch(store: var LmdbStore, txn: ptr Txn) =
  ## Abort a read transaction only if it's not the cached batch transaction.
  if not store.readTxnActive or txn != store.readTxn:
    abort(txn)

proc get*(store: var LmdbStore, global: string, subs: seq[string] = @[]): string =
  ## Get value for global[sub1,sub2,...]
  ## Uses cached read transaction if in a batch, else creates a new one.
  let key = encodeKey(global, subs)
  
  let readTxn = store.getReadTxn()
  if readTxn == nil: return ""
  
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](key.len)
  mdbKey.mvData = cast[pointer](unsafeAddr key[0])
  
  var mdbVal: Val
  let rc = get(readTxn, store.dbi, addr mdbKey, addr mdbVal)
  
  if rc != SUCCESS:
    store.abortIfNotBatch(readTxn)
    return ""
  
  if mdbVal.mvSize > 0:
    result = newString(mdbVal.mvSize)
    copyMem(addr result[0], mdbVal.mvData, mdbVal.mvSize)
  else:
    result = ""
  store.abortIfNotBatch(readTxn)

proc put*(store: var LmdbStore, global: string, subs: seq[string], value: string) =
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

# --- Batch write operations ---

proc beginWriteBatch*(store: var LmdbStore) =
  ## Begin a batch write transaction. All subsequent putBatch calls will use this transaction.
  ## Must be followed by endWriteBatch to commit.
  if store.writeTxnActive:
    raise newException(IOError, "LMDB write batch already active")
  
  var rc = txnBegin(store.env, nil, 0, addr store.writeTxn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB beginWriteBatch txn_begin failed")
  store.writeTxnActive = true

proc putBatch*(store: var LmdbStore, global: string, subs: seq[string], value: string) =
  ## Put a key-value pair within a batch write transaction.
  ## Must be called between beginWriteBatch and endWriteBatch.
  if not store.writeTxnActive:
    raise newException(IOError, "LMDB putBatch: no active write batch")
  
  let key = encodeKey(global, subs)
  
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](key.len)
  mdbKey.mvData = cast[pointer](unsafeAddr key[0])
  
  var mdbVal: Val
  mdbVal.mvSize = cast[uint](value.len)
  if value.len > 0:
    mdbVal.mvData = cast[pointer](unsafeAddr value[0])
  
  let rc = put(store.writeTxn, store.dbi, addr mdbKey, addr mdbVal, 0)
  if rc != SUCCESS:
    echo "DEBUG putBatch failed: key=", key.len, " val=", value.len, " rc=", rc
    echo "DEBUG key bytes: ", cast[seq[byte]](key)
    abort(store.writeTxn)
    store.writeTxnActive = false
    raise newException(IOError, "LMDB putBatch put failed: " & $rc)

proc endWriteBatch*(store: var LmdbStore) =
  ## Commit the batch write transaction.
  if not store.writeTxnActive:
    raise newException(IOError, "LMDB endWriteBatch: no active write batch")
  
  let rc = txnCommit(store.writeTxn)
  store.writeTxnActive = false
  if rc != SUCCESS:
    raise newException(IOError, "LMDB endWriteBatch txn_commit failed")

proc abortWriteBatch*(store: var LmdbStore) =
  ## Abort the batch write transaction without committing.
  if store.writeTxnActive:
    abort(store.writeTxn)
    store.writeTxnActive = false

proc delete*(store: var LmdbStore, global: string, subs: seq[string] = @[]) =
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
    if rc != SUCCESS and rc != NOTFOUND:
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

proc batchPut*(store: var LmdbStore, items: seq[(string, seq[string], string)]) =
  ## Batch put multiple key-value pairs in a single transaction
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
  try:
    for (global, subs, value) in items:
      let key = encodeKey(global, subs)
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
        raise newException(IOError, "LMDB batch put failed")
    
    rc = txnCommit(txn)
    if rc != SUCCESS:
      raise newException(IOError, "LMDB txn_commit failed")
  except:
    abort(txn)
    raise

proc batchDelete*(store: var LmdbStore, keys: seq[(string, seq[string])]) =
  ## Batch delete multiple keys in a single transaction
  var txn: ptr Txn
  var rc = txnBegin(store.env, nil, 0, addr txn)
  if rc != SUCCESS:
    raise newException(IOError, "LMDB txn_begin failed")
  
  try:
    for (global, subs) in keys:
      let key = encodeKey(global, subs)
      var mdbKey: Val
      mdbKey.mvSize = cast[uint](key.len)
      mdbKey.mvData = cast[pointer](unsafeAddr key[0])
      
      rc = del(txn, store.dbi, addr mdbKey, nil)
      if rc != SUCCESS and rc != NOTFOUND:
        abort(txn)
        raise newException(IOError, "LMDB batch delete failed")
    
    rc = txnCommit(txn)
    if rc != SUCCESS:
      raise newException(IOError, "LMDB txn_commit failed")
  except:
    abort(txn)
    raise

proc order*(store: var LmdbStore, global: string, subs: seq[string] = @[], forward: bool = true): string =
  ## Get next/previous key in LMDB (for $ORDER)
  ## Uses cached read transaction if in a batch, else creates a new one.
  let prefix = encodeKey(global, subs)
  
  var parentPrefix = global
  for i in 0..<subs.len:
    parentPrefix.add('\0')
    parentPrefix.add(subs[i])
  parentPrefix.add('\0')
  
  let readTxn = store.getReadTxn()
  if readTxn == nil: return ""
  
  var cursor: LMDBCursor
  var rc = cursorOpen(readTxn, store.dbi, addr cursor)
  if rc != SUCCESS:
    store.abortIfNotBatch(readTxn)
    return ""
  
  # Position cursor at prefix
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](prefix.len)
  mdbKey.mvData = cast[pointer](unsafeAddr prefix[0])
  
  var mdbVal: Val
  rc = cursorGet(cursor, addr mdbKey, addr mdbVal, SET_RANGE)
  
  if rc != SUCCESS:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return ""
  
  # Move to next/previous
  if forward:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, NEXT)
  else:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, PREV)
  
  if rc != SUCCESS:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return ""
  
  # Decode the key from mdbKey
  let key = newString(mdbKey.mvSize)
  copyMem(addr key[0], mdbKey.mvData, mdbKey.mvSize)
  let decoded = decodeKey(key)
  
  # Verify the key has the same global name
  if decoded[0] != global:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return ""
  
  # Verify the key is at the same level (same number of subscripts)
  if decoded[1].len != subs.len:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return ""
  
  # Verify all subscripts except the last match (same parent)
  for i in 0..<subs.len - 1:
    if decoded[1][i] != subs[i]:
      cursorClose(cursor)
      store.abortIfNotBatch(readTxn)
      return ""
  
  # Return the last subscript (the next one at this level)
  cursorClose(cursor)
  store.abortIfNotBatch(readTxn)
  return decoded[1][^1]

proc query*(store: var LmdbStore, global: string, subs: seq[string] = @[], forward: bool = true): (seq[string]) =
  ## Get next/previous node in LMDB (for $QUERY)
  ## Uses cached read transaction if in a batch, else creates a new one.
  let prefix = encodeKey(global, subs)
  
  let readTxn = store.getReadTxn()
  if readTxn == nil: return @[]
  
  var cursor: LMDBCursor
  var rc = cursorOpen(readTxn, store.dbi, addr cursor)
  if rc != SUCCESS:
    store.abortIfNotBatch(readTxn)
    return @[]
  
  # Position cursor at prefix
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](prefix.len)
  mdbKey.mvData = cast[pointer](unsafeAddr prefix[0])
  
  var mdbVal: Val
  rc = cursorGet(cursor, addr mdbKey, addr mdbVal, SET_RANGE)
  
  if rc != SUCCESS:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return @[]
  
  # Move to next/previous
  if forward:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, NEXT)
  else:
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, PREV)
  
  if rc != SUCCESS:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return @[]
  
  # Decode the key from mdbKey
  let key = newString(mdbKey.mvSize)
  copyMem(addr key[0], mdbKey.mvData, mdbKey.mvSize)
  let decoded = decodeKey(key)
  
  # Verify the key has the same global name
  if decoded[0] != global:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return @[]
  
  # Return all subscripts
  cursorClose(cursor)
  store.abortIfNotBatch(readTxn)
  return decoded[1]

proc listSubs*(store: var LmdbStore, global: string, subs: seq[string] = @[]): seq[seq[string]] =
  ## List all subscripts under a given global[sub1,sub2,...]
  ## Uses cached read transaction if in a batch, else creates a new one.
  let prefix = encodeKey(global, subs)
  
  let readTxn = store.getReadTxn()
  if readTxn == nil: return @[]
  
  var cursor: LMDBCursor
  var rc = cursorOpen(readTxn, store.dbi, addr cursor)
  if rc != SUCCESS:
    store.abortIfNotBatch(readTxn)
    return @[]
  
  # Position cursor at prefix
  var mdbKey: Val
  mdbKey.mvSize = cast[uint](prefix.len)
  mdbKey.mvData = cast[pointer](unsafeAddr prefix[0])
  
  var mdbVal: Val
  rc = cursorGet(cursor, addr mdbKey, addr mdbVal, SET_RANGE)
  
  if rc != SUCCESS:
    cursorClose(cursor)
    store.abortIfNotBatch(readTxn)
    return @[]
  
  var result: seq[seq[string]] = @[]
  
  # Iterate through all keys with the same prefix
  while rc == SUCCESS:
    let key = newString(mdbKey.mvSize)
    copyMem(addr key[0], mdbKey.mvData, mdbKey.mvSize)
    let decoded = decodeKey(key)
    
    if decoded[0] != global:
      break
    
    if decoded[1].len > subs.len:
      var match = true
      for i in 0..<subs.len:
        if decoded[1][i] != subs[i]:
          match = false
          break
      if match:
        result.add(decoded[1])
    
    rc = cursorGet(cursor, addr mdbKey, addr mdbVal, NEXT)
  
  cursorClose(cursor)
  store.abortIfNotBatch(readTxn)
  return result

proc listKeys*(store: var LmdbStore, prefix: string = ""): seq[string] =
  ## List all keys with optional prefix
  ## Uses cached read transaction if in a batch, else creates a new one.
  let readTxn = store.getReadTxn()
  if readTxn == nil: return @[]
  
  var cursor: LMDBCursor
  var rc = cursorOpen(readTxn, store.dbi, addr cursor)
  if rc != SUCCESS:
    store.abortIfNotBatch(readTxn)
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
  store.abortIfNotBatch(readTxn)
