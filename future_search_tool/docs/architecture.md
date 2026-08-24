# FST Architecture — Algorithms + Data Structures = Programs

## Core Insight

NimM already has the building blocks. The challenge is composing them
into a coherent search tool.

## Algorithm ↔ Data Structure Mapping

| Algorithm | Data Structure | FST Use Case |
|---|---|---|
| BM25 scoring | Table[string, Table[string, int]] | Keyword search over globals |
| HNSW graph | Table[int, seq[float]] + Table[int, seq[int]] | Vector similarity search |
| RRF fusion | Table[string, float] | Hybrid keyword+vector search |
| Pattern matching | seq[PatternAtom] | Result filtering |
| mCollationCmp | seq[string] | Result ordering (M collation) |
| TSTART/TCOMMIT | TransactionLevel overlay | Atomic index updates |
| $ORDER | LMDB cursor | Index traversal |
| $PIECE | string ops | NLM data parsing |
| NiMap | Table[string, string] | Search result caching |
| NiSorted | sorted seq | Ranked result lists |

## Data Flow

```
NLM data (XML/MARC)
  → $PIECE/parse (string ops)
    → ^MESH/^CATLINE/^PUBMED (hierarchical globals)
      → BM25 index (Table[term, Table[docId, freq]])
      → HNSW index (Table[id, seq[float]])
        → search(query) → ranked results
          → $ORDER traversal → formatted output
```

## Implementation Strategy

### 1. Store: Hierarchical Globals
```
^MESH("D000001","name") = "Hypertension"
^MESH("D000001","scopeNote") = "Persistently high..."
^CATLINE("1234567","title") = "Journal of hypertension"
^PUBMED("12345678","title") = "Hypertension treatment..."
```
- Natural M data model
- Upsert via SET
- Traverse via $ORDER
- Persistent via LMDB

### 2. Index: BM25 + HNSW
```
^BM25("hypertension", "MESH", "D000001") = 3  ; term, type, id, freq
^BM25("treatment", "PUBMED", "12345678") = 2
```
- Store index in LMDB alongside data
- Update index on import (TSTART/TCOMMIT for atomicity)
- Search: iterate ^BM25 entries, compute scores

### 3. Search: BM25 + RRF
```
search("hypertension treatment"):
  1. Tokenize query → ["hypertension", "treatment"]
  2. For each term, look up ^BM25 entries
  3. Compute BM25 scores per document
  4. Rank by score
  5. Return top-K results
```

### 4. Link: ^LINK global
```
^LINK("MESH", "D000001", "PUBMED", "12345678") = "mesh_term"
^LINK("MESH", "D000001", "CATLINE", "1234567") = "subject"
```
- Explicit relationships between record types
- Traverse via $ORDER
- Query: "find all records linked to D000001"

### 5. Filter: Pattern Matching
```
; Find records matching pattern
FOR I=1:1:N SET R=$ORDER(^PUBMED("")) QUIT:R=""  DO
 . I ^PUBMED(R,"title")?1.A1"Hypertension" W R,!
```
- Use M's pattern matching for result filtering
- Combine with BM25 scores for ranking

### 6. Cache: NiMap
```
; Cache search results
SET ^CACHE("hypertension")=results
```
- Use NiMap for in-memory caching
- TTL-based invalidation

## Performance Characteristics

| Operation | Algorithm | Data Structure | Complexity |
|---|---|---|---|
| Index document | BM25 addDocument | Table[term, freq] | O(n) where n = tokens |
| Search | BM25 search | Table[docId, score] | O(d*t) where d = docs, t = terms |
| Vector search | HNSW search | Graph traversal | O(log n) average |
| Link traversal | $ORDER | LMDB cursor | O(k) where k = linked records |
| Pattern filter | Pattern match | String ops | O(m) where m = string length |

## Key Design Decisions

1. **Store in LMDB, index in memory** — LMDB for persistence, in-memory tables for speed
2. **Upsert semantics** — M's SET provides natural upsert
3. **$ORDER for traversal** — M's native cursor for index iteration
4. **TSTART/TCOMMIT for atomicity** — index updates are transactional
5. **Pattern matching for filtering** — M's native string matching
6. **mCollationCmp for ordering** — M's numeric-before-string collation

## What NimM Already Has

| Feature | Status | FST Use |
|---|---|---|
| BM25 scorer | ✅ Implemented | Keyword search |
| HNSW index | ✅ Implemented | Vector search |
| Hybrid search | ✅ Implemented | Combined search |
| LMDB storage | ✅ Implemented | Persistent storage |
| Transactions | ✅ Implemented | Atomic index updates |
| Pattern matching | ✅ Implemented | Result filtering |
| $ORDER | ✅ Implemented | Index traversal |
| $PIECE | ✅ Implemented | Data parsing |
| NiMap | ✅ Implemented | Result caching |
| mCollationCmp | ✅ Implemented | Result ordering |

## What Needs Building

| Feature | Effort | Purpose |
|---|---|---|
| NLM XML parser | Medium | Parse MeSH, CatLine, SerLine, PubMed |
| Index builder | Medium | Build BM25 index from globals |
| MCP search tools | Low | Expose search via MCP |
| $NI_SEARCH function | Low | Expose search via M code |
| Result formatter | Low | Format search results for display |

## Relationship Caching with NiMap

LMDB for persistence, NiMap for speed:

```
; Persistent storage (LMDB)
^LINK("MESH", "D000001", "PUBMED", "12345678") = "mesh_term"

; In-memory cache (NiMap) — loaded on startup
^NIMAP("link:MESH:D000001") = "PUBMED:12345678,CATLINE:1234567"
```

**Pattern:**
1. On import: write to LMDB (^LINK) AND NiMap cache
2. On search: look up NiMap first (fast), fall back to LMDB
3. On startup: load all ^LINK entries into NiMap

**Why NiMap fits:**
- Relationships are read-heavy, write-light (perfect for caching)
- NiMap is in-memory → O(1) lookups
- LMDB provides persistence and cross-process access
- NiMap provides speed for search operations

## Performance Scaling Analysis

### Data Sizes (NLM)

| Dataset | Records | Size | Relationships |
|---|---|---|---|
| MeSH Descriptors | ~30K | 313 MB | ~100K links |
| MeSH Qualifiers | ~80 | 291 KB | ~500 links |
| MeSH Supplements | ~250K | 786 MB | ~500K links |
| CatLine | ~20M | 5.1 GB | ~20M links |
| SerLine | ~300K | 626 MB | ~300K links |
| PubMed | ~36M | 1.4 GB (compressed) | ~100M links |
| **Total** | **~56M** | **~8 GB** | **~120M links** |

### Component Scaling

| Component | Current | At Scale (56M records) | Bottleneck |
|---|---|---|---|
| **NiMap cache** | ~10 MB | ~500 MB | Memory — acceptable |
| **BM25 index** | ~1 MB | ~50 GB | Disk — needs LMDB storage |
| **HNSW index** | ~10 MB | ~2 GB | Memory — acceptable |
| **LMDB lookups** | O(log n) | O(log n) | No degradation |
| **Search latency** | ~1ms | ~100ms | BM25 iteration |

### Scaling Strategies

**1. BM25 Index in LMDB (not in-memory)**
- Current: Table[term, Table[docId, freq]] in memory
- At scale: Store in LMDB with compound keys
- Key: `^BM25(term, docType, docId)` = frequency
- Lookup: O(log n) per term via LMDB B-tree

**2. NiMap Cache with LRU Eviction**
- Current: Load all relationships on startup
- At scale: LRU cache with configurable size
- Evict least-used entries when memory limit hit
- Fall back to LMDB for evicted entries

**3. HNSW Index Partitioning**
- Current: Single index for all vectors
- At scale: Partition by record type (MESH, PUBMED, etc.)
- Search each partition, merge results
- Reduces memory per partition

**4. Incremental Indexing**
- Current: Rebuild index on import
- At scale: Update index incrementally on import
- Use TSTART/TCOMMIT for atomic index updates
- Avoid full rebuilds

**5. Result Caching**
- Current: No caching
- At scale: Cache frequent queries in NiMap
- TTL-based invalidation
- LRU eviction when cache full

### Performance Projections

| Operation | Current (small) | At Scale (56M) | With optimizations |
|---|---|---|---|
| Import 1M records | ~10s | ~10s | ~10s (incremental) |
| BM25 search | ~1ms | ~100ms | ~10ms (LMDB index) |
| HNSW search | ~1ms | ~10ms | ~5ms (partitioned) |
| Link traversal | ~0.1ms | ~1ms | ~0.5ms (NiMap cache) |
| Full reindex | ~1min | ~10min | ~1min (incremental)

### Memory Budget

| Component | Small (1M) | Medium (10M) | Large (56M) |
|---|---|---|---|
| NiMap cache | 10 MB | 100 MB | 500 MB |
| BM25 in-memory | 1 MB | 10 MB | 50 GB (use LMDB) |
| HNSW index | 10 MB | 100 MB | 2 GB |
| LMDB overhead | 50 MB | 500 MB | 5 GB |
| **Total** | **71 MB** | **710 MB** | **~57 GB** |

**Recommendation:** For >10M records, move BM25 index to LMDB. For >50M records, partition HNSW index by record type.
