# hnsw.nim — HNSW vector index for nimm
# Implements Hierarchical Navigable Small World graph

import math
import tables
import sequtils
import algorithm
import std/random

type
  HNSWIndex* = ref object
    ## HNSW vector index
    dim*: int           # Vector dimension
    M*: int             # Max connections per node
    efConstruction*: int # Construction search width
    efSearch*: int      # Search width
    ml*: float          # Level assignment multiplier
    vectors*: Table[int, seq[float]]  # id -> vector
    neighbors*: Table[int, seq[int]]  # id -> neighbor ids
    maxLevel*: int
    entryPoint*: int

proc newHNSWIndex*(dim: int, M: int = 16, efConstruction: int = 200, efSearch: int = 100): HNSWIndex =
  new(result)
  result.dim = dim
  result.M = M
  result.efConstruction = efConstruction
  result.efSearch = efSearch
  result.ml = 1.0 / ln(float(M))
  result.vectors = initTable[int, seq[float]]()
  result.neighbors = initTable[int, seq[int]]()
  result.maxLevel = 0
  result.entryPoint = -1

proc cosineSimilarity*(a, b: seq[float]): float =
  ## Calculate cosine similarity between two vectors
  var dotProduct = 0.0
  var normA = 0.0
  var normB = 0.0
  
  for i in 0..<a.len:
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  
  if normA == 0 or normB == 0:
    return 0.0
  
  return dotProduct / (sqrt(normA) * sqrt(normB))

proc randomLevel*(index: HNSWIndex): int =
  ## Assign random level to new node
  var level = 0
  while rand(1.0) < 0.5 and level < 10:
    inc level
  return level

proc searchLevel*(index: HNSWIndex, query: seq[float], entryId: int, ef: int, level: int): seq[(int, float)] =
  ## Search for nearest neighbors at a given level
  var visited = initTable[int, bool]()
  var candidates: seq[(int, float)] = @[]
  var results: seq[(int, float)] = @[]
  
  # Start with entry point
  let dist = cosineSimilarity(query, index.vectors[entryId])
  candidates.add((entryId, dist))
  results.add((entryId, dist))
  visited[entryId] = true
  
  while candidates.len > 0:
    # Get closest candidate
    var minIdx = 0
    for i in 1..<candidates.len:
      if candidates[i][1] > candidates[minIdx][1]:
        minIdx = i
    let (cId, cDist) = candidates[minIdx]
    candidates.delete(minIdx)
    
    # Check if we should expand
    if results.len >= ef and cDist < results[^1][1]:
      break
    
    # Expand neighbors
    if cId in index.neighbors:
      for nId in index.neighbors[cId]:
        if nId notin visited:
          visited[nId] = true
          let nDist = cosineSimilarity(query, index.vectors[nId])
          
          if results.len < ef:
            candidates.add((nId, nDist))
            results.add((nId, nDist))
            results.sort(proc (a, b: (int, float)): int = cmp(b[1], a[1]))
          elif nDist > results[^1][1]:
            candidates.add((nId, nDist))
            results[^1] = (nId, nDist)
            results.sort(proc (a, b: (int, float)): int = cmp(b[1], a[1]))
  
  return results

proc insert*(index: var HNSWIndex, id: int, vector: seq[float]) =
  ## Insert a vector into the index
  if vector.len != index.dim:
    raise newException(ValueError, "Vector dimension mismatch")
  
  index.vectors[id] = vector
  
  if index.entryPoint == -1:
    index.entryPoint = id
    index.neighbors[id] = @[]
    return
  
  let level = index.randomLevel()
  var currentLevel = index.maxLevel
  var entryId = index.entryPoint
  
  # Search from top level to level+1
  while currentLevel > level:
    let results = index.searchLevel(vector, entryId, 1, currentLevel)
    if results.len > 0:
      entryId = results[0][0]
    dec currentLevel
  
  # Search from level to 0
  while currentLevel >= 0:
    let results = index.searchLevel(vector, entryId, index.efConstruction, currentLevel)
    
    # Select M nearest neighbors
    var neighbors: seq[int] = @[]
    for i in 0..<min(index.M, results.len):
      neighbors.add(results[i][0])
    
    # Add bidirectional connections
    index.neighbors[id] = neighbors
    for nId in neighbors:
      if nId in index.neighbors:
        index.neighbors[nId].add(id)
        if index.neighbors[nId].len > index.M:
          # Remove weakest connection
          var weakestIdx = 0
          var weakestDist = cosineSimilarity(vector, index.vectors[index.neighbors[nId][0]])
          for i in 1..<index.neighbors[nId].len:
            let dist = cosineSimilarity(vector, index.vectors[index.neighbors[nId][i]])
            if dist < weakestDist:
              weakestDist = dist
              weakestIdx = i
          index.neighbors[nId].delete(weakestIdx)
      else:
        index.neighbors[nId] = @[id]
    
    if results.len > 0:
      entryId = results[0][0]
    dec currentLevel
  
  if level > index.maxLevel:
    index.maxLevel = level
    index.entryPoint = id

proc search*(index: HNSWIndex, query: seq[float], topK: int = 10): seq[(int, float)] =
  ## Search for nearest neighbors
  if index.entryPoint == -1:
    return @[]
  
  var currentLevel = index.maxLevel
  var entryId = index.entryPoint
  
  # Search from top level to 1
  while currentLevel > 0:
    let results = index.searchLevel(query, entryId, 1, currentLevel)
    if results.len > 0:
      entryId = results[0][0]
    dec currentLevel
  
  # Search at level 0 with efSearch
  let results = index.searchLevel(query, entryId, index.efSearch, 0)
  
  # Return top K
  if results.len > topK:
    return results[0..<topK]
  return results
