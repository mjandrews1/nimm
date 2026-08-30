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

  // ================= Trie (prefix tree) =================
  // Model a trie as the set of inserted keys. search = membership;
  // startsWith(prefix) = some key has `prefix` as a prefix.

  type Key = seq<char>

  predicate IsPrefix(p: Key, s: Key)
  {
    |p| <= |s| && s[..|p|] == p
  }

  type Trie = set<Key>

  function TInsert(t: Trie, k: Key): Trie { t + {k} }
  function TSearch(t: Trie, k: Key): bool { k in t }
  function TStartsWith(t: Trie, p: Key): bool { exists k :: k in t && IsPrefix(p, k) }

  lemma TSearchInsert(t: Trie, k: Key)
    ensures TSearch(TInsert(t, k), k)
  {
  }

  lemma TStartsWithInsert(t: Trie, k: Key, p: Key)
    requires IsPrefix(p, k)
    ensures TStartsWith(TInsert(t, k), p)
  {
    assert k in TInsert(t, k);
  }

  // ================= Graph (adjacency + reachability) =================
  // Directed graph as a set of edges; an undirected addEdge inserts both
  // directions. Reachability is a bounded path relation.

  type Node = string
  datatype Edge = E(src: Node, dst: Node)

  function AddEdgeDirected(g: set<Edge>, src: Node, dst: Node): set<Edge> { g + {E(src, dst)} }
  function AddEdgeUndirected(g: set<Edge>, src: Node, dst: Node): set<Edge> { g + {E(src, dst)} + {E(dst, src)} }

  lemma HasEdgeDirected(g: set<Edge>, src: Node, dst: Node)
    ensures E(src, dst) in AddEdgeDirected(g, src, dst)
  {
  }

  lemma UndirectedSymmetric(g: set<Edge>, src: Node, dst: Node)
    ensures E(src, dst) in AddEdgeUndirected(g, src, dst)
    ensures E(dst, src) in AddEdgeUndirected(g, src, dst)
  {
  }

  // Bounded reachability: b is reachable from a in at most `fuel` edges.
  ghost predicate ReachIn(g: set<Edge>, a: Node, b: Node, fuel: nat)
    decreases fuel
  {
    if fuel == 0 then a == b
    else a == b || exists m :: E(a, m) in g && ReachIn(g, m, b, fuel - 1)
  }

  lemma ReachInReflexive(g: set<Edge>, a: Node, fuel: nat)
    ensures ReachIn(g, a, a, fuel)
  {
  }

  lemma ReachInEdge(g: set<Edge>, a: Node, b: Node)
    requires E(a, b) in g
    ensures ReachIn(g, a, b, 1)
  {
    assert ReachIn(g, b, b, 0);
  }

  // Reachability is monotone in the fuel bound.
  lemma ReachInMonotone(g: set<Edge>, a: Node, b: Node, f1: nat, f2: nat)
    requires f1 <= f2 && ReachIn(g, a, b, f1)
    ensures ReachIn(g, a, b, f2)
    decreases f1
  {
    if f1 == 0 {
      assert a == b;
    } else if a == b {
    } else {
      var m :| E(a, m) in g && ReachIn(g, m, b, f1 - 1);
      ReachInMonotone(g, m, b, f1 - 1, f2 - 1);
    }
  }

  lemma ReachInTransitive(g: set<Edge>, a: Node, b: Node, c: Node, f1: nat, f2: nat)
    requires ReachIn(g, a, b, f1) && ReachIn(g, b, c, f2)
    ensures ReachIn(g, a, c, f1 + f2)
    decreases f1
  {
    if f1 == 0 {
      assert a == b;
    } else if a == b {
      ReachInMonotone(g, b, c, f2, f1 + f2);
    } else {
      var m :| E(a, m) in g && ReachIn(g, m, b, f1 - 1);
      ReachInTransitive(g, m, b, c, f1 - 1, f2);
    }
  }

  // ================= LRU (eviction) =================
  // The order list holds keys most-recent at the end. put of a new key when
  // full evicts the front (least-recently-used); size never exceeds capacity.

  function RemoveKey(lru: seq<string>, key: string): seq<string>
    decreases |lru|
  {
    if |lru| == 0 then []
    else if lru[0] == key then RemoveKey(lru[1..], key)
    else [lru[0]] + RemoveKey(lru[1..], key)
  }

  lemma RemoveKeyLen(lru: seq<string>, key: string)
    ensures |RemoveKey(lru, key)| <= |lru|
    decreases |lru|
  {
    if |lru| == 0 {
    } else if lru[0] == key {
      RemoveKeyLen(lru[1..], key);
    } else {
      RemoveKeyLen(lru[1..], key);
    }
  }

  function LruPut(lru: seq<string>, key: string, capacity: int): seq<string>
    requires capacity > 0
  {
    var l := RemoveKey(lru, key);
    if |l| >= capacity then l[1..] + [key]
    else l + [key]
  }

  lemma LruBound(lru: seq<string>, key: string, capacity: int)
    requires capacity > 0 && |lru| <= capacity
    ensures |LruPut(lru, key, capacity)| <= capacity
  {
    RemoveKeyLen(lru, key);
    var l := RemoveKey(lru, key);
    assert |l| <= capacity;
    if |l| >= capacity {
      assert |l| == capacity;
    } else {
      assert |l| < capacity;
    }
  }

  // ================= BitSet (set/clear/test) =================
  // A bitset as the set of set indices; set adds, clear removes, test checks.

  type Bitset = set<int>

  function BsSet(bs: Bitset, i: int): Bitset { bs + {i} }
  function BsClear(bs: Bitset, i: int): Bitset { bs - {i} }
  function BsTest(bs: Bitset, i: int): bool { i in bs }

  lemma BsTestAfterSet(bs: Bitset, i: int)
    ensures BsTest(BsSet(bs, i), i)
  {
  }

  lemma BsTestAfterClear(bs: Bitset, i: int)
    ensures !BsTest(BsClear(bs, i), i)
  {
  }

}
