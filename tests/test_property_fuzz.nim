# test_property_fuzz.nim — Phase 4 property fuzz (mirrors the Dafny models).
#
# Deterministic (seeded LCG) property tests for:
#   A. Key round-trip — makeKey/decodeMakeKey (flat in-memory, exact for all
#      subscripts) and encodeKey/decodeKey (exact for non-numeric subscripts).
#      Mirrors key_encoding.dfy / globals_order.dfy.
#   B. formatNumber canonical form — integer floats format to a bare integer;
#      fractions never carry a redundant leading "0." / "-0.".
#      Mirrors value_format.dfy.
#
# Run: nim c -r tests/test_property_fuzz.nim

import strutils
import ../globals
import ../storage/key_encoding
import ../value

var seed = 0x9E3779B97F4A7C15'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)

proc randInt(lo, hi: int): int =
  lo + int(rng() mod uint32(hi - lo + 1))

const alphabet = "abzAZ09._-!@#$%^&()[]"

proc randString(): string =
  let n = randInt(0, 5)
  result = ""
  for _ in 0 ..< n:
    result.add(alphabet[randInt(0, alphabet.len - 1)])

proc eq(a, b: seq[string]): bool =
  if a.len != b.len: return false
  for i in 0 ..< a.len:
    if a[i] != b[i]: return false
  true

proc allNonNumeric(subs: seq[string]): bool =
  for s in subs:
    if isNumeric(s): return false
  true

proc main() =
  echo "Property fuzz (seeded, deterministic)..."

  # --- A. Key round-trip ---
  var makeRtt = 0
  var encRtt = 0
  for _ in 1 .. 5000:
    let name = randString()
    var subs: seq[string] = @[]
    let nsub = randInt(0, 4)
    for _ in 0 ..< nsub:
      subs.add(randString())
    let (n2, s2) = decodeMakeKey(makeKey(name, subs))
    assert n2 == name, "makeKey name roundtrip failed: " & n2
    assert s2 == subs, "makeKey subs roundtrip failed: " & $s2 & " != " & $subs
    makeRtt += 1
    if allNonNumeric(subs):
      let (g2, e2) = decodeKey(encodeKey("^G", subs))
      assert g2 == "^G", "encodeKey global roundtrip failed"
      assert e2 == subs, "encodeKey subs roundtrip failed: " & $e2 & " != " & $subs
      encRtt += 1
  echo "  makeKey/decodeMakeKey round-trip: ", makeRtt, " cases"
  echo "  encodeKey/decodeKey round-trip (non-numeric): ", encRtt, " cases"

  # --- B. formatNumber canonical form ---
  var intCases = 0
  var fracCases = 0
  for _ in 1 .. 5000:
    let i = randInt(-9000000, 9000000)
    let fs = formatNumber(float(i))
    assert fs == $i, "formatNumber integer mismatch: " & fs & " != " & $i
    intCases += 1
    let num = randInt(-9999, 9999)
    let den = randInt(1, 10000)
    let ff = formatNumber(float(num) / float(den))
    assert not ff.startsWith("0.") and not ff.startsWith("-0."),
      "leading-zero fraction: " & ff
    fracCases += 1
  echo "  formatNumber integer canonical: ", intCases, " cases"
  echo "  formatNumber fraction no-leading-zero: ", fracCases, " cases"

  echo ""
  echo "All property fuzz tests passed!"

main()
