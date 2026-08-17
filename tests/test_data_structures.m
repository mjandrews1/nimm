; test_data_structures.m — nimm Data Structure Test Program
; Demonstrates invocation, operation, and use of all 29 data structures
;
; Run: nim c -d:release -r tests/test_data_structures_m.nim

; =============================================================================
; 1. NiArray — Dynamic array
; =============================================================================
TEST_ARRAY
 ; Create array and add elements
 SET arr=$NI_ARRAY()
 DO $NI_ARRAY_ADD(arr,"alpha")
 DO $NI_ARRAY_ADD(arr,"beta")
 DO $NI_ARRAY_ADD(arr,"gamma")
 
 ; Access by index
 WRITE "Array[0]: ",$NI_ARRAY_GET(arr,0),!
 WRITE "Array[1]: ",$NI_ARRAY_GET(arr,1),!
 WRITE "Array length: ",$NI_ARRAY_LEN(arr),!
 
 ; Modify element
 DO $NI_ARRAY_SET(arr,1,"BETA")
 WRITE "Modified[1]: ",$NI_ARRAY_GET(arr,1),!
 
 QUIT

; =============================================================================
; 2. NiBag — Multiset (allows duplicates)
; =============================================================================
TEST_BAG
 ; Create bag and add items
 SET bag=$NI_BAG()
 DO $NI_BAG_ADD(bag,"apple")
 DO $NI_BAG_ADD(bag,"apple")
 DO $NI_BAG_ADD(bag,"banana")
 
 ; Check counts
 WRITE "apple count: ",$NI_BAG_COUNT(bag,"apple"),!
 WRITE "banana count: ",$NI_BAG_COUNT(bag,"banana"),!
 WRITE "Total items: ",$NI_BAG_LEN(bag),!
 WRITE "Unique items: ",$NI_BAG_UNIQUE_LEN(bag),!
 
 ; Remove one occurrence
 DO $NI_BAG_REMOVE(bag,"apple")
 WRITE "apple count after remove: ",$NI_BAG_COUNT(bag,"apple"),!
 
 QUIT

; =============================================================================
; 3. NiBitSet — Bit array
; =============================================================================
TEST_BITSET
 ; Create bitset and set bits
 SET bs=$NI_BITSET(128)
 DO $NI_BITSET_SET(bs,0)
 DO $NI_BITSET_SET(bs,63)
 DO $NI_BITSET_SET(bs,64)
 
 ; Test bits
 WRITE "Bit 0: ",$NI_BITSET_TEST(bs,0),!
 WRITE "Bit 1: ",$NI_BITSET_TEST(bs,1),!
 WRITE "Bit 63: ",$NI_BITSET_TEST(bs,63),!
 WRITE "Popcount: ",$NI_BITSET_COUNT(bs),!
 
 ; Bitwise operations
 SET bs2=$NI_BITSET(128)
 DO $NI_BITSET_SET(bs2,0)
 DO $NI_BITSET_SET(bs2,1)
 SET bs3=$NI_BITSET_OR(bs,bs2)
 WRITE "OR popcount: ",$NI_BITSET_COUNT(bs3),!
 
 QUIT

; =============================================================================
; 4. NiBloom — Bloom filter (probabilistic set membership)
; =============================================================================
TEST_BLOOM
 ; Create bloom filter and add items
 SET bloom=$NI_BLOOM(1000,3)
 DO $NI_BLOOM_ADD(bloom,"hello")
 DO $NI_BLOOM_ADD(bloom,"world")
 
 ; Check membership
 WRITE "Has 'hello': ",$NI_BLOOM_CONTAINS(bloom,"hello"),!
 WRITE "Has 'foo': ",$NI_BLOOM_CONTAINS(bloom,"foo"),!
 
 QUIT

; =============================================================================
; 5. NiDeque — Double-ended queue
; =============================================================================
TEST_DEQUE
 ; Create deque and push elements
 SET dq=$NI_DEQUE()
 DO $NI_DEQUE_PUSHBACK(dq,"a")
 DO $NI_DEQUE_PUSHBACK(dq,"b")
 DO $NI_DEQUE_PUSHFRONT(dq,"c")
 
 ; Access ends
 WRITE "Front: ",$NI_DEQUE_PEEKFRONT(dq),!
 WRITE "Back: ",$NI_DEQUE_PEEKBACK(dq),!
 WRITE "Length: ",$NI_DEQUE_LEN(dq),!
 
 ; Pop elements
 WRITE "Pop front: ",$NI_DEQUE_POPFRONT(dq),!
 WRITE "Pop back: ",$NI_DEQUE_POPBACK(dq),!
 
 QUIT

; =============================================================================
; 6. NiDisjointSet — Union-find
; =============================================================================
TEST_DISJOINTSET
 ; Create disjoint set and union elements
 SET ds=$NI_DISJOINTSET(5)
 DO $NI_DISJOINTSET_UNION(ds,0,1)
 DO $NI_DISJOINTSET_UNION(ds,2,3)
 
 ; Check connectivity
 WRITE "0-1 connected: ",$NI_DISJOINTSET_CONNECTED(ds,0,1),!
 WRITE "0-2 connected: ",$NI_DISJOINTSET_CONNECTED(ds,0,2),!
 WRITE "Components: ",$NI_DISJOINTSET_COMPONENTCOUNT(ds),!
 
 ; Connect more
 DO $NI_DISJOINTSET_UNION(ds,1,3)
 WRITE "0-3 connected: ",$NI_DISJOINTSET_CONNECTED(ds,0,3),!
 
 QUIT

; =============================================================================
; 7. NiFenwickTree — Binary indexed tree
; =============================================================================
TEST_FENWICKTREE
 ; Create fenwick tree and update values
 SET ft=$NI_FENWICKTREE(5)
 DO $NI_FENWICKTREE_UPDATE(ft,0,1)
 DO $NI_FENWICKTREE_UPDATE(ft,1,2)
 DO $NI_FENWICKTREE_UPDATE(ft,2,3)
 DO $NI_FENWICKTREE_UPDATE(ft,3,4)
 DO $NI_FENWICKTREE_UPDATE(ft,4,5)
 
 ; Query prefix sums
 WRITE "Prefix sum [0,4]: ",$NI_FENWICKTREE_QUERY(ft,4),!
 WRITE "Range sum [1,3]: ",$NI_FENWICKTREE_RANGEQUERY(ft,1,3),!
 
 QUIT

; =============================================================================
; 8. NiGraph — Adjacency list graph
; =============================================================================
TEST_GRAPH
 ; Create directed graph and add edges
 SET g=$NI_GRAPH(1)
 DO $NI_GRAPH_ADDNODE(g,"A")
 DO $NI_GRAPH_ADDNODE(g,"B")
 DO $NI_GRAPH_ADDNODE(g,"C")
 DO $NI_GRAPH_ADDEDGE(g,"A","B",1.0)
 DO $NI_GRAPH_ADDEDGE(g,"B","C",2.0)
 DO $NI_GRAPH_ADDEDGE(g,"A","C",3.0)
 
 ; Query graph
 WRITE "Node count: ",$NI_GRAPH_NODECOUNT(g),!
 WRITE "Edge count: ",$NI_GRAPH_EDGECOUNT(g),!
 WRITE "Has edge A->B: ",$NI_GRAPH_HASEDGE(g,"A","B"),!
 
 ; Traversal
 WRITE "DFS from A: ",$NI_GRAPH_DFS(g,"A"),!
 WRITE "BFS from A: ",$NI_GRAPH_BFS(g,"A"),!
 
 QUIT

; =============================================================================
; 9. NiHeap — Priority queue
; =============================================================================
TEST_HEAP
 ; Create heap and push elements
 SET h=$NI_HEAP()
 DO $NI_HEAP_PUSH(h,"cherry")
 DO $NI_HEAP_PUSH(h,"apple")
 DO $NI_HEAP_PUSH(h,"banana")
 
 ; Peek and pop
 WRITE "Peek: ",$NI_HEAP_PEEK(h),!
 WRITE "Pop: ",$NI_HEAP_POP(h),!
 WRITE "Pop: ",$NI_HEAP_POP(h),!
 WRITE "Length: ",$NI_HEAP_LEN(h),!
 
 QUIT

; =============================================================================
; 10. NiIntervalTree — Interval overlap queries
; =============================================================================
TEST_INTERVALTREE
 ; Create interval tree and insert intervals
 SET it=$NI_INTERVALTREE()
 DO $NI_INTERVALTREE_INSERT(it,15,20)
 DO $NI_INTERVALTREE_INSERT(it,10,30)
 DO $NI_INTERVALTREE_INSERT(it,17,19)
 
 ; Query overlapping intervals
 WRITE "Overlaps [14,16]: ",$NI_INTERVALTREE_QUERY(it,14,16),!
 
 QUIT

; =============================================================================
; 11. NiKdTree — Spatial nearest-neighbor
; =============================================================================
TEST_KDTREE
 ; Create k-d tree and insert points
 SET kdt=$NI_KDTREE(2)
 DO $NI_KDTREE_INSERT(kdt,"1.0,2.0","pointA")
 DO $NI_KDTREE_INSERT(kdt,"3.0,4.0","pointB")
 DO $NI_KDTREE_INSERT(kdt,"5.0,6.0","pointC")
 
 ; Find nearest neighbor
 WRITE "Nearest to (2.5,3.0): ",$NI_KDTREE_NEAREST(kdt,"2.5,3.0"),!
 
 QUIT

; =============================================================================
; 12. NiLRU — LRU cache
; =============================================================================
TEST_LRU
 ; Create LRU cache and put items
 SET lru=$NI_LRU(2)
 DO $NI_LRU_PUT(lru,"a","1")
 DO $NI_LRU_PUT(lru,"b","2")
 
 ; Get and check
 WRITE "Get 'a': ",$NI_LRU_GET(lru,"a"),!
 WRITE "Has 'a': ",$NI_LRU_HAS(lru,"a"),!
 
 ; Evict by adding new item
 DO $NI_LRU_PUT(lru,"c","3")
 WRITE "Has 'a' after eviction: ",$NI_LRU_HAS(lru,"a"),!
 WRITE "Has 'c': ",$NI_LRU_HAS(lru,"c"),!
 
 QUIT

; =============================================================================
; 13. NiMap — Ordered map
; =============================================================================
TEST_MAP
 ; Create map and set entries
 SET m=$NI_MAP()
 DO $NI_MAP_SET(m,"c","3")
 DO $NI_MAP_SET(m,"a","1")
 DO $NI_MAP_SET(m,"b","2")
 
 ; Get and check
 WRITE "Get 'a': ",$NI_MAP_GET(m,"a"),!
 WRITE "Has 'b': ",$NI_MAP_HAS(m,"b"),!
 WRITE "Length: ",$NI_MAP_LEN(m),!
 
 ; Delete
 DO $NI_MAP_DEL(m,"b")
 WRITE "Has 'b' after delete: ",$NI_MAP_HAS(m,"b"),!
 
 QUIT

; =============================================================================
; 14. NiMatrix — 2D array
; =============================================================================
TEST_MATRIX
 ; Create matrix and set values
 SET m=$NI_MATRIX(2,3)
 DO $NI_MATRIX_SET(m,0,0,1.0)
 DO $NI_MATRIX_SET(m,0,1,2.0)
 DO $NI_MATRIX_SET(m,0,2,3.0)
 DO $NI_MATRIX_SET(m,1,0,4.0)
 DO $NI_MATRIX_SET(m,1,1,5.0)
 DO $NI_MATRIX_SET(m,1,2,6.0)
 
 ; Get values
 WRITE "[0,0]: ",$NI_MATRIX_GET(m,0,0),!
 WRITE "[1,2]: ",$NI_MATRIX_GET(m,1,2),!
 
 ; Transpose
 SET t=$NI_MATRIX_TRANSPOSE(m)
 WRITE "Transpose rows: ",$NI_MATRIX_ROWS(t),!
 WRITE "Transpose cols: ",$NI_MATRIX_COLS(t),!
 
 QUIT

; =============================================================================
; 15. NiMerkleTree — Cryptographic verification
; =============================================================================
TEST_MERKLETREE
 ; Create merkle tree from data
 SET mt=$NI_MERKLETREE("a,b,c,d")
 
 ; Get root hash
 WRITE "Root hash: ",$NI_MERKLETREE_ROOTHASH(mt),!
 WRITE "Leaf count: ",$NI_MERKLETREE_LEAFCOUNT(mt),!
 
 ; Verify leaf
 WRITE "Verify[0]='a': ",$NI_MERKLETREE_VERIFY(mt,0,"a"),!
 WRITE "Verify[0]='x': ",$NI_MERKLETREE_VERIFY(mt,0,"x"),!
 
 QUIT

; =============================================================================
; 16. NiObject — Key-value object
; =============================================================================
TEST_OBJECT
 ; Create object and set properties
 SET obj=$NI_OBJECT()
 DO $NI_OBJECT_SET(obj,"name","Alice")
 DO $NI_OBJECT_SET(obj,"age","30")
 
 ; Get and check
 WRITE "Name: ",$NI_OBJECT_GET(obj,"name"),!
 WRITE "Has 'age': ",$NI_OBJECT_HAS(obj,"age"),!
 
 ; Delete
 DO $NI_OBJECT_DEL(obj,"age")
 WRITE "Has 'age' after delete: ",$NI_OBJECT_HAS(obj,"age"),!
 
 QUIT

; =============================================================================
; 17. NiQueue — FIFO queue
; =============================================================================
TEST_QUEUE
 ; Create queue and enqueue items
 SET q=$NI_QUEUE()
 DO $NI_QUEUE_ENQUEUE(q,"first")
 DO $NI_QUEUE_ENQUEUE(q,"second")
 DO $NI_QUEUE_ENQUEUE(q,"third")
 
 ; Peek and dequeue
 WRITE "Peek: ",$NI_QUEUE_PEEK(q),!
 WRITE "Dequeue: ",$NI_QUEUE_DEQUEUE(q),!
 WRITE "Dequeue: ",$NI_QUEUE_DEQUEUE(q),!
 WRITE "Length: ",$NI_QUEUE_LEN(q),!
 
 QUIT

; =============================================================================
; 18. NiRing — Circular buffer
; =============================================================================
TEST_RING
 ; Create ring buffer and push items
 SET r=$NI_RING(3)
 DO $NI_RING_PUSH(r,"a")
 DO $NI_RING_PUSH(r,"b")
 DO $NI_RING_PUSH(r,"c")
 
 ; Ring is full, push overwrites oldest
 DO $NI_RING_PUSH(r,"d")
 WRITE "Pop: ",$NI_RING_POP(r),!  ; should be "b" (a was overwritten)
 WRITE "Length: ",$NI_RING_LEN(r),!
 
 QUIT

; =============================================================================
; 19. NiRope — Large string manipulation
; =============================================================================
TEST_ROPE
 ; Create ropes and concatenate
 SET r1=$NI_ROPE("Hello, ")
 SET r2=$NI_ROPE("World!")
 SET r3=$NI_ROPE_CONCAT(r1,r2)
 
 ; Get substring
 WRITE "Full: ",$NI_ROPE_TOSTRING(r3),!
 WRITE "Length: ",$NI_ROPE_LENGTH(r3),!
 WRITE "Substring [0,5]: ",$NI_ROPE_SUBSTRING(r3,0,5),!
 
 QUIT

; =============================================================================
; 20. NiSegmentTree — Range queries
; =============================================================================
TEST_SEGMENTTREE
 ; Create segment tree for sum queries
 SET st=$NI_SEGMENTTREE(5,"sum")
 
 ; Build tree with values [1,2,3,4,5]
 DO $NI_SEGMENTTREE_SET(st,0,1)
 DO $NI_SEGMENTTREE_SET(st,1,2)
 DO $NI_SEGMENTTREE_SET(st,2,3)
 DO $NI_SEGMENTTREE_SET(st,3,4)
 DO $NI_SEGMENTTREE_SET(st,4,5)
 DO $NI_SEGMENTTREE_BUILD(st,1,0,4)
 
 ; Query sums
 WRITE "Sum [0,4]: ",$NI_SEGMENTTREE_QUERY(st,1,0,4,0,4),!
 WRITE "Sum [1,3]: ",$NI_SEGMENTTREE_QUERY(st,1,0,4,1,3),!
 
 ; Update and re-query
 DO $NI_SEGMENTTREE_UPDATE(st,1,0,4,2,10)
 WRITE "Sum [0,4] after update: ",$NI_SEGMENTTREE_QUERY(st,1,0,4,0,4),!
 
 QUIT

; =============================================================================
; 21. NiSet — Unordered set
; =============================================================================
TEST_SET
 ; Create set and add items
 SET s=$NI_SET()
 DO $NI_SET_ADD(s,"apple")
 DO $NI_SET_ADD(s,"banana")
 DO $NI_SET_ADD(s,"apple")  ; duplicate
 
 ; Check membership
 WRITE "Has 'apple': ",$NI_SET_CONTAINS(s,"apple"),!
 WRITE "Has 'cherry': ",$NI_SET_CONTAINS(s,"cherry"),!
 WRITE "Length: ",$NI_SET_LEN(s),!
 
 ; Remove
 DO $NI_SET_REMOVE(s,"apple")
 WRITE "Has 'apple' after remove: ",$NI_SET_CONTAINS(s,"apple"),!
 
 QUIT

; =============================================================================
; 22. NiSkipList — Probabilistic sorted structure
; =============================================================================
TEST_SKIPLIST
 ; Create skip list and insert items
 SET sl=$NI_SKIPLIST()
 DO $NI_SKIPLIST_INSERT(sl,"c")
 DO $NI_SKIPLIST_INSERT(sl,"a")
 DO $NI_SKIPLIST_INSERT(sl,"b")
 
 ; Search
 WRITE "Has 'a': ",$NI_SKIPLIST_SEARCH(sl,"a"),!
 WRITE "Has 'd': ",$NI_SKIPLIST_SEARCH(sl,"d"),!
 WRITE "Length: ",$NI_SKIPLIST_LEN(sl),!
 
 QUIT

; =============================================================================
; 23. NiSorted — Sorted collection (unique)
; =============================================================================
TEST_SORTED
 ; Create sorted collection and add items
 SET s=$NI_SORTED()
 DO $NI_SORTED_ADD(s,"c")
 DO $NI_SORTED_ADD(s,"a")
 DO $NI_SORTED_ADD(s,"b")
 DO $NI_SORTED_ADD(s,"a")  ; duplicate
 
 ; Check
 WRITE "Has 'a': ",$NI_SORTED_CONTAINS(s,"a"),!
 WRITE "Length: ",$NI_SORTED_LEN(s),!
 
 QUIT

; =============================================================================
; 24. NiSparseMatrix — Sparse 2D data
; =============================================================================
TEST_SPARSEMATRIX
 ; Create sparse matrix and set values
 SET sm=$NI_SPARSEMATRIX(1000,1000)
 DO $NI_SPARSEMATRIX_SET(sm,0,0,1.0)
 DO $NI_SPARSEMATRIX_SET(sm,999,999,2.0)
 
 ; Get values
 WRITE "[0,0]: ",$NI_SPARSEMATRIX_GET(sm,0,0),!
 WRITE "[0,1]: ",$NI_SPARSEMATRIX_GET(sm,0,1),!
 WRITE "Non-zero count: ",$NI_SPARSEMATRIX_NNZ(sm),!
 
 QUIT

; =============================================================================
; 25. NiStack — LIFO stack
; =============================================================================
TEST_STACK
 ; Create stack and push items
 SET s=$NI_STACK()
 DO $NI_STACK_PUSH(s,"first")
 DO $NI_STACK_PUSH(s,"second")
 DO $NI_STACK_PUSH(s,"third")
 
 ; Peek and pop
 WRITE "Peek: ",$NI_STACK_PEEK(s),!
 WRITE "Pop: ",$NI_STACK_POP(s),!
 WRITE "Pop: ",$NI_STACK_POP(s),!
 WRITE "Length: ",$NI_STACK_LEN(s),!
 
 QUIT

; =============================================================================
; 26. NiSuffixArray — String pattern matching
; =============================================================================
TEST_SUFFIXARRAY
 ; Create suffix array from text
 SET sa=$NI_SUFFIXARRAY("banana")
 
 ; Search for patterns
 WRITE "Search 'ana': ",$NI_SUFFIXARRAY_SEARCH(sa,"ana"),!
 WRITE "Search 'nan': ",$NI_SUFFIXARRAY_SEARCH(sa,"nan"),!
 
 QUIT

; =============================================================================
; 27. NiTreap — Randomized balanced BST
; =============================================================================
TEST_TREAP
 ; Create treap and insert items
 SET t=$NI_TREAP()
 DO $NI_TREAP_INSERT(t,"b")
 DO $NI_TREAP_INSERT(t,"a")
 DO $NI_TREAP_INSERT(t,"c")
 
 ; Search
 WRITE "Has 'a': ",$NI_TREAP_SEARCH(t,"a"),!
 WRITE "Has 'd': ",$NI_TREAP_SEARCH(t,"d"),!
 WRITE "Length: ",$NI_TREAP_LEN(t),!
 
 QUIT

; =============================================================================
; 28. NiTrie — Prefix tree
; =============================================================================
TEST_TRIE
 ; Create trie and insert words
 SET t=$NI_TRIE()
 DO $NI_TRIE_INSERT(t,"hello","world")
 DO $NI_TRIE_INSERT(t,"help","me")
 DO $NI_TRIE_INSERT(t,"hero","zero")
 
 ; Search and prefix
 WRITE "Search 'hello': ",$NI_TRIE_SEARCH(t,"hello"),!
 WRITE "Starts with 'he': ",$NI_TRIE_STARTSWITH(t,"he"),!
 WRITE "Get 'hello': ",$NI_TRIE_GET(t,"hello"),!
 
 ; Autocomplete
 WRITE "Autocomplete 'hel': ",$NI_TRIE_AUTOCOMPLETE(t,"hel"),!
 
 QUIT

; =============================================================================
; 29. NiWaveletTree — Range queries on sequences
; =============================================================================
TEST_WAVELETTREE
 ; Create wavelet tree from sequence
 SET wt=$NI_WAVELETTREE("3,1,4,1,5,9,2,6,5,3,5")
 
 ; Range rank queries
 WRITE "Count of 5 in [0,10]: ",$NI_WAVELETTREE_RANGERANK(wt,0,10,5),!
 
 QUIT

; =============================================================================
; Main entry point
; =============================================================================
MAIN
 WRITE "=== nimm Data Structure Test Program ===",!
 WRITE !
 
 DO TEST_ARRAY
 DO TEST_BAG
 DO TEST_BITSET
 DO TEST_BLOOM
 DO TEST_DEQUE
 DO TEST_DISJOINTSET
 DO TEST_FENWICKTREE
 DO TEST_GRAPH
 DO TEST_HEAP
 DO TEST_INTERVALTREE
 DO TEST_KDTREE
 DO TEST_LRU
 DO TEST_MAP
 DO TEST_MATRIX
 DO TEST_MERKLETREE
 DO TEST_OBJECT
 DO TEST_QUEUE
 DO TEST_RING
 DO TEST_ROPE
 DO TEST_SEGMENTTREE
 DO TEST_SET
 DO TEST_SKIPLIST
 DO TEST_SORTED
 DO TEST_SPARSEMATRIX
 DO TEST_STACK
 DO TEST_SUFFIXARRAY
 DO TEST_TREAP
 DO TEST_TRIE
 DO TEST_WAVELETTREE
 
 WRITE !,"=== All tests complete ===",!
 
 QUIT
