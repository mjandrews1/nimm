# test_specialized_structures.nim — Test specialized data structures

import ../data_structures

proc main() =
  echo "Testing specialized data structures..."
  
  # Test NiSuffixArray
  let text = "banana"
  let sa = newSuffixArray(text)
  assert sa.text == "banana"
  assert sa.sa.len == 6
  # Search for "ana"
  let results = sa.search("ana")
  assert results.len == 2  # found at positions 1 and 3
  echo "✓ NiSuffixArray"
  
  # Test NiWaveletTree
  let data = @[3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
  let wt = newWaveletTree(data)
  assert wt.minVal == 1
  assert wt.maxVal == 9
  # Count occurrences of 5 in [0, 10]
  let count5 = wt.rangeRank(0, 10, 5)
  assert count5 == 3  # 5 appears 3 times
  echo "✓ NiWaveletTree"
  
  # Test NiKdTree
  var kdt = newKdTree(2)
  kdt.insert(@[1.0, 2.0], "a")
  kdt.insert(@[3.0, 4.0], "b")
  kdt.insert(@[5.0, 6.0], "c")
  let nearest = kdt.nearest(@[2.5, 3.0])
  assert nearest.data == "b"  # closest to (2.5, 3.0)
  echo "✓ NiKdTree"
  
  # Test NiRope
  let rope1 = newRope("Hello, ")
  let rope2 = newRope("World!")
  let combined = concat(rope1, rope2)
  assert combined.toString() == "Hello, World!"
  assert combined.length == 13
  let sub = combined.substring(0, 5)
  assert sub == "Hello"
  echo "✓ NiRope"
  
  # Test NiMerkleTree
  let leaves = @["a", "b", "c", "d"]
  let tree = newMerkleTree(leaves)
  assert tree.leafCount == 4
  assert tree.rootHash.len > 0
  assert tree.verify(0, "a")
  assert tree.verify(3, "d")
  assert not tree.verify(0, "x")
  echo "✓ NiMerkleTree"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
