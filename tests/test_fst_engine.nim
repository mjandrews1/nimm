# test_fst_engine.nim — FST SearchEngine + MCP tool handlers
# Mirrors FST Phase 1 (#453): wires bm25/hnsw/hybrid_search behind a SearchEngine.
#
# Run: nim c -r tests/test_fst_engine.nim

import json
import tables
import ../mcp_server
import ../future_search_tool/src/fst_core
import ../future_search_tool/src/fst_mcp

proc hasDoc(results: seq[(string, float)], docId: string): bool =
  for (d, _) in results:
    if d == docId: return true
  return false

proc main() =
  echo "FST SearchEngine + MCP tool test (Phase 1)..."

  # --- SearchEngine core ---
  var engine = newSearchEngine(dim = 3, rrfK = 60)
  engine.indexDocument("d1", "hello world", @[1.0, 0.0, 0.0])
  engine.indexDocument("d2", "hello there", @[1.0, 0.1, 0.0])
  engine.indexDocument("d3", "goodbye universe", @[0.0, 0.0, 1.0])
  assert engine.docCount() == 3, "docCount should be 3"

  # Keyword search: "hello" matches d1 and d2 only.
  let kw = engine.keywordSearch("hello")
  assert kw.len == 2, "keyword search should return d1+d2, got " & $kw.len
  assert kw.hasDoc("d1") and kw.hasDoc("d2"), "keyword search should include d1 and d2"
  assert not kw.hasDoc("d3"), "keyword search should exclude d3"

  # Vector search: [1,0,0] is closest to d1.
  let vec = engine.vectorSearch(@[1.0, 0.0, 0.0])
  assert vec.len >= 1, "vector search should return results"
  assert vec[0][0] == "d1", "vector search top hit should be d1, got " & vec[0][0]

  # Hybrid search: d1 matches both keyword and vector, so it should rank top.
  let hyb = engine.hybridSearch("hello", @[1.0, 0.0, 0.0])
  assert hyb.len >= 1, "hybrid search should return results"
  assert hyb[0][0] == "d1", "hybrid search top hit should be d1, got " & hyb[0][0]

  echo "  SearchEngine: index / keyword / vector / hybrid all correct"

  # --- MCP tool handlers ---
  var mcp = newMCPServer(port = 0)
  var mcpEngine = newSearchEngine(dim = 3)
  registerSearchTools(mcp, mcpEngine)

  assert "search_index" in mcp.tools, "search_index should be registered"
  assert "search_keyword" in mcp.tools, "search_keyword should be registered"
  assert "search_vector" in mcp.tools, "search_vector should be registered"
  assert "search_hybrid" in mcp.tools, "search_hybrid should be registered"

  # Index via the MCP tool, then keyword-search via the MCP tool.
  let idxResp = mcp.tools["search_index"](%*{"docId": "x1", "text": "alpha beta gamma"})
  assert idxResp["docCount"].getInt() == 1, "search_index should report docCount 1"

  let kwResp = mcp.tools["search_keyword"](%*{"query": "alpha"})
  assert kwResp.hasKey("results"), "search_keyword should return results"
  assert kwResp["results"].len == 1, "search_keyword should find x1"
  assert kwResp["results"][0]["docId"].getStr() == "x1", "search_keyword should return x1"

  echo "  MCP tools: search_index / search_keyword handlers correct"
  echo "FST Phase 1 test passed!"

main()
