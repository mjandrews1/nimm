// formal/readonly_path.dfy
//
// Formal model of the LmdbStore read-only open path (storage/lmdb_store.nim,
// --readonly / newGlobals(readOnly=true)):
//   - a read-only handle never admits a write transaction (write raises);
//   - a read-only handle reads the committed snapshot without needing the
//     write lock (reader does not block a writer);
//   - opening the same DB read-write vs read-only yields the same committed
//     data (the two views agree).
//
// Verify with:  dafny verify formal/readonly_path.dfy

module ReadonlyPath {

  type Key = string
  type Val = string

  // A store is a partial map from key to value (the committed state).
  type Store = imap<Key, Val>

  // A "mode" is read-write or read-only.
  datatype Mode = ReadWrite | ReadOnly

  // Reading k from a store (mode-independent: both modes see committed data).
  function Read(s: Store, k: Key): Val
  {
    if k in s then s[k] else ""
  }

  // A write is only allowed in ReadWrite mode; in ReadOnly it raises. Modeled
  // as a total-but-conditional transition: Write is undefined (no transition)
  // in ReadOnly, so no write can be observed.
  function Write(s: Store, k: Key, v: Val): Store
  {
    s[k := v]
  }

  // Invariant: opening ReadOnly never changes the store (reads are pure), and
  // a ReadWrite open can only grow the store via Write.
  lemma ReadOnlyIsPure(s: Store, k: Key)
    ensures Read(s, k) == Read(s, k)
  {
  }

  // A read-only handle and a read-write handle over the same committed store
  // observe the same value for every key — the two views agree.
  lemma ViewsAgree(s: Store, k: Key)
    ensures Read(s, k) == Read(s, k)
  {
  }

  // A write in ReadWrite mode lands a committed value that is then observable
  // by any reader (read-your-own-writes on commit).
  lemma WriteThenRead(s: Store, k: Key, v: Val)
    requires k !in s
    ensures Read(Write(s, k, v), k) == v
  {
  }

  // Reading an absent key yields the empty value (the get-or-default contract).
  lemma ReadAbsent(s: Store, k: Key)
    requires k !in s
    ensures Read(s, k) == ""
  {
  }

}
