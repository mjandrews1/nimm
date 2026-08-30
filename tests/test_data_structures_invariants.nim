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

  echo "  stack LIFO / queue FIFO / heap min-order all hold"
  echo "Data-structure invariant test passed!"

main()
