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

  # Regression: leading-zero and large-integer subscripts must round-trip
  # losslessly as strings (the encodeNumeric 18-digit field overflows int64
  # for |num| >= 1e6; leading zeros are non-canonical).
  roundtripEncodeKey("^G", @["0402304"])           # leading zero -> string
  roundtripEncodeKey("^G", @["101258277"])         # 9-digit -> string
  roundtripEncodeKey("^G", @["9918334887106676"])  # 16-digit -> string
  roundtripEncodeKey("^G", @["26170740R"])         # alphanumeric -> string
  roundtripEncodeKey("^G", @["42", "101258277", "0402304", "hello"])
  echo "✓ large/leading-zero subscripts round-trip losslessly"

  # isNumeric boundary: leading zeros and >= 7-digit integers are not numeric.
  assert not isNumeric("0402304"), "leading zero must not be numeric"
  assert not isNumeric("00"), "00 must not be numeric"
  assert not isNumeric("101258277"), "7+ digit integer must not be numeric"
  assert not isNumeric("9918334887106676"), "16-digit integer must not be numeric"
  assert isNumeric("42"), "small integer must be numeric"
  assert isNumeric("999999"), "6-digit integer must be numeric"
  assert not isNumeric("1000000"), "1e6 (7 digits) must not be numeric"
  echo "✓ isNumeric boundary (leading zero / >= 1e6)"

  # Collation consistency: mCollationCmp must agree with encodeKey's type byte
  # (numeric-vs-string) so $ORDER does not skip fallback-string subscripts.
  assert mCollationCmp("101258277", "0402304") > 0,
    "large int (string) must sort after leading-zero (string)"
  assert mCollationCmp("42", "101258277") < 0,
    "small number must sort before large int (string)"
  echo "✓ mCollationCmp consistent with encoding"

  # Framing well-formedness: validateFraming rejects every malformed form.
  assert validateFraming("^X\x00") == ""
  assert validateFraming("^X\x00\x00") == ""
  assert validateFraming("^X\x00\x02abc\x00") == ""
  assert validateFraming("") == "empty key"
  assert validateFraming("^X") == "no global terminator"
  assert validateFraming("^X\x00\x03") != ""
  assert validateFraming("^X\x00\x01") != ""
  assert validateFraming("^X\x00\x02abc") != ""
  echo "✓ validateFraming rejects malformed keys"

  echo ""
  echo "All tests passed!"

when isMainModule:
  main()
