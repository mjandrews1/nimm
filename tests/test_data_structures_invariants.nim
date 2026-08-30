# test_data_structures_invariants.nim — $NI_* invariant test
# (mirrors formal/data_structures.dfy: stack LIFO, queue FIFO, min-heap order).
#
# Run: nim c -r tests/test_data_structures_invariants.nim

import ../data_structures

proc main() =
  echo "Data-structure invariant test (mirrors formal/data_structures.dfy)..."

  # Stack: LIFO
  var st = newStack()
  st.push("a")
  st.push("b")
  assert st.pop() == "b", "stack should pop last-pushed (LIFO)"
  assert st.pop() == "a", "stack should pop first-pushed next"

  # Queue: FIFO
  var q = newQueue()
  q.enqueue("a")
  q.enqueue("b")
  assert q.dequeue() == "a", "queue should dequeue first-enqueued (FIFO)"
  assert q.dequeue() == "b"

  # Heap: min-heap — pops in non-decreasing order
  var h = newHeap()
  for v in ["c", "a", "b", "e", "d"]:
    h.push(v)
  var prev = ""
  while h.len() > 0:
    let v = h.pop()
    if prev.len > 0:
      assert prev <= v, "heap should pop in non-decreasing order"
    prev = v

  # Trie: insert/search/startsWith
  var tr = newTrie()
  tr.insert("hello")
  tr.insert("world")
  assert tr.search("hello"), "trie should find inserted key"
  assert not tr.search("hell"), "trie search requires a full key"
  assert tr.startsWith("hell"), "trie startsWith should match a prefix"

  # Graph: undirected adjacency symmetry + reachability (DFS)
  var gr = newGraph(directed = false)
  gr.addEdge("a", "b")
  gr.addEdge("b", "c")
  assert gr.hasEdge("a", "b"), "undirected edge a-b"
  assert gr.hasEdge("b", "a"), "undirected edge is symmetric"
  let reached = gr.dfs("a")
  assert "c" in reached, "a should reach c via b (dfs)"

  # LRU: eviction at capacity (least-recently-used dropped)
  var lru = newLRU(2)
  lru.put("a", "1")
  lru.put("b", "2")
  lru.put("c", "3")           # evicts "a"
  assert not lru.has("a"), "LRU should evict the least-recently-used key"
  assert lru.has("b") and lru.has("c")
  assert lru.len() == 2, "LRU size should stay at capacity"

  # BitSet: set/clear/test round-trip
  var bs = newBitSet(8)
  bs.set(3)
  assert bs.test(3), "bit set should test true after set"
  bs.clear(3)
  assert not bs.test(3), "bit clear should test false after clear"

  echo "  stack LIFO / queue FIFO / heap min-order / trie / graph / LRU / bitset all hold"
  echo "Data-structure invariant test passed!"

main()
