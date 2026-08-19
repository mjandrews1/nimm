# bm25.nim — BM25 keyword scorer for nimm
# Implements Okapi BM25 scoring algorithm

import math
import tables
import strutils

type
  BM25Scorer* = ref object
    ## BM25 keyword scorer
    k1*: float  # Term frequency saturation parameter
    b*: float   # Document length normalization parameter
    docCount*: int
    avgDocLen*: float
    docFreq*: Table[string, int]  # term -> number of documents containing term
    docLens*: Table[string, int]  # docId -> document length
    termFreqs*: Table[string, Table[string, int]]  # docId -> (term -> frequency)

proc newBM25Scorer*(k1: float = 1.2, b: float = 0.75): BM25Scorer =
  result.k1 = k1
  result.b = b
  result.docCount = 0
  result.avgDocLen = 0.0
  result.docFreq = initTable[string, int]()
  result.docLens = initTable[string, int]()
  result.termFreqs = initTable[string, Table[string, int]]()

proc addDocument*(scorer: var BM25Scorer, docId: string, text: string) =
  ## Add a document to the scorer
  let tokens = text.toLowerAscii.split({' ', '\t', '\n', '\r', ',', '.', '!', '?', ';', ':', '(', ')', '[', ']', '{', '}', '"', '\''})
  var termFreq = initTable[string, int]()
  
  for token in tokens:
    let t = token.strip()
    if t.len > 0:
      termFreq[t] = termFreq.getOrDefault(t, 0) + 1
  
  # Update document frequency
  for term in termFreq.keys:
    scorer.docFreq[term] = scorer.docFreq.getOrDefault(term, 0) + 1
  
  # Store term frequencies
  scorer.termFreqs[docId] = termFreq
  scorer.docLens[docId] = tokens.len
  scorer.docCount += 1
  
  # Update average document length
  var totalLen = 0
  for len in scorer.docLens.values:
    totalLen += len
  scorer.avgDocLen = float(totalLen) / float(scorer.docCount)

proc score*(scorer: BM25Scorer, docId: string, query: string): float =
  ## Calculate BM25 score for a document against a query
  if docId notin scorer.termFreqs:
    return 0.0
  
  let docLen = scorer.docLens[docId]
  let termFreq = scorer.termFreqs[docId]
  let queryTerms = query.toLowerAscii.split({' ', '\t', '\n', '\r'})
  
  var totalScore = 0.0
  
  for term in queryTerms:
    let t = term.strip()
    if t.len == 0:
      continue
    
    let tf = termFreq.getOrDefault(t, 0)
    let df = scorer.docFreq.getOrDefault(t, 0)
    let n = scorer.docCount
    
    if df == 0:
      continue
    
    # IDF: log((N - n + 0.5) / (n + 0.5) + 1.0)
    let idf = log((float(n) - float(df) + 0.5) / (float(df) + 0.5) + 1.0)
    
    # TF normalization
    let tfNorm = (float(tf) * (scorer.k1 + 1.0)) / (float(tf) + scorer.k1 * (1.0 - scorer.b + scorer.b * float(docLen) / scorer.avgDocLen))
    
    totalScore += idf * tfNorm
  
  return totalScore

proc search*(scorer: BM25Scorer, query: string, topK: int = 10): seq[(string, float)] =
  ## Search for documents matching query
  var scores: seq[(string, float)] = @[]
  
  for docId in scorer.termFreqs.keys:
    let s = scorer.score(docId, query)
    if s > 0:
      scores.add((docId, s))
  
  # Sort by score descending
  scores.sort(proc (a, b: (string, float)): int = cmp(b[1], a[1]))
  
  # Return top K
  if scores.len > topK:
    return scores[0..<topK]
  return scores
