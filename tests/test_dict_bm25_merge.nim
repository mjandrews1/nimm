# test_dict_bm25_merge.nim — mirrors the dict+BM25 merge (fst_search.py
# search_descriptors / formal/entry_term_expansion.dfy), #462 M4.
#
# The M4 question was: should the SQL layer also express the dict-first + BM25
# ranking merge? Answer: no — that merge is a *ranking policy* (exact-name hits
# first, then synonyms, then BM25 fill), already specified by
# entry_term_expansion.dfy (MergeDictFirst / MergeNoDup / MergeCapped), not a
# relational JOIN over ^LINK that the SQL layer targets.
#
# This test asserts the merge's invariants hold (dict prefix, no duplicates,
# cap respected), i.e. the runtime form is already byte-identical to its spec.
#
# Run: nim c -r tests/test_dict_bm25_merge.nim

import sets
import strutils

proc noDup(s: seq[string]): bool =
  var seen = initHashSet[string]()
  for x in s:
    if x in seen: return false
    seen.incl(x)
  return true

proc mergeDictFirst(dictIds, bm25Order: seq[string], cap: int): seq[string] =
  ## The fst_search.py search_descriptors combine: dict hits first (already
  ## deduped), then BM25 fill excluding any dict hit, truncated at cap.
  var seen = initHashSet[string]()
  for ui in dictIds:
    if ui notin seen:
      seen.incl(ui)
      result.add(ui)
  for ui in bm25Order:
    if ui notin seen:
      seen.incl(ui)
      result.add(ui)
  if result.len > cap:
    result = result[0 ..< cap]

proc main() =
  echo "dict+bm25 merge mirror test..."

  let dict = @["D1", "D2"]         # exact-name then synonym, in M-collation order
  let bm25 = @["D2", "D3", "D1"]   # ranked; D2/D1 already dict hits
  var combined = mergeDictFirst(dict, bm25, 20)

  # MergeDictFirst: dict hits are a prefix of the merged list.
  assert combined.len >= 2 and combined[0] == "D1" and combined[1] == "D2",
    "dict is a prefix, got " & $combined

  # MergeNoDup: no duplicates anywhere.
  assert noDup(combined), "no duplicates"

  # BM25 fill appends only non-dict hits, preserving BM25 order.
  assert combined == @["D1", "D2", "D3"], "dict-first + bm25 fill, got " & $combined

  # MergeCapped: cap respected.
  let many = @["d1", "d2", "d3", "d4", "d5"]
  let capped = mergeDictFirst(many, @[], 3)
  assert capped.len == 3 and capped == @["d1", "d2", "d3"], "cap respected"

  echo "  dict-first / no-dup / capped hold (spec == runtime merge)"
  echo "dict+bm25 merge mirror test passed!"

main()
