// formal/network.dfy
//
// Formal model of the network connection table (network.nim): the set of open
// connection ids and the monotonic next-id counter. Proves the deterministic
// state-machine invariants — fresh ids, close-removes, count == cardinality,
// closeAll empties — that the environment-dependent socket I/O sits on top of.
//
// Verify with:  dafny verify formal/network.dfy

module Network {

  // Open connection ids (a connection in the set is open; niclose removes it,
  // so "in the table" == "open" == "isConnected").
  type Conns = set<int>

  // Every open id is strictly below the next-id counter (the counter starts at
  // 100 and only increments, so it never collides with an allocated id).
  ghost predicate IdsBelow(conns: Conns, nextId: int)
  {
    forall id | id in conns :: id < nextId
  }

  lemma IdsBelowFresh(conns: Conns, nextId: int)
    requires IdsBelow(conns, nextId)
    ensures nextId !in conns
  {
  }

  // Open a connection: allocate the fresh nextId and advance the counter.
  function Open(conns: Conns, nextId: int): Conns
    requires nextId !in conns
  {
    conns + {nextId}
  }

  lemma OpenPreservesIdsBelow(conns: Conns, nextId: int)
    requires IdsBelow(conns, nextId)
    ensures IdsBelow(Open(conns, nextId), nextId + 1)
  {
  }

  // Close removes the connection id.
  function Close(conns: Conns, id: int): Conns { conns - {id} }

  lemma CloseRemoves(conns: Conns, id: int)
    ensures id !in Close(conns, id)
  {
  }

  predicate IsConnected(conns: Conns, id: int) { id in conns }

  // Closing makes a connection not-connected.
  lemma CloseImpliesNotConnected(conns: Conns, id: int)
    ensures !IsConnected(Close(conns, id), id)
  {
    CloseRemoves(conns, id);
  }

  // Closing never increases the number of open connections.
  lemma CloseDecreases(conns: Conns, id: int)
    ensures |Close(conns, id)| <= |conns|
  {
  }

  // Connection count is the cardinality of the open-id set.
  function Count(conns: Conns): int { |conns| }

  lemma CountIsCardinality(conns: Conns)
    ensures Count(conns) == |conns|
  {
  }

  // closeAll empties the table.
  function CloseAll(conns: Conns): Conns { {} }

  lemma CloseAllEmpty(conns: Conns)
    ensures |CloseAll(conns)| == 0
    ensures CloseAll(conns) == {}
  {
  }

}
