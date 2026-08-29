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

}
