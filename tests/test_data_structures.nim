# test_data_structures.nim — Test nimm data structures

import ../data_structures

proc main() =
  echo "Testing nimm data structures..."
  
  # NiArray
  var arr = newArray()
  arr.add("a")
  arr.add("b")
  arr.add("c")
  assert arr.len == 3
  assert arr.get(0) == "a"
  assert arr.get(1) == "b"
  assert arr.get(2) == "c"
  arr.set(1, "B")
  assert arr.get(1) == "B"
  echo "✓ NiArray"
  
  # NiObject
  var obj = newObject()
  obj.set("name", "Alice")
  obj.set("age", "30")
  assert obj.get("name") == "Alice"
  assert obj.has("age") == true
  assert obj.has("missing") == false
  obj.del("age")
  assert obj.has("age") == false
  echo "✓ NiObject"
  
  # NiStack
  var stack = newStack()
  stack.push("a")
  stack.push("b")
  stack.push("c")
  assert stack.len == 3
  assert stack.peek() == "c"
  assert stack.pop() == "c"
  assert stack.pop() == "b"
  assert stack.len == 1
  echo "✓ NiStack"
  
  # NiQueue
  var queue = newQueue()
  queue.enqueue("a")
  queue.enqueue("b")
  queue.enqueue("c")
  assert queue.len == 3
  assert queue.peek() == "a"
  assert queue.dequeue() == "a"
  assert queue.dequeue() == "b"
  assert queue.len == 1
  echo "✓ NiQueue"
  
  # NiSet
  var s = newSet()
  s.add("a")
  s.add("b")
  s.add("a")  # duplicate
  assert s.len == 2
  assert s.contains("a") == true
  assert s.contains("c") == false
  s.remove("a")
  assert s.contains("a") == false
  echo "✓ NiSet"
  
  # NiMap
  var m = newMap()
  m.set("c", "3")
  m.set("a", "1")
  m.set("b", "2")
  assert m.len == 3
  assert m.get("a") == "1"
  assert m.has("b") == true
  # Check sorted order
  let seq1 = m.data
  assert seq1[0][0] == "a"
  assert seq1[1][0] == "b"
  assert seq1[2][0] == "c"
  m.set("a", "11")  # update
  assert m.get("a") == "11"
  m.del("b")
  assert m.has("b") == false
  echo "✓ NiMap"
  
  # NiSorted
  var sorted = newSorted()
  sorted.add("c")
  sorted.add("a")
  sorted.add("b")
  sorted.add("a")  # duplicate
  assert sorted.len == 3
  assert sorted.contains("a") == true
  let seq2 = sorted.toSeq()
  assert seq2[0] == "a"
  assert seq2[1] == "b"
  assert seq2[2] == "c"
  sorted.remove("b")
  assert sorted.len == 2
  echo "✓ NiSorted"
  
  # NiDeque
  var dq = newDeque()
  dq.pushBack("a")
  dq.pushBack("b")
  dq.pushFront("c")
  assert dq.len == 3
  assert dq.peekFront() == "c"
  assert dq.peekBack() == "b"
  assert dq.popFront() == "c"
  assert dq.popBack() == "b"
  assert dq.len == 1
  echo "✓ NiDeque"
  
  # NiBag
  var bag = newBag()
  bag.add("a")
  bag.add("a")
  bag.add("b")
  assert bag.len == 3  # total count
  assert bag.uniqueLen == 2  # unique values
  assert bag.count("a") == 2
  assert bag.count("b") == 1
  bag.remove("a")
  assert bag.count("a") == 1
  bag.remove("a")
  assert bag.count("a") == 0
  assert bag.uniqueLen == 1
  echo "✓ NiBag"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
