// formal/data_structures.dfy
//
// Formal model of the key invariants of the $NI_* data structures
// (data_structures.nim): stack LIFO, queue FIFO, and the min-heap property
// (parent <= children; the root is the minimum).
//
// Verify with:  dafny verify formal/data_structures.dfy

module DataStructures {

  // --- Stack (LIFO) ---
  function Push(stack: seq<int>, v: int): seq<int> { stack + [v] }
  function Pop(stack: seq<int>): seq<int> { if |stack| > 0 then stack[..|stack| - 1] else stack }
  function Top(stack: seq<int>): int { if |stack| > 0 then stack[|stack| - 1] else 0 }

  lemma TopAfterPush(stack: seq<int>, v: int) ensures Top(Push(stack, v)) == v { }
  lemma PopPush(stack: seq<int>, v: int) ensures Pop(Push(stack, v)) == stack { }

  // --- Queue (FIFO) ---
  function Enqueue(q: seq<int>, v: int): seq<int> { q + [v] }
  function Dequeue(q: seq<int>): seq<int> { if |q| > 0 then q[1..] else q }
  function Front(q: seq<int>): int { if |q| > 0 then q[0] else 0 }

  lemma FrontAfterEnqueue(q: seq<int>, v: int)
    requires |q| > 0
    ensures Front(Enqueue(q, v)) == q[0]
  { }

  lemma DequeueFront(q: seq<int>)
    requires |q| > 0
    ensures Front(Dequeue(q)) == (if |q| > 1 then q[1] else 0)
  { }

  // --- Heap (min-heap) ---
  function Parent(i: int): int { (i - 1) / 2 }

  // The heap property: every node is >= its parent.
  predicate IsHeap(data: seq<int>)
  {
    forall i | 0 < i < |data| :: data[Parent(i)] <= data[i]
  }

  function Peek(data: seq<int>): int { if |data| > 0 then data[0] else 0 }

  // The root is an ancestor of every node, so the root is <= every node.
  lemma AncestorLe(data: seq<int>, i: nat)
    requires IsHeap(data) && i < |data|
    ensures data[0] <= data[i]
    decreases i
  {
    if i > 0 {
      AncestorLe(data, (i - 1) / 2);
      assert 0 < i < |data|;
      assert data[Parent(i)] <= data[i];
    }
  }

  // Peek (the root) is the minimum.
  lemma PeekIsMin(data: seq<int>)
    requires IsHeap(data) && |data| > 0
    ensures forall i | 0 <= i < |data| :: data[0] <= data[i]
  {
    forall i | 0 <= i < |data|
      ensures data[0] <= data[i]
    {
      AncestorLe(data, i);
    }
  }

}
