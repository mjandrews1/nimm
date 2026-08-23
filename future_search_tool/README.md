# future_search_tool

Search and vector index infrastructure for NimM. Extracted from the nimm codebase.

## Modules

| Module | Purpose |
|---|---|
| `bm25.nim` | Okapi BM25 keyword scoring |
| `hnsw.nim` | Hierarchical Navigable Small World vector index |
| `hybrid_search.nim` | Hybrid search with Reciprocal Rank Fusion |
| `index_builder.nim` | Search index builder from LMDB data |
| `record_loader.nim` | Record loader for LMDB |

## Status

Extracted from nimm — not yet wired to any application. These modules were developed as infrastructure for a search tool (formerly YakSearch) and are preserved here for future development.

## Dependencies

- Nim >= 2.2.0
- LMDB (via nimble: `nimble install lmdb`)

## Structure

```
future_search_tool/
├── src/
│   ├── bm25.nim
│   ├── hnsw.nim
│   ├── hybrid_search.nim
│   ├── index_builder.nim
│   └── record_loader.nim
├── README.md
└── future_search_tool.nimble
```
