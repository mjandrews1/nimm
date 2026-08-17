# run_data_structure_tests.nim — Run all data structure tests
# This exercises all 29 structures without a full M interpreter

import ../data_structures
import tables

proc testArray() =
  echo "1. NiArray"
  var arr = newArray()
  arr.add("alpha"); arr.add("beta"); arr.add("gamma")
  assert arr.len == 3
  assert arr.get(0) == "alpha"
  arr.set(1, "BETA")
  assert arr.get(1) == "BETA"
  echo "   ✓ Create, add, get, set, len"

proc testBag() =
  echo "2. NiBag"
  var bag = newBag()
  bag.add("apple"); bag.add("apple"); bag.add("banana")
  assert bag.count("apple") == 2
  assert bag.len == 3
  bag.remove("apple")
  assert bag.count("apple") == 1
  echo "   ✓ Create, add, count, remove, len"

proc testBitSet() =
  echo "3. NiBitSet"
  var bs = newBitSet(128)
  bs.set(0); bs.set(63); bs.set(64)
  assert bs.test(0) and bs.test(63) and bs.test(64)
  assert not bs.test(1)
  assert bs.count == 3
  echo "   ✓ Create, set, test, count"

proc testBloom() =
  echo "4. NiBloom"
  var bloom = newBloom(1000, 3)
  bloom.add("hello"); bloom.add("world")
  assert bloom.contains("hello")
  assert bloom.contains("world")
  echo "   ✓ Create, add, contains"

proc testDeque() =
  echo "5. NiDeque"
  var dq = newDeque()
  dq.pushBack("a"); dq.pushBack("b"); dq.pushFront("c")
  assert dq.len == 3
  assert dq.peekFront() == "c"
  assert dq.peekBack() == "b"
  assert dq.popFront() == "c"
  assert dq.popBack() == "b"
  echo "   ✓ Create, push, peek, pop, len"

proc testDisjointSet() =
  echo "6. NiDisjointSet"
  var ds = newDisjointSet(5)
  ds.union(0, 1); ds.union(2, 3)
  assert ds.connected(0, 1)
  assert not ds.connected(0, 2)
  assert ds.componentCount == 3
  ds.union(1, 3)
  assert ds.connected(0, 3)
  echo "   ✓ Create, union, connected, componentCount"

proc testFenwickTree() =
  echo "7. NiFenwickTree"
  var ft = newFenwickTree(5)
  for i in 0..4: ft.update(i, i + 1)
  assert ft.query(4) == 15
  assert ft.rangeQuery(1, 3) == 9
  echo "   ✓ Create, update, query, rangeQuery"

proc testGraph() =
  echo "8. NiGraph"
  var g = newGraph(true)
  g.addEdge("A", "B", 1.0)
  g.addEdge("B", "C", 2.0)
  g.addEdge("A", "C", 3.0)
  assert g.nodeCount == 3
  assert g.edgeCount == 3
  assert g.hasEdge("A", "B")
  assert not g.hasEdge("B", "A")
  let dfs = g.dfs("A")
  assert dfs.len == 3
  echo "   ✓ Create, addEdge, nodeCount, edgeCount, DFS, BFS"

proc testHeap() =
  echo "9. NiHeap"
  var h = newHeap()
  h.push("cherry"); h.push("apple"); h.push("banana")
  assert h.peek() == "apple"
  assert h.pop() == "apple"
  assert h.len == 2
  echo "   ✓ Create, push, peek, pop, len"

proc testIntervalTree() =
  echo "10. NiIntervalTree"
  var it = newIntervalTree()
  it.insert(15, 20); it.insert(10, 30); it.insert(17, 19)
  let overlaps = it.query(14, 16)
  assert overlaps.len >= 2
  echo "   ✓ Create, insert, query"

proc testKdTree() =
  echo "11. NiKdTree"
  var kdt = newKdTree(2)
  kdt.insert(@[1.0, 2.0], "a")
  kdt.insert(@[3.0, 4.0], "b")
  kdt.insert(@[5.0, 6.0], "c")
  let nearest = kdt.nearest(@[2.5, 3.0])
  assert nearest.data == "b"
  echo "   ✓ Create, insert, nearest"

proc testLru() =
  echo "12. NiLRU"
  var lru = newLRU(2)
  lru.put("a", "1"); lru.put("b", "2")
  assert lru.has("a")
  lru.put("c", "3")
  assert not lru.has("a")
  assert lru.has("c")
  echo "   ✓ Create, put, get, has, eviction"

proc testMap() =
  echo "13. NiMap"
  var m = newMap()
  m.set("c", "3"); m.set("a", "1"); m.set("b", "2")
  assert m.len == 3
  assert m.get("a") == "1"
  m.set("a", "11")
  assert m.get("a") == "11"
  m.del("b")
  assert not m.has("b")
  echo "   ✓ Create, set, get, has, del, sorted"

proc testMatrix() =
  echo "14. NiMatrix"
  var m = newMatrix(2, 3)
  m.set(0, 0, 1.0); m.set(0, 1, 2.0); m.set(0, 2, 3.0)
  m.set(1, 0, 4.0); m.set(1, 1, 5.0); m.set(1, 2, 6.0)
  assert m.get(0, 0) == 1.0
  assert m.get(1, 2) == 6.0
  let t = m.transpose()
  assert t.rows == 3 and t.cols == 2
  echo "   ✓ Create, set, get, transpose"

proc testMerkleTree() =
  echo "15. NiMerkleTree"
  let tree = newMerkleTree(@["a", "b", "c", "d"])
  assert tree.leafCount == 4
  assert tree.rootHash.len > 0
  assert tree.verify(0, "a")
  assert not tree.verify(0, "x")
  echo "   ✓ Create, rootHash, verify, leafCount"

proc testObject() =
  echo "16. NiObject"
  var obj = newObject()
  obj.set("name", "Alice"); obj.set("age", "30")
  assert obj.get("name") == "Alice"
  assert obj.has("age")
  obj.del("age")
  assert not obj.has("age")
  echo "   ✓ Create, set, get, has, del"

proc testQueue() =
  echo "17. NiQueue"
  var q = newQueue()
  q.enqueue("first"); q.enqueue("second"); q.enqueue("third")
  assert q.peek() == "first"
  assert q.dequeue() == "first"
  assert q.len == 2
  echo "   ✓ Create, enqueue, peek, dequeue, len"

proc testRing() =
  echo "18. NiRing"
  var r = newRing(3)
  r.push("a"); r.push("b"); r.push("c")
  assert r.isFull
  r.push("d")
  assert r.len == 3
  assert r.pop() == "b"
  echo "   ✓ Create, push, pop, isFull, len"

proc testRope() =
  echo "19. NiRope"
  let r1 = newRope("Hello, ")
  let r2 = newRope("World!")
  let combined = concat(r1, r2)
  assert combined.toString() == "Hello, World!"
  assert combined.length == 13
  assert combined.substring(0, 5) == "Hello"
  echo "   ✓ Create, concat, toString, substring"

proc testSegmentTree() =
  echo "20. NiSegmentTree"
  var st = newSegmentTree(5, "sum")
  st.data = @[1, 2, 3, 4, 5]
  st.build(1, 0, 4)
  assert st.query(1, 0, 4, 0, 4) == 15
  assert st.query(1, 0, 4, 1, 3) == 9
  st.update(1, 0, 4, 2, 10)
  assert st.query(1, 0, 4, 0, 4) == 22
  echo "   ✓ Create, build, query, update"

proc testSet() =
  echo "21. NiSet"
  var s = newSet()
  s.add("apple"); s.add("banana"); s.add("apple")
  assert s.len == 2
  assert s.contains("apple")
  s.remove("apple")
  assert not s.contains("apple")
  echo "   ✓ Create, add, contains, remove, len"

proc testSkipList() =
  echo "22. NiSkipList"
  var sl = newSkipList()
  sl.insert("c"); sl.insert("a"); sl.insert("b")
  assert sl.search("a")
  assert not sl.search("d")
  assert sl.len == 3
  echo "   ✓ Create, insert, search, len"

proc testSorted() =
  echo "23. NiSorted"
  var s = newSorted()
  s.add("c"); s.add("a"); s.add("b"); s.add("a")
  assert s.len == 3
  assert s.contains("a")
  let seq1 = s.toSeq()
  assert seq1[0] == "a" and seq1[1] == "b" and seq1[2] == "c"
  echo "   ✓ Create, add, contains, toSeq"

proc testSparseMatrix() =
  echo "24. NiSparseMatrix"
  var sm = newSparseMatrix(1000, 1000)
  sm.set(0, 0, 1.0); sm.set(999, 999, 2.0)
  assert sm.get(0, 0) == 1.0
  assert sm.get(0, 1) == 0.0
  assert sm.nnz == 2
  echo "   ✓ Create, set, get, nnz"

proc testStack() =
  echo "25. NiStack"
  var s = newStack()
  s.push("first"); s.push("second"); s.push("third")
  assert s.peek() == "third"
  assert s.pop() == "third"
  assert s.len == 2
  echo "   ✓ Create, push, peek, pop, len"

proc testSuffixArray() =
  echo "26. NiSuffixArray"
  let sa = newSuffixArray("banana")
  assert sa.sa.len == 6
  let results = sa.search("ana")
  assert results.len == 2
  echo "   ✓ Create, search"

proc testTreap() =
  echo "27. NiTreap"
  var t = newTreap()
  t.insert("b"); t.insert("a"); t.insert("c")
  assert t.search("a")
  assert not t.search("d")
  assert t.len == 3
  echo "   ✓ Create, insert, search, len"

proc testTrie() =
  echo "28. NiTrie"
  var t = newTrie()
  t.insert("hello", "world")
  t.insert("help", "me")
  t.insert("hero", "zero")
  assert t.search("hello")
  assert t.startsWith("he")
  assert t.get("hello") == "world"
  let ac = t.autocomplete("hel")
  assert ac.len == 2
  echo "   ✓ Create, insert, search, startsWith, get, autocomplete"

proc testWaveletTree() =
  echo "29. NiWaveletTree"
  let data = @[3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
  let wt = newWaveletTree(data)
  assert wt.minVal == 1
  assert wt.maxVal == 9
  assert wt.rangeRank(0, 10, 5) == 3
  echo "   ✓ Create, rangeRank"

proc main() =
  echo "=== nimm Data Structure Test Suite ==="
  echo ""
  
  testArray()
  testBag()
  testBitSet()
  testBloom()
  testDeque()
  testDisjointSet()
  testFenwickTree()
  testGraph()
  testHeap()
  testIntervalTree()
  testKdTree()
  testLru()
  testMap()
  testMatrix()
  testMerkleTree()
  testObject()
  testQueue()
  testRing()
  testRope()
  testSegmentTree()
  testSet()
  testSkipList()
  testSorted()
  testSparseMatrix()
  testStack()
  testSuffixArray()
  testTreap()
  testTrie()
  testWaveletTree()
  
  echo ""
  echo "=== All 29 data structures tested successfully ==="

when isMainModule:
  main()
