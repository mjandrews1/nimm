# test_new_structures.nim — Test new data structures

import ../data_structures
import tables

proc main() =
  echo "Testing new data structures..."
  
  # Test NiHeap
  var heap = newHeap()
  heap.push("c")
  heap.push("a")
  heap.push("b")
  assert heap.peek() == "a"
  assert heap.pop() == "a"
  assert heap.pop() == "b"
  assert heap.len == 1
  echo "✓ NiHeap"
  
  # Test NiRing
  var ring = newRing(3)
  ring.push("a")
  ring.push("b")
  ring.push("c")
  assert ring.isFull
  ring.push("d")  # overwrites "a"
  assert ring.len == 3
  assert ring.pop() == "b"
  echo "✓ NiRing"
  
  # Test NiLRU
  var lru = newLRU(2)
  lru.put("a", "1")
  lru.put("b", "2")
  assert lru.has("a")
  lru.put("c", "3")  # evicts "a"
  assert not lru.has("a")
  assert lru.has("b")
  assert lru.has("c")
  echo "✓ NiLRU"
  
  # Test NiBitSet
  var bs = newBitSet(128)
  bs.set(0)
  bs.set(63)
  bs.set(64)
  assert bs.test(0)
  assert bs.test(63)
  assert bs.test(64)
  assert not bs.test(1)
  assert bs.count == 3
  echo "✓ NiBitSet"
  
  # Test NiTrie
  var trie = newTrie()
  trie.insert("hello", "world")
  trie.insert("help", "me")
  trie.insert("hero", "zero")
  assert trie.search("hello")
  assert trie.search("help")
  assert not trie.search("he")
  assert trie.startsWith("he")
  assert trie.get("hello") == "world"
  let ac = trie.autocomplete("hel")
  assert ac.len == 2  # hello, help
  echo "✓ NiTrie"
  
  # Test NiGraph
  var g = newGraph(true)
  g.addEdge("a", "b", 1.0)
  g.addEdge("b", "c", 2.0)
  g.addEdge("a", "c", 3.0)
  assert g.nodeCount == 3
  assert g.edgeCount == 3
  assert g.hasEdge("a", "b")
  assert not g.hasEdge("b", "a")  # directed
  let dfsResult = g.dfs("a")
  assert dfsResult.len == 3
  let bfsResult = g.bfs("a")
  assert bfsResult.len == 3
  echo "✓ NiGraph"
  
  # Test NiMatrix
  var m = newMatrix(2, 3)
  m.set(0, 0, 1.0)
  m.set(0, 1, 2.0)
  m.set(0, 2, 3.0)
  m.set(1, 0, 4.0)
  m.set(1, 1, 5.0)
  m.set(1, 2, 6.0)
  assert m.get(0, 0) == 1.0
  assert m.get(1, 2) == 6.0
  let t = m.transpose()
  assert t.rows == 3
  assert t.cols == 2
  assert t.get(0, 0) == 1.0
  assert t.get(2, 1) == 6.0
  echo "✓ NiMatrix"
  
  # Test NiBloom
  var bloom = newBloom(1000, 3)
  bloom.add("hello")
  bloom.add("world")
  assert bloom.contains("hello")
  assert bloom.contains("world")
  assert not bloom.contains("foo")  # might be false positive, but unlikely
  echo "✓ NiBloom"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
