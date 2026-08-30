# test_truthy.nim — truth-value + numeric round-trip property test
# (mirrors formal/numeric_prefix.dfy and formal/value_format.dfy).
#
# Run: nim c -r tests/test_truthy.nim

import std/options
import ../value

var seed = 0xABCD'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)
proc randInt(lo, hi: int): int = lo + int(rng() mod uint32(hi - lo + 1))

proc main() =
  echo "Truthy + numeric round-trip (mirrors numeric_prefix.dfy / value_format.dfy)..."

  # Truth table (ANSI/ISO 2.2.4).
  assert not truthy("")
  assert not truthy("0")
  assert not truthy("0.00")
  assert not truthy("abc")
  assert truthy("1")
  assert truthy("042")
  assert truthy(".5x")
  assert truthy("3apples")
  assert truthy("2e3")
  assert truthy("9")
  assert not truthy("-0")
  echo "  truth table: ok"

  # formatNumber -> parseNum round-trip (formatNumber is parseNum's inverse).
  for _ in 1 .. 20000:
    let v = float(randInt(-9000000, 9000000))
    let s = formatNumber(v)
    let p = parseNum(s)
    assert p.isSome(), "formatNumber output should be parseable: " & s
    assert p.get() == v, "integer round-trip failed: " & s & " -> " & $p.get()

    let f = float(randInt(-9999, 9999)) / float(randInt(1, 10000))
    let fs = formatNumber(f)
    let fp = parseNum(fs)
    assert fp.isSome(), "fraction output should be parseable: " & fs
    assert fp.get() == f, "fraction round-trip failed: " & fs & " -> " & $fp.get()
  echo "  formatNumber -> parseNum round-trip (20k x 2): ok"

  echo "Truthy/round-trip test passed!"

main()
