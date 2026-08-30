# fst_core.nim — FST search engine core
# A single SearchEngine type wrapping BM25 keyword scoring and HNSW vector
# indexing, exposing keyword / vector / hybrid (RRF fusion) search.

import tables
import algorithm
import bm25
import hnsw

type
  SearchEngine* = ref object
    bm25*: BM25Scorer
    hnsw*: HNSWIndex
    documents*: Table[string, string]  # docId -> text
    docOf*: Table[int, string]         # HNSW int id -> docId
    nextVecId*: int
    rrfK*: int                         # reciprocal-rank-fusion constant

proc newSearchEngine*(dim: int = 384, rrfK: int = 60): SearchEngine =
  new(result)
  result.bm25 = newBM25Scorer()
  result.hnsw = newHNSWIndex(dim)
  result.documents = initTable[string, string]()
  result.docOf = initTable[int, string]()
  result.nextVecId = 0
  result.rrfK = rrfK

proc docCount*(engine: SearchEngine): int = engine.documents.len

proc indexDocument*(engine: SearchEngine, docId: string, text: string, vector: seq[float] = @[]) =
  ## Index a document. `vector` is optional; when non-empty the document is
  ## also added to the HNSW vector index.
  engine.documents[docId] = text
  engine.bm25.addDocument(docId, text)
  if vector.len > 0:
    let id = engine.nextVecId
    engine.nextVecId += 1
    engine.docOf[id] = docId
    engine.hnsw.insert(id, vector)

proc keywordSearch*(engine: SearchEngine, query: string, topK: int = 10): seq[(string, float)] =
  engine.bm25.search(query, topK)

proc vectorSearch*(engine: SearchEngine, query: seq[float], topK: int = 10): seq[(string, float)] =
  ## Vector similarity search; results are mapped back to docIds.
  let raw = engine.hnsw.search(query, topK)
  result = @[]
  for (id, score) in raw:
    let docId = if id in engine.docOf: engine.docOf[id] else: $id
    result.add((docId, score))

proc hybridSearch*(engine: SearchEngine, query: string, vector: seq[float], topK: int = 10): seq[(string, float)] =
  ## Hybrid search: reciprocal-rank-fuse the BM25 and HNSW result lists.
  let bm = engine.bm25.search(query, topK * 2)
  let vec = engine.hnsw.search(vector, topK * 2)
  var scores = initTable[string, float]()
  for i, (docId, _) in bm:
    scores[docId] = scores.getOrDefault(docId, 0.0) + 1.0 / (float(engine.rrfK) + float(i + 1))
  for i, (id, _) in vec:
    let docId = if id in engine.docOf: engine.docOf[id] else: $id
    scores[docId] = scores.getOrDefault(docId, 0.0) + 1.0 / (float(engine.rrfK) + float(i + 1))
  result = @[]
  for docId, score in scores:
    result.add((docId, score))
  result.sort(proc (a, b: (string, float)): int = cmp(b[1], a[1]))
  if result.len > topK:
    result = result[0 ..< topK]
