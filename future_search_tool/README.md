# future_search_tool

Search and vector index infrastructure for NimM. Extracted from the nimm codebase.

## Modules

| Module | Purpose |
|---|---|
| `bm25.nim` | Okapi BM25 keyword scoring |
| `hnsw.nim` | Hierarchical Navigable Small World vector index |
| `hybrid_search.nim` | Hybrid search with Reciprocal Rank Fusion |
| `fst_core.nim` | `SearchEngine` — keyword/vector/hybrid search over indexed docs |
| `fst_mcp.nim` | MCP tool handlers (`search_index`/`search_keyword`/`search_vector`/`search_hybrid`) |
| `index_builder.nim` | Search index builder from LMDB data |
| `record_loader.nim` | Record loader for LMDB |

## Status

`bm25.nim`/`hnsw.nim`/`hybrid_search.nim` are wired into the main binary via
`fst_core.nim` (`SearchEngine`) and exposed through the MCP server by
`fst_mcp.nim` (FST Phase 1, #453). `index_builder.nim`/`record_loader.nim`
remain infrastructure (not yet wired to an application).

The modules compile under Nim 2.2 (fixes applied: `log`→`ln`,
`import std/random`/`algorithm`, missing `new(result)` in the constructors).
The RRF fusion path is exercised by `tests/test_hybrid_rrf.nim`; the SearchEngine
and MCP handlers by `tests/test_fst_engine.nim`.

## Dependencies

- Nim >= 2.2.0
- LMDB (via nimble: `nimble install lmdb`) — only for `index_builder.nim`/`record_loader.nim`

## Structure

```
future_search_tool/
├── src/
│   ├── bm25.nim
│   ├── hnsw.nim
│   ├── hybrid_search.nim
│   ├── fst_core.nim
│   ├── fst_mcp.nim
│   ├── index_builder.nim
│   └── record_loader.nim
├── README.md
└── future_search_tool.nimble
```
