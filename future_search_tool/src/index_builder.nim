# index_builder.nim — Index builder for nimm
# Builds search indexes from data

import bm25
import hnsw
import storage/lmdb_store
import strutils
import json

type
  IndexBuilder* = ref object
    ## Index builder
    store*: LmdbStore
    bm25*: BM25Scorer
    hnsw*: HNSWIndex

proc newIndexBuilder*(store: LmdbStore, dim: int = 384): IndexBuilder =
  result.store = store
  result.bm25 = newBM25Scorer()
  result.hnsw = newHNSWIndex(dim)

proc addDocument*(builder: var IndexBuilder, docId: string, text: string, vector: seq[float]) =
  ## Add a document to the index
  builder.bm25.addDocument(docId, text)
  var id = 0
  try:
    id = parseInt(docId)
  except:
    id = builder.hnsw.vectors.len
  builder.hnsw.insert(id, vector)

proc buildFromStore*(builder: var IndexBuilder, prefix: string = "^DATA") =
  ## Build index from LMDB store
  let keys = builder.store.listKeys(prefix)
  for key in keys:
    let text = builder.store.get(key)
    if text.len > 0:
      builder.addDocument(key, text, @[])

proc search*(builder: IndexBuilder, query: string, vector: seq[float], topK: int = 10): seq[(string, float)] =
  ## Search the index
  let bm25Results = builder.bm25.search(query, topK * 2)
  let hnswResults = if vector.len > 0:
    builder.hnsw.search(vector, topK * 2)
  else:
    @[]
  
  # Combine results
  var scores: seq[(string, float)] = @[]
  for (docId, score) in bm25Results:
    scores.add((docId, score))
  
  # Sort by score
  scores.sort(proc (a, b: (string, float)): int = cmp(b[1], a[1]))
  
  if scores.len > topK:
    return scores[0..<topK]
  return scores
