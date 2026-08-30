# test_collation.nim — Phase A property test (mirrors formal/collation.dfy).
#
# Validates that the real mCollationCmp is a consistent comparison:
#   reflexive      cmp(s, s) == 0
#   skew-symmetric cmp(a, b) == -cmp(b, a)
#   transitive     cmp(a,b) < 0 && cmp(b,c) < 0  ==>  cmp(a,c) < 0
#   sorted         sort() output is non-decreasing
#
# Run: nim c -r tests/test_collation.nim

import algorithm
import ../storage/key_encoding

var seed = 0xDEADBEEF'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)

proc randInt(lo, hi: int): int =
  lo + int(rng() mod uint32(hi - lo + 1))

proc main() =
  echo "Collation property test (mirrors formal/collation.dfy)..."

  var corpus: seq[string] = @[
    "", "0", "1", "-1", "42", "-42", ".5", "-.5", "1.0", "01", "007", "-007",
    "1.50", "0.0", "a", "b", "A", "B", "aa", "ab", "ba", "a0", "a1", "z", "Z",
    "hello", "world", "test", "case", " ", "  ", "\t"
  ]
  const alphabet = "abcXYZ019.-"
  for _ in 1 .. 40:
    var s = ""
    for _ in 0 ..< randInt(0, 6):
      s.add(alphabet[randInt(0, alphabet.len - 1)])
    corpus.add(s)

  # 1. reflexivity
  for s in corpus:
    assert mCollationCmp(s, s) == 0, "reflexivity failed for: " & s

  # 2. skew-symmetry (all pairs)
  for a in corpus:
    for b in corpus:
      assert mCollationCmp(a, b) == -mCollationCmp(b, a),
        "skew failed for: " & a & " vs " & b

  # 3. transitivity (all triples)
  for a in corpus:
    for b in corpus:
      for c in corpus:
        let ab = mCollationCmp(a, b)
        let bc = mCollationCmp(b, c)
        if ab < 0 and bc < 0:
          assert mCollationCmp(a, c) < 0,
            "transitivity failed for: " & a & " < " & b & " < " & c

  # 4. sorted order is non-decreasing
  var sortedCorpus = corpus
  sortedCorpus.sort(mCollationCmp)
  for i in 1 ..< sortedCorpus.len:
    assert mCollationCmp(sortedCorpus[i - 1], sortedCorpus[i]) <= 0,
      "sorted order violated at index " & $i

  echo "  ", corpus.len, " strings; reflexivity, skew, transitivity, sorted order all hold"
  echo "All collation property tests passed!"

main()
