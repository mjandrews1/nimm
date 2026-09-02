# test_ni_sql.nim — mirror of formal/query_semantics.dfy (#462, M1).
#
# Part 1 re-implements the model's ScanAll/Take/PointLookup as pure Nim
# functions and asserts soundness, completeness, order-preservation, LIMIT
# prefix/bound, and point-lookup count — the same properties the Dafny lemmas
# prove (using mCollationCmp so the "free ORDER BY" claim is over real M
# collation).
#
# Part 2 drives the actual executor (parseSelect + planSelect + execSelect via
# niSql) over an in-memory store: point lookup, range scans, natural ORDER BY,
# LIMIT, SELECT *, the ^LINK traversal that motivates the layer, and the M1
# error gates.
#
# Run: nim c -r tests/test_ni_sql.nim

import algorithm
import strutils
import sets
import ../globals
import ../storage/key_encoding
import ../future_search_tool/src/sql_select

proc sortedKeys(keys: seq[string]): bool =
  for i in 0 ..< keys.len:
    for j in (i + 1) ..< keys.len:
      if mCollationCmp(keys[i], keys[j]) >= 0:
        return false
  return true

proc inRange(k, low, high: string, loInc, hiInc: bool): bool =
  result = true
  if low.len > 0:
    let c = mCollationCmp(k, low)
    if loInc and c < 0: result = false
    if not loInc and c <= 0: result = false
  if high.len > 0:
    let c = mCollationCmp(k, high)
    if hiInc and c > 0: result = false
    if not hiInc and c >= 0: result = false

proc scanAll(keys: seq[string], low, high: string, loInc, hiInc: bool): seq[string] =
  result = @[]
  for k in keys:
    if inRange(k, low, high, loInc, hiInc):
      result.add(k)

proc takeP(keys: seq[string], k: int): seq[string] =
  result = @[]
  for i in 0 ..< min(k, keys.len):
    result.add(keys[i])

proc main() =
  echo "query_semantics mirror test..."

  # --- Part 1: pure mirrors of the Dafny lemmas ---
  var ks = @["d1", "d10", "d2", "d3", "d30"]
  ks.sort(proc(a, b: string): int = mCollationCmp(a, b))
  assert sortedKeys(ks), "input is sorted in M collation"

  let lo = "d2"
  let hi = "d3"
  let r = scanAll(ks, lo, hi, true, true)

  # ScanAllSound — every emitted key satisfies the range predicate.
  for k in r:
    assert inRange(k, lo, hi, true, true), "soundness: " & k

  # ScanAllComplete — every in-range key is emitted.
  for k in ks:
    if inRange(k, lo, hi, true, true):
      assert k in r, "completeness: " & k

  # ScanAllPreservesOrder — free ORDER BY.
  assert sortedKeys(r), "scan preserves order"

  # TakeIsPrefix + TakeBounded.
  let t = takeP(ks, 3)
  assert t.len <= 3, "take bounded by k"
  assert t.len <= ks.len, "take <= input length"
  for i in 0 ..< t.len:
    assert t[i] == ks[i], "take is a prefix"

  # PointLookupCount — one row iff present.
  var s = initHashSet[string]()
  s.incl("d1")
  s.incl("d2")
  proc pointLookup(k: string): int = (if k in s: 1 else: 0)
  assert pointLookup("d1") == 1, "present -> 1"
  assert pointLookup("d2") == 1, "present -> 1"
  assert pointLookup("zz") == 0, "absent -> 0"

  echo "  model mirrors hold"

  # --- Part 2: executor over an in-memory store ---
  echo "--- executor tests ---"
  var g = newGlobals("")
  g.set("^BM25", @["hello", "MESH", "d1"], "1")
  g.set("^BM25", @["hello", "MESH", "d2"], "3")
  g.set("^BM25", @["hello", "MESH", "d10"], "2")
  g.set("^BM25", @["hello", "CATLINE", "c1"], "1")
  g.set("^LINK", @["MESH", "D000001", "PUBMED", "100"], "mesh_term")
  g.set("^LINK", @["MESH", "D000001", "PUBMED", "200"], "mesh_term")
  g.set("^LINK", @["MESH", "D000001", "CATLINE", "C1"], "mesh_term")

  # Point lookup.
  assert g.niSql("SELECT tf FROM bm25 WHERE term='hello' AND src='MESH' AND doc_id='d1'") == "1\n",
    "point lookup"

  # Full scan in natural order (free ORDER BY on doc_id).
  let all = g.niSql("SELECT doc_id, tf FROM bm25 WHERE term='hello' AND src='MESH' ORDER BY doc_id")
  assert all == "d1\t1\nd10\t2\nd2\t3\n", "full scan in M collation order, got:\n" & all

  # SELECT *.
  let star = g.niSql("SELECT * FROM bm25 WHERE term='hello' AND src='MESH' AND doc_id='d2'")
  assert star == "hello\tMESH\td2\t3\n", "SELECT * point, got:\n" & star

  # Range >= (M collation: d1 < d10 < d2).
  assert g.niSql("SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' AND doc_id>='d2'") == "d2\n",
    "range >= picks d2 only"

  # Range <= stops early.
  assert g.niSql("SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' AND doc_id<='d10'") == "d1\nd10\n",
    "range <= stops at d10"

  # LIMIT is a prefix.
  assert g.niSql("SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' LIMIT 2") == "d1\nd10\n",
    "limit prefix"

  # The ^LINK traversal that motivates the layer.
  let link = g.niSql("SELECT to_id FROM link WHERE from_type='MESH' AND from_id='D000001' AND to_type='PUBMED' ORDER BY to_id")
  assert link == "100\n200\n", "link traversal, got:\n" & link

  # Error gates.
  proc expectErr(sql: string, needle: string) =
    var caught = false
    try:
      discard g.niSql(sql)
    except SqlError as e:
      caught = true
      assert needle in e.msg, "expected '" & needle & "' in error, got: " & e.msg
    assert caught, "expected SqlError for: " & sql

  expectErr("SELECT x FROM bm25", "unknown column")
  expectErr("SELECT doc_id FROM nope", "unknown table")
  expectErr("SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' ORDER BY doc_id DESC", "DESC")
  expectErr("SELECT doc_id FROM bm25 WHERE src='MESH'", "without binding term")
  expectErr("SELECT doc_id FROM bm25 WHERE term='hello' AND tf='1'", "value-column")

  echo "  executor + error gates hold"
  echo "query_semantics mirror test passed!"

main()
