# hybrid_search.nim — Hybrid search with Reciprocal Rank Fusion
# Combines BM25 keyword search and HNSW vector search

import bm25
import hnsw
import tables

type
  HybridSearch* = ref object
    ## Hybrid search combining BM25 and HNSW
    bm25*: BM25Scorer
    hnsw*: HNSWIndex
    k*: int  # RRF parameter

proc newHybridSearch*(dim: int, k: int = 60): HybridSearch =
  result.bm25 = newBM25Scorer()
  result.hnsw = newHNSWIndex(dim)
  result.k = k

proc addDocument*(search: var HybridSearch, docId: string, text: string, vector: seq[float]) =
  ## Add a document with both text and vector
  search.bm25.addDocument(docId, text)
  var id = 0
  try:
    id = parseInt(docId)
  except:
    id = search.hnsw.vectors.len
  search.hnsw.insert(id, vector)

proc rrfScore*(search: HybridSearch, bm25Results: seq[(string, float)], hnswResults: seq[(int, float)]): seq[(string, float)] =
  ## Calculate Reciprocal Rank Fusion score
  var scores: Table[string, float] = initTable[string, float]()
  
  # BM25 scores
  for i, (docId, _) in bm25Results:
    let rank = i + 1
    scores[docId] = scores.getOrDefault(docId, 0.0) + 1.0 / (float(search.k) + float(rank))
  
  # HNSW scores
  for i, (id, _) in hnswResults:
    let docId = $id
    let rank = i + 1
    scores[docId] = scores.getOrDefault(docId, 0.0) + 1.0 / (float(search.k) + float(rank))
  
  # Sort by score
  var result: seq[(string, float)] = @[]
  for docId, score in scores:
    result.add((docId, score))
  result.sort(proc (a, b: (string, float)): int = cmp(b[1], a[1]))
  
  return result

proc search*(search: HybridSearch, query: string, vector: seq[float], topK: int = 10): seq[(string, float)] =
  ## Perform hybrid search
  let bm25Results = search.bm25.search(query, topK * 2)
  let hnswResults = search.hnsw.search(vector, topK * 2)
  
  return search.rrfScore(bm25Results, hnswResults)
