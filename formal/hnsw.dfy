// formal/hnsw.dfy
//
// Formal model of the HNSW vector index invariants (future_search_tool/src/hnsw.nim):
// the neighbor graph must stay bidirectional (no one-way edges), and cosine
// similarity is symmetric with self-similarity 1.
//
// Verify with:  dafny verify formal/hnsw.dfy

module HNSW {

  // ============ cosine similarity ============
  function Dot(a: seq<real>, b: seq<real>): real
    requires |a| == |b|
    decreases |a|
  {
    if |a| == 0 then 0.0 else a[0] * b[0] + Dot(a[1..], b[1..])
  }

  lemma DotSymmetric(a: seq<real>, b: seq<real>)
    requires |a| == |b|
    ensures Dot(a, b) == Dot(b, a)
    decreases |a|
  {
    if |a| == 0 {
    } else {
      DotSymmetric(a[1..], b[1..]);
    }
  }

  function NormSq(a: seq<real>): real { Dot(a, a) }

  // Cosine similarity as Dot scaled by the norms. The square root is opaque;
  // only the self/symmetry facts below are needed, so we axiomatize it.
  function Sqrt(x: real): real

  lemma {:axiom} SqrtSquared(x: real)
    requires x >= 0.0
    ensures Sqrt(x) * Sqrt(x) == x

  function Cosine(a: seq<real>, b: seq<real>): real
    requires |a| == |b|
  {
    var n := Sqrt(NormSq(a)) * Sqrt(NormSq(b));
    if n == 0.0 then 0.0 else Dot(a, b) / n
  }

  lemma CosineSymmetric(a: seq<real>, b: seq<real>)
    requires |a| == |b|
    ensures Cosine(a, b) == Cosine(b, a)
  {
    DotSymmetric(a, b);
  }

  // Self-similarity is 1 for any non-zero vector.
  lemma CosineSelfIsOne(a: seq<real>)
    requires |a| > 0
    requires NormSq(a) > 0.0
    ensures Cosine(a, a) == 1.0
  {
    SqrtSquared(NormSq(a));
    assert Sqrt(NormSq(a)) * Sqrt(NormSq(a)) == NormSq(a);
    assert NormSq(a) / NormSq(a) == 1.0;
  }

  // ============ neighbor graph ============
  // A node maps to the set of its neighbors. A missing node maps to {}.
  type Graph = int -> set<int>

  ghost predicate Symmetric(g: Graph)
  {
    forall a, b :: (b in g(a)) <==> (a in g(b))
  }

  ghost predicate BoundedDegree(g: Graph, M: int)
  {
    forall a :: |g(a)| <= M
  }

  function SetNeighbors(g: Graph, a: int, s: set<int>): Graph
  {
    (x: int) => if x == a then s else g(x)
  }

  // Add a bidirectional edge a <-> b.
  function Connect(g: Graph, a: int, b: int): Graph
  {
    SetNeighbors(SetNeighbors(g, a, g(a) + {b}), b, g(b) + {a})
  }

  // Remove a bidirectional edge a <-> b.
  function RemoveEdge(g: Graph, a: int, b: int): Graph
  {
    SetNeighbors(SetNeighbors(g, a, g(a) - {b}), b, g(b) - {a})
  }

  // A one-sided removal (the bug in hnsw.nim's trim): drop b from a's list
  // but leave a in b's list.
  function RemoveEdgeOneSided(g: Graph, a: int, b: int): Graph
  {
    SetNeighbors(g, a, g(a) - {b})
  }

  lemma ConnectPreservesSymmetric(g: Graph, a: int, b: int)
    requires Symmetric(g)
    ensures Symmetric(Connect(g, a, b))
  {
  }

  lemma RemoveEdgePreservesSymmetric(g: Graph, a: int, b: int)
    requires Symmetric(g)
    ensures Symmetric(RemoveEdge(g, a, b))
  {
  }

  // A concrete symmetric graph {0 <-> 1}.
  function TwoNodeGraph(): Graph
  {
    (x: int) => if x == 0 then {1} else if x == 1 then {0} else {}
  }

  lemma TwoNodeGraphSymmetric()
    ensures Symmetric(TwoNodeGraph())
  {
  }

  // The one-sided trim breaks symmetry: 0 loses 1, but 1 still points at 0.
  lemma OneSidedRemoveBreaksSymmetric()
    ensures !Symmetric(RemoveEdgeOneSided(TwoNodeGraph(), 0, 1))
  {
    assert RemoveEdgeOneSided(TwoNodeGraph(), 0, 1)(0) == {};
    assert RemoveEdgeOneSided(TwoNodeGraph(), 0, 1)(1) == {0};
  }

}
