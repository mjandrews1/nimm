# FST (Future Search Tool) — Design Document

## Problem Statement

NimM has persistent storage (LMDB) and a rich data model (hierarchical globals),
but no way to search across data. Users need:
- **Keyword search**: find records matching text queries
- **Semantic search**: find records similar to a query vector
- **Hybrid search**: combine keyword + semantic for best results

## Use Cases

| Use Case | Domain | Example |
|---|---|---|
| Patient record search | Healthcare | "Find patients with hypertension and diabetes" |
| Transaction lookup | Banking | "Find all transactions > $1000 last month" |
| Bibliographic search | Libraries | "Find books about MUMPS published after 2000" |
| Code search | Development | "Find routines that call $ORDER" |
| Log analysis | Operations | "Find error entries in the last hour" |

## Architecture

### Data Flow
```
Source data (globals, files, CSV, JSON)
  → Record Loader (parse and index)
    → BM25 Indexer (keyword tokens)
    → HNSW Indexer (vector embeddings)
      → Hybrid Search (RRF fusion)
        → Results (ranked list)
```

### Integration Points
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  M Code     │     │  MCP Server │     │  CLI Tool   │
│  $NI_SEARCH │     │  search_*   │     │  fst search │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                    ┌──────▼──────┐
                    │  FST Core   │
                    │  (Nim lib)  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │    LMDB     │
                    └─────────────┘
```

## Module Design

### fst_core.nim — Core search engine
```nim
type
  SearchEngine* = ref object
    bm25: BM25Scorer
    hnsw: HNSWIndex
    store: ptr LmdbStore  # shared with NimM globals

proc indexGlobal*(engine: var SearchEngine, name: string)
proc searchText*(engine: SearchEngine, query: string, topK: int): seq[SearchResult]
proc searchVector*(engine: SearchEngine, query: seq[float], topK: int): seq[SearchResult]
proc searchHybrid*(engine: SearchEngine, query: string, vector: seq[float], topK: int): seq[SearchResult]
```

### fst_indexer.nim — Index builder
```nim
proc indexGlobals*(engine: var SearchEngine, prefix: string = "^")
proc indexFile*(engine: var SearchEngine, path: string)
proc indexDirectory*(engine: var SearchEngine, dir: string)
```

### fst_mcp.nim — MCP tool handlers
```nim
proc registerSearchTools*(server: var MCPServer, engine: var SearchEngine)
# Tools: search_index, search_query, search_vector, index_global, index_file
```

### fst_m.nim — M intrinsic functions
```nim
# $NI_SEARCH(query, [topK]) — keyword search
# $NI_SEARCH_VECTOR(vector, [topK]) — vector search
# $NI_SEARCH_HYBRID(query, vector, [topK]) — hybrid search
# $NI_INDEX(global) — index a global
```

## Existing Modules — What to Keep/Modify/Discard

| Module | Decision | Reason |
|---|---|---|
| `bm25.nim` | **Keep** — solid BM25 implementation | Works correctly, good API |
| `hnsw.nim` | **Keep** — working HNSW index | Correct algorithm, good API |
| `hybrid_search.nim` | **Keep** — RRF fusion | Clean implementation |
| `index_builder.nim` | **Modify** — needs LMDB integration | Currently uses LmdbStore directly, needs to work with NimM's globals |
| `record_loader.nim` | **Keep** — useful for data import | CSV/JSON/text loading |

## Integration with NimM

### Option A: Shared LMDB
FST reads from the same LMDB database as NimM globals. Indexes stored in separate LMDB DBI.

**Pros:** No data duplication, real-time indexing
**Cons:** Coupled to NimM's storage model

### Option B: Separate index
FST maintains its own index files, separate from NimM globals.

**Pros:** Independent, can index external data
**Cons:** Data duplication, sync issues

**Recommendation:** Option A — shared LMDB with separate index DBI.

## Naming

| Option | Pros | Cons |
|---|---|---|
| `fst` | Short, memorable | Generic |
| `nimm-search` | Clear ownership | Long |
| `nsearch` | Short, M-style | Conflicts with Nim |
| `yaksearch` | Brand continuity | Tied to old project |

**Recommendation:** `fst` (Future Search Tool) — short, memorable, no conflicts.

## Implementation Phases

### Phase 1: Core search (MCP tools)
- Move bm25.nim, hnsw.nim, hybrid_search.nim to src/fst/
- Create fst_core.nim with SearchEngine type
- Create fst_mcp.nim with MCP tool handlers
- Register search tools in main.nim
- Test: index globals, search via MCP

### Phase 2: M intrinsic functions
- Add $NI_SEARCH, $NI_SEARCH_VECTOR, $NI_SEARCH_HYBRID
- Add $NI_INDEX to index globals from M code
- Test: search from M code

### Phase 3: Advanced features
- Incremental indexing (update index on global write)
- Vector embeddings (integrate with embedding API)
- Search result highlighting
- Faceted search

## Testing

- Unit tests for BM25, HNSW, hybrid search
- Integration tests: index globals, search, verify results
- MCP tool tests: search_index, search_query
- Performance benchmarks: index time, search latency
