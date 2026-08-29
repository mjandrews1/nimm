# test_encoding_roundtrip.nim — L1 property tests: key codecs are inverses.
# encodeKey/decodeKey (LMDB type-byte) and makeKey/decodeMakeKey (flat in-memory).

import ../globals
import ../storage/key_encoding

proc eq(subs: seq[string], expected: seq[string]): bool =
  if subs.len != expected.len: return false
  for i in 0 ..< subs.len:
    if subs[i] != expected[i]: return false
  true

proc roundtripMakeKey(name: string, subs: seq[string]) =
  let key = makeKey(name, subs)
  let (n, s) = decodeMakeKey(key)
  assert n == name, "makeKey name roundtrip failed: " & n
  assert s == subs, "makeKey subs roundtrip failed"

proc roundtripEncodeKey(global: string, subs: seq[string]) =
  let key = encodeKey(global, subs)
  let (g, s) = decodeKey(key)
  assert g == global, "encodeKey global roundtrip failed: " & g
  assert eq(s, subs), "encodeKey subs roundtrip failed: " & $s & " != " & $subs

proc main() =
  echo "Testing encoding round-trip (L1)..."

  # makeKey / decodeMakeKey — exact inverse for arbitrary subscripts
  roundtripMakeKey("X", @[])
  roundtripMakeKey("X", @["a"])
  roundtripMakeKey("X", @["a", "b", "c"])
  roundtripMakeKey("^G", @["1", "2"])
  roundtripMakeKey("^G", @[""])
  roundtripMakeKey("^G", @["a", "", "b"])
  roundtripMakeKey("", @["a"])
  echo "✓ makeKey/decodeMakeKey exact round-trip"

  # encodeKey / decodeKey — exact for strings, empty, and canonical numbers
  roundtripEncodeKey("^G", @[])
  roundtripEncodeKey("^G", @["hello"])
  roundtripEncodeKey("^G", @[""])
  roundtripEncodeKey("^G", @["a", "b", "c"])
  roundtripEncodeKey("^G", @["1"])          # canonical integer
  roundtripEncodeKey("^G", @["-100"])       # negative integer
  roundtripEncodeKey("^G", @["0"])          # zero
  roundtripEncodeKey("^G", @[".5"])         # canonical fraction (no leading 0)
  roundtripEncodeKey("^G", @["-.25"])       # canonical negative fraction
  roundtripEncodeKey("^G", @["10", "hello", ""])
  echo "✓ encodeKey/decodeKey exact round-trip (canonical forms)"

  # Non-canonical numeric inputs canonicalize on decode (documented behavior)
  let (g1, s1) = decodeKey(encodeKey("^G", @["0.5"]))
  assert g1 == "^G" and s1 == @[".5"], "expected canonicalization to .5"
  let (g2, s2) = decodeKey(encodeKey("^G", @["-0.25"]))
  assert g2 == "^G" and s2 == @["-.25"], "expected canonicalization to -.25"
  echo "✓ numeric canonicalization (0.5 -> .5, -0.25 -> -.25)"

  echo ""
  echo "All tests passed!"

when isMainModule:
  main()
