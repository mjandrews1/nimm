# test_locks.nim — resource-lock property test (mirrors formal/lock_semantics.dfy).
#
# Run: nim c -r tests/test_locks.nim

import ../globals

proc main() =
  echo "Lock semantics test (mirrors formal/lock_semantics.dfy)..."

  var g = newGlobals()

  # acquire is idempotent (set insert)
  g.acquireLock("A")
  g.acquireLock("A")
  assert g.lockHeld("A"), "acquire should be idempotent"

  # release removes exactly the named lock
  g.releaseLock("A")
  assert not g.lockHeld("A"), "release should remove the lock"

  # acquire then release (when unheld) is a no-op
  g.acquireLock("B")
  g.releaseLock("B")
  assert not g.lockHeld("B"), "acquire-then-release should leave it unheld"

  # release an unheld lock is a no-op
  g.releaseLock("E")
  assert not g.lockHeld("E"), "releasing an unheld lock should be a no-op"

  # bare LOCK empties the set
  g.acquireLock("C")
  g.acquireLock("D")
  g.releaseAllLocks()
  assert not g.lockHeld("C") and not g.lockHeld("D"), "release-all should empty the set"

  echo "  acquire/release/release-all all hold"
  echo "Lock semantics test passed!"

main()
