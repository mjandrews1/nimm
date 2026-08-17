# test_advanced_structures.nim — Test advanced data structures

import ../data_structures

proc main() =
  echo "Testing advanced data structures..."
  
  # Test NiSkipList
  var sl = newSkipList()
  sl.insert("c")
  sl.insert("a")
  sl.insert("b")
  assert sl.search("a")
  assert sl.search("b")
  assert sl.search("c")
  assert not sl.search("d")
  assert sl.len == 3
  echo "✓ NiSkipList"
  
  # Test NiTreap
  var treap = newTreap()
  treap.insert("b")
  treap.insert("a")
  treap.insert("c")
  assert treap.search("a")
  assert treap.search("b")
  assert treap.search("c")
  assert not treap.search("d")
  assert treap.len == 3
  echo "✓ NiTreap"
  
  # Test NiDisjointSet
  var ds = newDisjointSet(5)
  ds.union(0, 1)
  ds.union(2, 3)
  assert ds.connected(0, 1)
  assert ds.connected(2, 3)
  assert not ds.connected(0, 2)
  assert ds.componentCount == 3  # {0,1}, {2,3}, {4}
  ds.union(1, 3)
  assert ds.connected(0, 3)
  assert ds.componentCount == 2
  echo "✓ NiDisjointSet"
  
  # Test NiSegmentTree (sum)
  var st = newSegmentTree(5, "sum")
  st.data = @[1, 2, 3, 4, 5]
  st.build(1, 0, 4)
  assert st.query(1, 0, 4, 0, 4) == 15  # sum of all
  assert st.query(1, 0, 4, 1, 3) == 9   # sum of 2+3+4
  st.update(1, 0, 4, 2, 10)  # set index 2 to 10
  assert st.query(1, 0, 4, 0, 4) == 22  # 1+2+10+4+5
  echo "✓ NiSegmentTree"
  
  # Test NiFenwickTree
  var ft = newFenwickTree(5)
  ft.update(0, 1)
  ft.update(1, 2)
  ft.update(2, 3)
  ft.update(3, 4)
  ft.update(4, 5)
  assert ft.query(4) == 15  # prefix sum
  assert ft.rangeQuery(1, 3) == 9  # 2+3+4
  echo "✓ NiFenwickTree"
  
  # Test NiSparseMatrix
  var sm = newSparseMatrix(3, 3)
  sm.set(0, 0, 1.0)
  sm.set(1, 1, 2.0)
  sm.set(2, 2, 3.0)
  assert sm.get(0, 0) == 1.0
  assert sm.get(0, 1) == 0.0
  assert sm.nnz == 3
  echo "✓ NiSparseMatrix"
  
  # Test NiIntervalTree
  var it = newIntervalTree()
  it.insert(15, 20)
  it.insert(10, 30)
  it.insert(17, 19)
  it.insert(5, 20)
  let overlaps = it.query(14, 16)
  assert overlaps.len >= 2  # should find [15,20] and [10,30]
  echo "✓ NiIntervalTree"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
