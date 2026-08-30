# test_pattern.nim — M pattern-match property test (mirrors formal/pattern.dfy).
#
# Validates matchPattern (pattern.nim) against the model's semantics:
#   exact-count atoms, orMore (`.`), alternation (`!`), and atom sequences
#   must consume the whole string (a pattern matches iff some alternative does).
#
# Run: nim c -r tests/test_pattern.nim

import ../ast
import ../pattern

var seed = 0xC0FFEE'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)
proc randInt(lo, hi: int): int = lo + int(rng() mod uint32(hi - lo + 1))

proc allAlpha(s: string): bool =
  result = s.len > 0
  for c in s:
    if c notin {'A'..'Z', 'a'..'z'}: return false

proc allDigit(s: string): bool =
  result = s.len > 0
  for c in s:
    if c notin {'0'..'9'}: return false

proc allUpper(s: string): bool =
  result = s.len > 0
  for c in s:
    if c notin {'A'..'Z'}: return false

proc main() =
  echo "Pattern match property test (mirrors formal/pattern.dfy)..."

  # Exact-count atom: 3A matches exactly 3 alphabetic.
  assert matchPattern("abc", @[@[PatternAtom(count: 3, code: 'A')]])
  assert not matchPattern("ab", @[@[PatternAtom(count: 3, code: 'A')]])
  assert not matchPattern("ab1", @[@[PatternAtom(count: 3, code: 'A')]])

  # orMore: 1.A matches one or more alphabetic (but not empty).
  assert matchPattern("abc", @[@[PatternAtom(count: 1, code: 'A', orMore: true)]])
  assert not matchPattern("", @[@[PatternAtom(count: 1, code: 'A', orMore: true)]])
  assert not matchPattern("a1", @[@[PatternAtom(count: 1, code: 'A', orMore: true)]])

  # Alternation (!): matches iff ANY alternative consumes the whole string.
  assert matchPattern("abc", @[@[PatternAtom(count: 3, code: 'N')],
                               @[PatternAtom(count: 3, code: 'A')]])
  assert not matchPattern("ab", @[@[PatternAtom(count: 3, code: 'N')],
                                  @[PatternAtom(count: 3, code: 'A')]])

  # Sequence of atoms: 1.A (greedy) then 3N.
  assert matchPattern("abc123", @[@[PatternAtom(count: 1, code: 'A', orMore: true),
                                    PatternAtom(count: 3, code: 'N')]])
  assert not matchPattern("abc12", @[@[PatternAtom(count: 1, code: 'A', orMore: true),
                                       PatternAtom(count: 3, code: 'N')]])

  # Character classes: numeric, hex, uppercase/lowercase.
  assert matchPattern("123", @[@[PatternAtom(count: 3, code: 'N')]])
  assert matchPattern("aF3", @[@[PatternAtom(count: 3, code: 'H')]])
  assert matchPattern("ABC", @[@[PatternAtom(count: 3, code: 'U')]])
  assert matchPattern("abc", @[@[PatternAtom(count: 3, code: 'L')]])

  # Randomized fuzz: the character classes must match the string's contents.
  for _ in 1 .. 5000:
    var s = ""
    for _ in 0 ..< randInt(0, 8):
      s.add(chr(randInt(32, 126)))
    assert matchPattern(s, @[@[PatternAtom(count: 1, code: 'E', orMore: true)]]) == (s.len > 0)
    assert matchPattern(s, @[@[PatternAtom(count: 1, code: 'A', orMore: true)]]) == allAlpha(s)
    assert matchPattern(s, @[@[PatternAtom(count: 1, code: 'N', orMore: true)]]) == allDigit(s)
    assert matchPattern(s, @[@[PatternAtom(count: 1, code: 'U', orMore: true)]]) == allUpper(s)

  echo "  exact / orMore / alternation / sequence / classes / fuzz all hold"
  echo "Pattern match test passed!"

main()
