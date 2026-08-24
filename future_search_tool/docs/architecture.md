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
