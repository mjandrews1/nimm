// formal/lock_semantics.dfy
//
// Formal model of the resource-lock set (globals.nim heldLocks + acquireLock /
// releaseLock / releaseAllLocks): acquire is idempotent (set insert), release
// removes exactly the named lock, and bare LOCK empties the set.
//
// Verify with:  dafny verify formal/lock_semantics.dfy

module LockSemantics {

  type LockName = string
  type Locks = set<LockName>

  function Acquire(locks: Locks, name: LockName): Locks { locks + {name} }
  function Release(locks: Locks, name: LockName): Locks { locks - {name} }
  function ReleaseAll(locks: Locks): Locks { {} }

  // Acquiring a lock twice is the same as once (idempotent).
  lemma AcquireIdempotent(locks: Locks, name: LockName)
    ensures Acquire(Acquire(locks, name), name) == Acquire(locks, name)
  {
  }

  // Release removes exactly the named lock.
  lemma ReleaseRemoves(locks: Locks, name: LockName)
    ensures name !in Release(locks, name)
  {
  }

  // Bare LOCK empties the set.
  lemma ReleaseAllEmpty(locks: Locks)
    ensures ReleaseAll(locks) == {}
  {
  }

  // Acquire then release is a no-op (when the lock was not already held).
  lemma AcquireReleaseNoop(locks: Locks, name: LockName)
    requires name !in locks
    ensures Release(Acquire(locks, name), name) == locks
  {
  }

  // Releasing an unheld lock is a no-op.
  lemma ReleaseAbsentNoop(locks: Locks, name: LockName)
    requires name !in locks
    ensures Release(locks, name) == locks
  {
  }

}
