#!/bin/bash
# test_ni_structures.sh — Verify #393: advanced data structures wired via $NI_*
# Usage: ./tests/test_ni_structures.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #393: advanced data structures ==="

# NiHeap: min-heap priority queue
OUT=$($NIMM -x 'WRITE $NI_HEAP("create","h"),"|",$NI_HEAP("push","h","c"),"|",$NI_HEAP("push","h","a"),"|",$NI_HEAP("peek","h"),"|",$NI_HEAP("pop","h"),"|",$NI_HEAP("len","h")' 2>&1)
check "NiHeap push/peek/pop" "h|1|2|a|a|1" "$OUT"

# NiRing: ring buffer with overwrite
OUT=$($NIMM -x 'WRITE $NI_RING("create","r",3),"|",$NI_RING("push","r","a"),"|",$NI_RING("push","r","b"),"|",$NI_RING("push","r","c"),"|",$NI_RING("isfull","r"),"|",$NI_RING("push","r","d"),"|",$NI_RING("pop","r"),"|",$NI_RING("toseq","r")' 2>&1)
check "NiRing push/isfull/pop" "r|1|2|3|1|3|b|c,d" "$OUT"

# NiLRU: cache with eviction
OUT=$($NIMM -x 'WRITE $NI_LRU("create","l",2),"|",$NI_LRU("put","l","a","1"),"|",$NI_LRU("put","l","b","2"),"|",$NI_LRU("has","l","a"),"|",$NI_LRU("put","l","c","3"),"|",$NI_LRU("has","l","a"),"|",$NI_LRU("get","l","c")' 2>&1)
check "NiLRU put/get/eviction" "l|1|1|1|1|0|3" "$OUT"

# NiBitSet: bit set
OUT=$($NIMM -x 'WRITE $NI_BITSET("create","b",128),"|",$NI_BITSET("set","b",0),"|",$NI_BITSET("set","b",64),"|",$NI_BITSET("test","b",64),"|",$NI_BITSET("test","b",1),"|",$NI_BITSET("count","b")' 2>&1)
check "NiBitSet set/test/count" "b|1|1|1|0|2" "$OUT"

# NiTrie: prefix tree
OUT=$($NIMM -x 'WRITE $NI_TRIE("create","t"),"|",$NI_TRIE("insert","t","hello","world"),"|",$NI_TRIE("insert","t","help","me"),"|",$NI_TRIE("search","t","hello"),"|",$NI_TRIE("get","t","hello"),"|",$NI_TRIE("startswith","t","he"),"|",$NI_TRIE("autocomplete","t","hel")' 2>&1)
check "NiTrie insert/search/get/autocomplete" "t|1|1|1|world|1|help,hello" "$OUT"

# NiGraph: directed graph traversal
OUT=$($NIMM -x 'WRITE $NI_GRAPH("create","g"),"|",$NI_GRAPH("addedge","g","a","b"),"|",$NI_GRAPH("addedge","g","b","c"),"|",$NI_GRAPH("hasedge","g","a","b"),"|",$NI_GRAPH("nodecount","g"),"|",$NI_GRAPH("dfs","g","a"),"|",$NI_GRAPH("bfs","g","a")' 2>&1)
check "NiGraph addEdge/traversal" "g|1|1|1|3|a,b,c|a,b,c" "$OUT"

# NiMatrix: dense matrix
OUT=$($NIMM -x 'WRITE $NI_MATRIX("create","m",2,2),"|",$NI_MATRIX("set","m",0,0,3.5),"|",$NI_MATRIX("get","m",0,0),"|",$NI_MATRIX("rows","m"),"|",$NI_MATRIX("cols","m")' 2>&1)
check "NiMatrix set/get/dims" "m|1|3.5|2|2" "$OUT"

# NiBloom: bloom filter
OUT=$($NIMM -x 'WRITE $NI_BLOOM("create","bl",1000,3),"|",$NI_BLOOM("add","bl","hello"),"|",$NI_BLOOM("contains","bl","hello"),"|",$NI_BLOOM("contains","bl","foo")' 2>&1)
check "NiBloom add/contains" "bl|1|1|0" "$OUT"

# NiSkipList: skip list
OUT=$($NIMM -x 'WRITE $NI_SKIPLIST("create","s"),"|",$NI_SKIPLIST("insert","s","c"),"|",$NI_SKIPLIST("insert","s","a"),"|",$NI_SKIPLIST("search","s","a"),"|",$NI_SKIPLIST("search","s","z"),"|",$NI_SKIPLIST("len","s")' 2>&1)
check "NiSkipList insert/search/len" "s|1|1|1|0|2" "$OUT"

# NiTreap: treap
OUT=$($NIMM -x 'WRITE $NI_TREAP("create","t"),"|",$NI_TREAP("insert","t","b"),"|",$NI_TREAP("insert","t","a"),"|",$NI_TREAP("search","t","a"),"|",$NI_TREAP("search","t","z"),"|",$NI_TREAP("len","t")' 2>&1)
check "NiTreap insert/search/len" "t|1|1|1|0|2" "$OUT"

# NiDisjointSet: union-find
OUT=$($NIMM -x 'WRITE $NI_DSET("create","d",5),"|",$NI_DSET("union","d",0,1),"|",$NI_DSET("union","d",2,3),"|",$NI_DSET("connected","d",0,1),"|",$NI_DSET("connected","d",0,2),"|",$NI_DSET("count","d")' 2>&1)
check "NiDisjointSet union/connected/count" "d|1|1|1|0|3" "$OUT"

# NiSegmentTree: range queries
OUT=$($NIMM -x 'WRITE $NI_SEGTREE("create","s",5),"|",$NI_SEGTREE("setdata","s",1,2,3,4,5),"|",$NI_SEGTREE("build","s"),"|",$NI_SEGTREE("query","s",0,4),"|",$NI_SEGTREE("query","s",1,3),"|",$NI_SEGTREE("update","s",2,10),"|",$NI_SEGTREE("query","s",0,4)' 2>&1)
check "NiSegmentTree build/query/update" "s|1|1|15|9|1|22" "$OUT"

# NiFenwickTree: prefix sums
OUT=$($NIMM -x 'WRITE $NI_FENWICK("create","f",5),"|",$NI_FENWICK("update","f",0,1),"|",$NI_FENWICK("update","f",1,2),"|",$NI_FENWICK("query","f",4),"|",$NI_FENWICK("range","f",1,3)' 2>&1)
check "NiFenwickTree update/query/range" "f|1|1|3|2" "$OUT"

# NiSparseMatrix: sparse matrix
OUT=$($NIMM -x 'WRITE $NI_SPARSE("create","s",3,3),"|",$NI_SPARSE("set","s",0,0,1),"|",$NI_SPARSE("set","s",1,1,2),"|",$NI_SPARSE("get","s",0,0),"|",$NI_SPARSE("get","s",0,1),"|",$NI_SPARSE("nnz","s")' 2>&1)
check "NiSparseMatrix set/get/nnz" "s|1|1|1|0|2" "$OUT"

# NiIntervalTree: overlap queries
OUT=$($NIMM -x 'WRITE $NI_ITREE("create","i"),"|",$NI_ITREE("insert","i",15,20),"|",$NI_ITREE("insert","i",10,30),"|",$NI_ITREE("query","i",14,16)' 2>&1)
check "NiIntervalTree insert/query" "i|1|1|15-20,10-30" "$OUT"

# NiSuffixArray: pattern search
OUT=$($NIMM -x 'WRITE $NI_SUFFIX("create","s","banana"),"|",$NI_SUFFIX("len","s")' 2>&1)
check "NiSuffixArray create/len" "s|6" "$OUT"
OUT=$($NIMM -x 'WRITE $NI_SUFFIX("create","s","banana"),"|",$NI_SUFFIX("search","s","ana")' 2>&1)
if [ "$OUT" = "s|1,3" ] || [ "$OUT" = "s|3,1" ]; then
  echo "  PASS: NiSuffixArray search (found both matches)"
  PASS=$((PASS+1))
else
  echo "  FAIL: NiSuffixArray search (expected 's|1,3' or 's|3,1', got '$OUT')"
  FAIL=$((FAIL+1))
fi

# NiWaveletTree: range rank
OUT=$($NIMM -x 'WRITE $NI_WAVELET("create","w",3,1,4,1,5,9,2,6,5,3,5),"|",$NI_WAVELET("min","w"),"|",$NI_WAVELET("max","w"),"|",$NI_WAVELET("range","w",0,10,5),"|",$NI_WAVELET("len","w")' 2>&1)
check "NiWaveletTree min/max/range/len" "w|1|9|3|11" "$OUT"

# NiKdTree: nearest neighbor
OUT=$($NIMM -x 'WRITE $NI_KDTREE("create","k",2),"|",$NI_KDTREE("insert","k",1,2,"a"),"|",$NI_KDTREE("insert","k",3,4,"b"),"|",$NI_KDTREE("nearest","k",2.5,3)' 2>&1)
check "NiKdTree insert/nearest" "k|1|1|b" "$OUT"

# NiRope: string concatenation/substring
OUT=$($NIMM -x 'WRITE $NI_ROPE("create","ro","Hello, "),"|",$NI_ROPE("create","r2","World!"),"|",$NI_ROPE("concat","ro","r2","r3"),"|",$NI_ROPE("tostring","r3"),"|",$NI_ROPE("substring","r3",0,5),"|",$NI_ROPE("len","r3")' 2>&1)
check "NiRope concat/substring/len" "ro|r2|r3|Hello, World!|Hello|13" "$OUT"

# NiMerkleTree: root hash and verify
OUT=$($NIMM -x 'WRITE $NI_MERKLE("create","mk","a","b","c","d"),"|",$NI_MERKLE("leafcount","mk"),"|",$NI_MERKLE("verify","mk",0,"a"),"|",$NI_MERKLE("verify","mk",3,"d"),"|",$NI_MERKLE("verify","mk",0,"x")' 2>&1)
check "NiMerkleTree leafcount/verify" "mk|4|1|1|0" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
