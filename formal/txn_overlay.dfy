// formal/txn_overlay.dfy
//
// Formal model of the transaction overlay (globals.nim txnSubs): writes add
// or override a node, kills remove a node and all its descendants, and levels
// apply outer-to-inner so the innermost op wins. This is the read-your-own-
// writes invariant behind #396.
//
// Verify with:  dafny verify formal/key_encoding.dfy formal/txn_overlay.dfy

module TxnOverlay {

  import opened KeyEncoding

  // A node is a subscript tuple; a store maps nodes to byte-string values.
  type Node = seq<Sub>
  type Value = seq<int>
  type Store = map<Node, Value>

  // Is `n` a strict prefix of `d` (n is an ancestor of d)?
  predicate IsStrictPrefix(n: Node, d: Node) {
    |n| < |d| && d[..|n|] == n
  }

  // Node-or-ancestor.
  predicate IsPrefix(n: Node, d: Node) {
    n == d || IsStrictPrefix(n, d)
  }

  // Apply a write: set node -> value.
  function ApplyWrite(base: Store, node: Node, value: Value): Store {
    base[node := value]
  }

  // Apply a kill: drop the node and every descendant (all keys with `node`
  // as a prefix).
  function ApplyKill(base: Store, node: Node): Store {
    map d | d in base && !IsPrefix(node, d) :: base[d]
  }

  // One overlay operation.
  datatype Op = Write(node: Node, value: Value) | Kill(node: Node)

  // Total lookup (defaults to [] for absent nodes), avoiding the partial
  // map-indexing operator in postconditions.
  function Lookup(m: Store, node: Node): Value {
    if node in m then m[node] else []
  }

  // Apply a sequence of operations in order (outer-to-inner levels).
  function ApplyOps(base: Store, ops: seq<Op>): Store
    decreases |ops|
  {
    if ops == [] then base
    else
      match ops[0]
      case Write(n, v) => ApplyOps(ApplyWrite(base, n, v), ops[1..])
      case Kill(n) => ApplyOps(ApplyKill(base, n), ops[1..])
  }

  // ---------------------------------------------------------------------------
  // Invariants
  // ---------------------------------------------------------------------------

  // A kill removes the node and all of its descendants.
  lemma KillRemovesDescendants(base: Store, node: Node, d: Node)
    requires IsPrefix(node, d)
    ensures d !in ApplyKill(base, node)
  {
    reveal IsPrefix;
    if node == d {
      // d == node is filtered out by !IsPrefix(node, d).
    } else {
      // IsStrictPrefix(node, d): d[..|node|] == node, so the map filter drops it.
    }
  }

  // A write makes the node visible with the written value.
  lemma WriteVisible(base: Store, node: Node, value: Value)
    ensures Lookup(ApplyWrite(base, node, value), node) == value
  {
    reveal ApplyWrite;
  }

  // A write after a kill restores the node (the inner level wins).
  lemma KillThenWriteWins(base: Store, node: Node, value: Value)
    ensures Lookup(ApplyOps(ApplyKill(base, node), [Write(node, value)]), node) == value
  {
    reveal ApplyOps;
    reveal ApplyWrite;
  }

  // A kill after a write removes it (the inner kill wins).
  lemma WriteThenKillRemoves(base: Store, node: Node, value: Value)
    ensures node !in ApplyOps(ApplyWrite(base, node, value), [Kill(node)])
  {
    reveal ApplyOps;
    KillRemovesDescendants(ApplyWrite(base, node, value), node, node);
  }

  // ---------------------------------------------------------------------------
  // Nested transaction levels ($TLEVEL) + TCOMMIT / TROLLBACK (#416)
  // ---------------------------------------------------------------------------

  // A transaction stack: a durable base store plus pending levels of ops,
  // innermost last.
  datatype Txn = Txn(base: Store, levels: seq<seq<Op>>)

  // Flatten all levels outer-to-inner.
  function Flatten(levels: seq<seq<Op>>): seq<Op>
    decreases |levels|
  {
    if |levels| == 0 then [] else levels[0] + Flatten(levels[1..])
  }

  // The store a reader sees (base + all pending ops, outer-to-inner).
  function Effective(t: Txn): Store {
    ApplyOps(t.base, Flatten(t.levels))
  }

  // $TLEVEL.
  function Tlevel(t: Txn): int { |t.levels| }

  // TSTART pushes a fresh (empty) level.
  function Tstart(t: Txn): Txn { Txn(t.base, t.levels + [[]]) }

  // A write goes into the top level.
  function Twrite(t: Txn, node: Node, value: Value): Txn
    requires |t.levels| > 0
  {
    Txn(t.base, t.levels[..|t.levels| - 1] + [t.levels[|t.levels| - 1] + [Write(node, value)]])
  }

  // A kill goes into the top level.
  function Tkill(t: Txn, node: Node): Txn
    requires |t.levels| > 0
  {
    Txn(t.base, t.levels[..|t.levels| - 1] + [t.levels[|t.levels| - 1] + [Kill(node)]])
  }

  // TCOMMIT: merge the top level into its parent; the outermost level commits
  // to the durable base store.
  function Tcommit(t: Txn): Txn
    requires |t.levels| > 0
  {
    if |t.levels| == 1 then Txn(ApplyOps(t.base, t.levels[0]), [])
    else Txn(t.base, t.levels[..|t.levels| - 2] + [t.levels[|t.levels| - 2] + t.levels[|t.levels| - 1]])
  }

  // TROLLBACK discards the top level.
  function Trollback(t: Txn): Txn
    requires |t.levels| > 0
  {
    Txn(t.base, t.levels[..|t.levels| - 1])
  }

  // Flatten of merging the last two levels equals flatten of the original.
  lemma FlattenMergeLevels(prefix: seq<seq<Op>>, a: seq<Op>, b: seq<Op>)
    ensures Flatten(prefix + [a + b]) == Flatten(prefix + [a, b])
    decreases |prefix|
  {
    reveal Flatten;
    if |prefix| == 0 {
      assert prefix == [];
      assert prefix + [a + b] == [a + b];
      assert prefix + [a, b] == [a, b];
      assert Flatten([]) == [];
      assert b + [] == b;
      assert Flatten([b]) == b + [];
      assert Flatten([a, b]) == a + (b + []);
      assert Flatten([a + b]) == (a + b) + [];
      assert a + (b + []) == a + b;
      assert (a + b) + [] == a + b;
      assert Flatten([a + b]) == Flatten([a, b]);
    } else {
      assert (prefix + [a + b])[0] == prefix[0];
      assert (prefix + [a + b])[1..] == prefix[1..] + [a + b];
      assert (prefix + [a, b])[1..] == prefix[1..] + [a, b];
      FlattenMergeLevels(prefix[1..], a, b);
    }
  }

  // $TLEVEL tracks nesting: start increments, commit/rollback decrement.
  lemma TlevelTstart(t: Txn)
    ensures Tlevel(Tstart(t)) == Tlevel(t) + 1
  {
  }

  lemma TlevelTcommit(t: Txn)
    requires |t.levels| > 0
    ensures Tlevel(Tcommit(t)) == Tlevel(t) - 1
  {
  }

  lemma TlevelTrollback(t: Txn)
    requires |t.levels| > 0
    ensures Tlevel(Trollback(t)) == Tlevel(t) - 1
  {
  }

  // Commit preserves what readers see: merging the top level into the parent
  // reorders nothing and loses nothing.
  lemma CommitPreservesEffective(t: Txn)
    requires |t.levels| > 0
    ensures Effective(Tcommit(t)) == Effective(t)
  {
    reveal Flatten;
    reveal ApplyOps;
    if |t.levels| == 1 {
      assert Flatten(t.levels) == t.levels[0];
      assert ApplyOps(ApplyOps(t.base, t.levels[0]), []) == ApplyOps(t.base, t.levels[0]);
    } else {
      FlattenMergeLevels(t.levels[..|t.levels| - 2], t.levels[|t.levels| - 2], t.levels[|t.levels| - 1]);
      assert t.levels[..|t.levels| - 2] + [t.levels[|t.levels| - 2], t.levels[|t.levels| - 1]] == t.levels;
    }
  }

  // Rollback discards the top level: the effective store is exactly the base
  // plus the remaining (outer) levels.
  lemma RollbackDiscardsTopLevel(t: Txn)
    requires |t.levels| > 0
    ensures Effective(Trollback(t)) == ApplyOps(t.base, Flatten(t.levels[..|t.levels| - 1]))
  {
  }

  // Read-your-own-writes across levels: a write at an inner level after a kill
  // at an outer level wins.
  lemma NestedKillThenWriteWins(base: Store, node: Node, value: Value)
    ensures Lookup(Effective(Txn(base, [[Kill(node)], [Write(node, value)]])), node) == value
  {
    reveal Flatten;
    reveal ApplyOps;
    assert Flatten([[Write(node, value)]]) == [Write(node, value)];
    assert Flatten([[Kill(node)], [Write(node, value)]]) == [Kill(node)] + [Write(node, value)];
    KillThenWriteWins(base, node, value);
  }

}
