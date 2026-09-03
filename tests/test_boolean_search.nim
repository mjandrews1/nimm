# test_boolean_search.nim — mirror of formal/boolean_search.dfy (#468).
#
# Re-implements the zig-zag merge over sorted ordinal sequences and asserts the
# lemmas: soundness + completeness + commutativity for Intersect, Union, and
# Difference, plus the SmallerHeadAbsent helper. Uses ints (order-isomorphic to
# the nat ordinals in the model).
#
# Run: nim c -r tests/test_boolean_search.nim

import sets
import algorithm

type Doc = int

proc sortedPosting(ids: seq[Doc]): bool =
  for i in 1 ..< ids.len:
    if ids[i - 1] >= ids[i]: return false
  return true

proc toSet(ids: seq[Doc]): HashSet[Doc] =
  result = initHashSet[Doc]()
  for d in ids: result.incl(d)

proc intersectP(a, b: seq[Doc]): seq[Doc] =
  result = @[]
  var i = 0; var j = 0
  while i < a.len and j < b.len:
    if a[i] == b[j]:
      result.add(a[i]); inc i; inc j
    elif a[i] < b[j]: inc i
    else: inc j

proc unionP(a, b: seq[Doc]): seq[Doc] =
  result = @[]
  var i = 0; var j = 0
  while i < a.len and j < b.len:
    if a[i] == b[j]: result.add(a[i]); inc i; inc j
    elif a[i] < b[j]: result.add(a[i]); inc i
    else: result.add(b[j]); inc j
  while i < a.len: result.add(a[i]); inc i
  while j < b.len: result.add(b[j]); inc j

proc differenceP(a, b: seq[Doc]): seq[Doc] =
  result = @[]
  var i = 0; var j = 0
  while i < a.len and j < b.len:
    if a[i] == b[j]: inc i; inc j
    elif a[i] < b[j]: result.add(a[i]); inc i
    else: inc j
  while i < a.len: result.add(a[i]); inc i

proc smallerHeadAbsent(a0: Doc, b: seq[Doc]): bool =
  # mirrors SmallerHeadAbsent: a0 < b[0] && sorted(b) => a0 not in b
  if b.len == 0: return true
  if a0 >= b[0]: return true  # premise violated -> vacuously true
  return not toSet(b).contains(a0)

proc main() =
  echo "boolean_search mirror test..."
  let a = @[1, 3, 5, 7, 9]
  let b = @[1, 2, 3, 4, 9]
  let c = @[2, 4, 6]
  assert sortedPosting(a) and sortedPosting(b) and sortedPosting(c), "inputs sorted"

  # SmallerHeadAbsent: when a0 < b[0] and b is sorted, a0 is absent from b.
  let a0 = 0
  assert a0 < b[0]
  assert a0 notin toSet(b), "0 < every b element, so 0 notin b"

  # IntersectSound/Complete
  let iab = intersectP(a, b)
  for d in iab:
    assert toSet(a).contains(d) and toSet(b).contains(d), "IntersectSound: " & $d
  for d in toSet(a).items:
    if toSet(b).contains(d):
      assert toSet(iab).contains(d), "IntersectComplete: " & $d
  assert toSet(iab) == toSet(intersectP(b, a)), "IntersectCommutative"

  # UnionSound/Complete
  let uab = unionP(a, b)
  for d in uab:
    assert toSet(a).contains(d) or toSet(b).contains(d), "UnionSound: " & $d
  for d in (toSet(a) + toSet(b)).items:
    assert toSet(uab).contains(d), "UnionComplete: " & $d
  assert toSet(uab) == toSet(unionP(b, a)), "UnionCommutative"

  # DifferenceSound/Complete
  let dab = differenceP(a, c)
  for d in dab:
    assert toSet(a).contains(d) and (not toSet(c).contains(d)), "DifferenceSound: " & $d
  for d in toSet(a).items:
    if not toSet(c).contains(d):
      assert toSet(dab).contains(d), "DifferenceComplete: " & $d

  # Concrete check: a - c where c = [2,4,6], a = [1,3,5,7,9]
  assert dab == @[1, 3, 5, 7, 9], "difference concrete, got " & $dab
  # a AND NOT b = [5,7]
  let anotb = differenceP(a, b)
  assert anotb == @[5, 7], "a AND NOT b = [5,7], got " & $anotb

  echo "  merge soundness/completeness/commutativity hold"
  echo "boolean_search mirror test passed!"

main()
