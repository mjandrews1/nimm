// formal/data_tristate.dfy
//
// Formal model of the $DATA tri-state (globals.nim data, §8.5): 11 = value +
// descendants, 1 = value only, 10 = descendants only, 0 = neither — and its
// interaction with the transaction overlay (write → value, kill → absent).
//
// Verify with:  dafny verify formal/key_encoding.dfy formal/txn_overlay.dfy formal/data_tristate.dfy

module DataTriState {

  import opened KeyEncoding
  import opened TxnOverlay

  // The node has a value (is present in the store).
  predicate HasValue(store: Store, node: Node) {
    node in store
  }

  // The node has at least one strict descendant present.
  predicate HasDescendants(store: Store, node: Node) {
    exists d :: d in store && IsStrictPrefix(node, d)
  }

  // $DATA (§8.5): 11 = value + children, 1 = value, 10 = children, 0 = none.
  function Data(store: Store, node: Node): int {
    if HasValue(store, node) && HasDescendants(store, node) then 11
    else if HasValue(store, node) then 1
    else if HasDescendants(store, node) then 10
    else 0
  }

  // Exhaustiveness: the result is always one of the four codes.
  lemma DataExhaustive(store: Store, node: Node)
    ensures Data(store, node) == 0 || Data(store, node) == 1 ||
            Data(store, node) == 10 || Data(store, node) == 11
  {
  }

  // A write gives the node a value, so $DATA becomes 1 or 11.
  lemma WriteGivesValue(store: Store, node: Node, value: Value)
    ensures Data(ApplyWrite(store, node, value), node) == 1 ||
            Data(ApplyWrite(store, node, value), node) == 11
  {
    reveal HasValue;
    reveal ApplyWrite;
  }

  // A kill removes the node and all descendants, so $DATA becomes 0.
  lemma KillRemovesData(store: Store, node: Node)
    ensures Data(ApplyKill(store, node), node) == 0
  {
    reveal HasValue;
    reveal HasDescendants;
    reveal ApplyKill;
    // node itself is removed (IsPrefix(node, node)).
    KillRemovesDescendants(store, node, node);
  }

}
