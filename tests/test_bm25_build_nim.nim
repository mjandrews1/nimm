# test_bm25_build_nim.nim — Nim buildIndex (global_bm25.nim) parity with
# bm25idx.m COMMON tokenization and index layout.
#
# Run: nim c -r tests/test_bm25_build_nim.nim

import ../globals
import ../future_search_tool/src/global_bm25

proc main() =
  echo "Nim BM25 buildIndex parity test..."

  # --- tokenizeDoc matches COMMON: lowercase + P-set -> space, split on ' ' ---
  var toks = tokenizeDoc("Hypertension, RENAL")
  assert toks == @["hypertension", "renal"], "punct+case: got " & $toks

  # '\n' and '\r' are NOT separators (P set lacks them), unlike tokenizeQuery.
  toks = tokenizeDoc("a\nb")
  assert toks == @["a\nb"], "newline kept: got " & $toks
  toks = tokenizeDoc("a\rb")
  assert toks == @["a\rb"], "CR kept: got " & $toks

  # Punctuation collapse into empty splits is dropped.
  toks = tokenizeDoc("foo...bar")
  assert toks == @["foo", "bar"], "repeated punct: got " & $toks

  # --- buildIndex over an in-memory global ---
  var g = newGlobals("")
  g.set("^MESH", @["D1", "name"], "Hypertension")
  g.set("^MESH", @["D1", "scopeNote"], "High blood pressure")
  g.set("^MESH", @["D2", "name"], "Hypertension, Renal")
  g.set("^MESH", @["D2", "scopeNote"], "Kidney disease")

  let res = g.buildIndex("MESH", "^MESH", "name^scopeNote")
  assert res.docs == 2, "docs should be 2, got " & $res.docs
  assert res.tokens == 8, "tokens should be 8, got " & $res.tokens

  # tf: "hypertension" appears once in D1, once in D2.
  assert g.get("^BM25", @["hypertension", "MESH", "D1"]) == "1"
  assert g.get("^BM25", @["hypertension", "MESH", "D2"]) == "1"
  # df: "hypertension" in 2 docs; "kidney" in 1 doc.
  assert g.get("^BM25DF", @["hypertension", "MESH"]) == "2"
  assert g.get("^BM25DF", @["kidney", "MESH"]) == "1"
  # doc lengths: D1 = 4 tokens, D2 = 4 tokens.
  assert g.get("^BM25LEN", @["MESH", "D1"]) == "4"
  assert g.get("^BM25LEN", @["MESH", "D2"]) == "4"
  # meta: N=2, avgdl = (4+4)/2 = 4.0.
  assert g.get("^BM25META", @["MESH", "N"]) == "2"
  assert g.get("^BM25META", @["MESH", "avgdl"]) == "4.00"

  # --- idempotent re-run: no double-counting ---
  let res2 = g.buildIndex("MESH", "^MESH", "name^scopeNote")
  assert res2.docs == 2 and res2.tokens == 8, "re-run must be idempotent"
  assert g.get("^BM25DF", @["hypertension", "MESH"]) == "2", "df unchanged on re-run"

  # --- scoreGlobal agrees with the freshly built index ---
  assert g.scoreGlobal("MESH", "D1", "hypertension") > 0.0

  echo "  tokenizeDoc == COMMON; buildIndex tf/df/len/meta correct"
  echo "Nim BM25 buildIndex parity test passed!"

main()
