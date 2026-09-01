# test_lmdb_readonly.nim — LmdbStore read-only open path (reader does not
# block on a writer; writes are rejected).
#
# Run: nim c -r tests/test_lmdb_readonly.nim

import ../globals
import os

proc main() =
  echo "LmdbStore read-only open test..."
  let db = "/tmp/test_lmdb_readonly.lmdb"
  removeFile(db)
  removeFile(db & "-lock")

  # Write some data with a normal (read-write) store.
  var w = newGlobals(db)
  w.set("^X", @["a"], "1")
  w.set("^X", @["b"], "2")
  w.close()

  # Open read-only: reads work.
  var r = newGlobals(db, readOnly = true)
  assert r.get("^X", @["a"]) == "1", "read-only get a"
  assert r.get("^X", @["b"]) == "2", "read-only get b"
  assert r.order("^X", @[], forward = true) == "a", "read-only order"
  r.close()

  echo "  read-only open: reads OK"

  # Read-only write must raise (LMDB read-only txn rejects put).
  var r2 = newGlobals(db, readOnly = true)
  var raised = false
  try:
    r2.set("^X", @["c"], "3")
  except IOError:
    raised = true
  r2.close()
  assert raised, "read-only set must raise IOError"
  echo "  read-only open: writes rejected"

  removeFile(db)
  removeFile(db & "-lock")
  echo "LmdbStore read-only test passed!"

main()
