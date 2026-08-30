# fst_mcp.nim — MCP tool handlers for FST search
# Registers search_index / search_keyword / search_vector / search_hybrid
# against the MCP server, backed by a SearchEngine.

import json
import ../../mcp_server
import fst_core

proc parseVector(params: JsonNode): seq[float] =
  result = @[]
  if params.hasKey("vector") and params["vector"].kind == JArray:
    for x in params["vector"]:
      result.add(x.getFloat())

proc toResultsJson(results: seq[(string, float)]): JsonNode =
  var arr = newJArray()
  for (docId, score) in results:
    arr.add(%*{"docId": docId, "score": score})
  return arr

proc registerSearchTools*(mcp: var MCPServer, engine: SearchEngine) =
  ## Register the FST search tools on `mcp`, backed by `engine`.

  mcp.registerTool("search_index",
    "Index a document into the FST search engine (keyword, optional vector)",
    %*{
      "type": "object",
      "properties": {
        "docId": {"type": "string", "description": "Document identifier"},
        "text": {"type": "string", "description": "Document text"},
        "vector": {"type": "array", "items": {"type": "number"}, "description": "Optional embedding vector"}
      },
      "required": ["docId", "text"]
    },
    proc(params: JsonNode): JsonNode =
      let docId = params["docId"].getStr()
      let text = params["text"].getStr()
      let vector = parseVector(params)
      try:
        engine.indexDocument(docId, text, vector)
        return %*{"indexed": docId, "docCount": engine.docCount()}
      except:
        return %*{"error": getCurrentExceptionMsg()}
  )

  mcp.registerTool("search_keyword",
    "BM25 keyword search over indexed documents",
    %*{
      "type": "object",
      "properties": {
        "query": {"type": "string", "description": "Search query"},
        "topK": {"type": "integer", "description": "Max results (default 10)"}
      },
      "required": ["query"]
    },
    proc(params: JsonNode): JsonNode =
      let query = params["query"].getStr()
      let topK = if params.hasKey("topK"): params["topK"].getInt() else: 10
      try:
        return %*{"results": toResultsJson(engine.keywordSearch(query, topK))}
      except:
        return %*{"error": getCurrentExceptionMsg()}
  )

  mcp.registerTool("search_vector",
    "HNSW vector similarity search over indexed documents",
    %*{
      "type": "object",
      "properties": {
        "vector": {"type": "array", "items": {"type": "number"}, "description": "Query embedding vector"},
        "topK": {"type": "integer", "description": "Max results (default 10)"}
      },
      "required": ["vector"]
    },
    proc(params: JsonNode): JsonNode =
      let vector = parseVector(params)
      let topK = if params.hasKey("topK"): params["topK"].getInt() else: 10
      try:
        return %*{"results": toResultsJson(engine.vectorSearch(vector, topK))}
      except:
        return %*{"error": getCurrentExceptionMsg()}
  )

  mcp.registerTool("search_hybrid",
    "Hybrid BM25 + vector search with reciprocal-rank fusion",
    %*{
      "type": "object",
      "properties": {
        "query": {"type": "string", "description": "Keyword query"},
        "vector": {"type": "array", "items": {"type": "number"}, "description": "Query embedding vector"},
        "topK": {"type": "integer", "description": "Max results (default 10)"}
      },
      "required": ["query", "vector"]
    },
    proc(params: JsonNode): JsonNode =
      let query = params["query"].getStr()
      let vector = parseVector(params)
      let topK = if params.hasKey("topK"): params["topK"].getInt() else: 10
      try:
        return %*{"results": toResultsJson(engine.hybridSearch(query, vector, topK))}
      except:
        return %*{"error": getCurrentExceptionMsg()}
  )
