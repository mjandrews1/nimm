# test_lmdb.nim — Test LMDB storage backend

import ../storage/lmdb_store
import ../storage/key_encoding
import os

proc main() =
  let dbPath = "/tmp/nimm_test.lmdb"
  
  # Clean up
  if dirExists(dbPath):
    removeDir(dbPath)
  
  echo "Testing LMDB storage..."
  
  var store: LmdbStore
  store.init(dbPath)
  
  # Test basic put/get
  store.put("GLOBAL", @["sub1"], "value1")
  let val1 = store.get("GLOBAL", @["sub1"])
  assert val1 == "value1", "Expected 'value1', got '" & val1 & "'"
  echo "✓ Basic put/get"
  
  # Test multiple subscripts
  store.put("GLOBAL", @["sub1", "sub2"], "value2")
  let val2 = store.get("GLOBAL", @["sub1", "sub2"])
  assert val2 == "value2", "Expected 'value2', got '" & val2 & "'"
  echo "✓ Multiple subscripts"
  
  # Test overwrite
  store.put("GLOBAL", @["sub1"], "new_value")
  let val3 = store.get("GLOBAL", @["sub1"])
  assert val3 == "new_value", "Expected 'new_value', got '" & val3 & "'"
  echo "✓ Overwrite"
  
  # Test delete
  store.delete("GLOBAL", @["sub1"])
  let val4 = store.get("GLOBAL", @["sub1"])
  assert val4.len == 0, "Expected empty, got '" & val4 & "'"
  echo "✓ Delete"
  
  # Test key encoding
  let key = encodeKey("GLOBAL", @["sub1", "sub2"])
  let (global, subs) = decodeKey(key)
  assert global == "GLOBAL", "Expected 'GLOBAL', got '" & global & "'"
  assert subs.len == 2, "Expected 2 subs, got " & $subs.len
  assert subs[0] == "sub1", "Expected 'sub1', got '" & subs[0] & "'"
  assert subs[1] == "sub2", "Expected 'sub2', got '" & subs[1] & "'"
  echo "✓ Key encoding/decoding"
  
  # Test M-collation
  assert mCollationCmp("", "a") < 0, "Empty should sort before strings"
  assert mCollationCmp("1", "a") < 0, "Numbers should sort before strings"
  assert mCollationCmp("1", "2") < 0, "Numeric comparison"
  assert mCollationCmp("a", "b") < 0, "String comparison"
  echo "✓ M-collation"
  
  store.close()
  
  # Clean up
  if fileExists(dbPath):
    removeFile(dbPath)
  if fileExists(dbPath & "-lock"):
    removeFile(dbPath & "-lock")
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
