// formal/key_encoding.dfy
//
// Formal model of NimM `storage/key_encoding.nim`: the LMDB key framing and
// M-collation ordering. This models the SPEC (unambiguous type-byte framing,
// and the order Empty < Num < Str), CONCRETIZED around the numeric field's
// fixed width: the Nim encodeNumeric scales a value by 10^12 into an int64 /
// 18-digit field, so only |scale| < 10^18 round-trips (|value| < 10^6). Any
// number whose scaled magnitude reaches 10^18 (e.g. a 16-digit id) must be
// classified as a *string*, or encode/decode corrupts it. The Nim
// implementation is checked against this by tests/test_encoding_roundtrip.nim.
//
// Verify with:  dafny verify formal/key_encoding.dfy

module KeyEncoding {

  // The numeric body is the value scaled by 10^12, stored in a fixed 18-digit
  // field. MaxScaled is 10^18 (the largest 18-digit field); a scale at or
  // beyond it does not fit and must fall back to string encoding.
  const MaxScaled: int := 1_000_000_000_000_000_000

  ghost predicate EncodableNum(scale: int)
  {
    -MaxScaled < scale < MaxScaled
  }

  // A scaled magnitude of >= 10^18 (i.e. |value| >= 10^6) is not encodable.
  lemma LargeScaleNotEncodable(scale: int)
    requires scale >= MaxScaled
    ensures !EncodableNum(scale)
  {
  }

  // Every Num subscript in the list is within the encodable range.
  ghost predicate EncodableSubs(subs: seq<Sub>)
    decreases |subs|
  {
    if subs == [] then true
    else (subs[0].Num? ==> EncodableNum(subs[0].scale)) && EncodableSubs(subs[1..])
  }

  // A subscript: empty, a scaled integer (value = scale / 10^12), or a
  // non-empty string of bytes.
  datatype Sub =
    | Empty
    | Num(scale: int)
    | Str(bytes: seq<int>)

  // ---------------------------------------------------------------------------
  // Collation (mirrors mCollationCmp)
  // ---------------------------------------------------------------------------

  // Lexicographic < over byte sequences.
  function LexLt(a: seq<int>, b: seq<int>): bool
    decreases a
  {
    if a == [] then b != []
    else if b == [] then false
    else if a[0] != b[0] then a[0] < b[0]
    else LexLt(a[1..], b[1..])
  }

  // M collation: Empty < Num < Str; Num by value; Str lexicographic.
  function Cmp(a: Sub, b: Sub): int
  {
    if a.Empty? then
      if b.Empty? then 0 else -1
    else if a.Num? then
      if b.Empty? then 1
      else if b.Num? then
        if a.scale < b.scale then -1 else if a.scale == b.scale then 0 else 1
      else -1
    else
      if b.Empty? then 1
      else if b.Num? then 1
      else if a.bytes == b.bytes then 0
      else if LexLt(a.bytes, b.bytes) then -1 else 1
  }

  // ---------------------------------------------------------------------------
  // Theorems: Cmp is a strict weak (total) order.
  // ---------------------------------------------------------------------------

  lemma LexLtAntisymmetric(a: seq<int>, b: seq<int>)
    ensures LexLt(a, b) ==> !LexLt(b, a)
    decreases a
  {
    if a != [] && b != [] && a[0] == b[0] {
      LexLtAntisymmetric(a[1..], b[1..]);
    }
  }

  lemma LexLtTransitive(a: seq<int>, b: seq<int>, c: seq<int>)
    requires LexLt(a, b) && LexLt(b, c)
    ensures LexLt(a, c)
    decreases |a| + |b| + |c|
  {
    reveal LexLt;
    if a == [] {
    } else if b == [] || c == [] {
    } else if a[0] < b[0] {
    } else if b[0] < c[0] {
    } else {
      LexLtTransitive(a[1..], b[1..], c[1..]);
    }
  }

  lemma LexLtTotal(a: seq<int>, b: seq<int>)
    requires a != b
    ensures LexLt(a, b) || LexLt(b, a)
    decreases |a| + |b|
  {
    reveal LexLt;
    if a == [] {
    } else if b == [] {
    } else if a[0] < b[0] {
    } else if b[0] < a[0] {
    } else {
      LexLtTotal(a[1..], b[1..]);
    }
  }

  lemma CmpAntisymmetric(a: Sub, b: Sub)
    ensures Cmp(a, b) == -Cmp(b, a)
  {
    reveal Cmp;
    if a.Empty? {
    } else if a.Num? {
    } else {
      if b.Empty? {
      } else if b.Num? {
      } else {
        if a.bytes != b.bytes {
          if LexLt(a.bytes, b.bytes) {
            LexLtAntisymmetric(a.bytes, b.bytes);
          } else {
            LexLtTotal(a.bytes, b.bytes);
          }
        }
      }
    }
  }

  lemma CmpTransitive(a: Sub, b: Sub, c: Sub)
    requires Cmp(a, b) <= 0
    requires Cmp(b, c) <= 0
    ensures Cmp(a, c) <= 0
  {
    reveal Cmp;
    if a.Empty? {
    } else if a.Num? {
      if b.Empty? {
      } else if b.Num? {
      } else {
      }
    } else {
      if b.Empty? {
      } else if b.Num? {
      } else if c.Empty? {
      } else if c.Num? {
      } else {
        if a.bytes == b.bytes {
        } else if b.bytes == c.bytes {
        } else {
          LexLtTransitive(a.bytes, b.bytes, c.bytes);
        }
      }
    }
  }

  lemma CmpZeroMeansEqual(x: Sub, y: Sub)
    requires Cmp(x, y) == 0
    ensures x == y
  {
    reveal Cmp;
    if x.Empty? {
      assert y.Empty?;
    } else if x.Num? {
      assert y.Num? && x.scale == y.scale;
    } else {
      assert y.Str? && x.bytes == y.bytes;
    }
  }

  // Strict transitivity: x < y && y <= z  ==>  x < z.
  lemma CmpStrictTrans(x: Sub, y: Sub, z: Sub)
    requires Cmp(x, y) < 0 && Cmp(y, z) <= 0
    ensures Cmp(x, z) < 0
  {
    reveal Cmp;
    CmpTransitive(x, y, z);
    if Cmp(x, z) == 0 {
      CmpZeroMeansEqual(x, z);
      CmpAntisymmetric(x, y);
      assert Cmp(y, x) > 0;
      assert Cmp(y, z) <= 0;
      assert false;
    }
  }

  // ---------------------------------------------------------------------------
  // Framing (encode / decode)
  // ---------------------------------------------------------------------------
  //
  // Key layout:  global 0x00  (type + data)*
  //   type 0x00 = Empty (0 data bytes)
  //   type 0x01 = Num   (fixed-width, self-delimiting)
  //   type 0x02 = Str   (bytes, terminated by 0x00)
  //
  // The numeric body is abstracted to an injective fixed-width encoding; the
  // concrete 18-digit/9's-complement body in the Nim code is pinned to this
  // contract by test_encoding_roundtrip.nim.

  function EncodeNum(scale: int): seq<int> { [scale] }
  function DecodeNum(body: seq<int>): int { if body == [] then 0 else body[0] }

  lemma NumCodecRoundTrip(scale: int)
    requires EncodableNum(scale)
    ensures DecodeNum(EncodeNum(scale)) == scale
  {
  }

  // Encode a global + subscripts into a framed byte sequence.
  // Layout:  global ++ [0] ++ (type+data)*   (the 0 is the global terminator).
  function EncodeSubs(subs: seq<Sub>): seq<int>
    decreases |subs|
  {
    if subs == [] then []
    else if subs[0].Empty? then [0] + EncodeSubs(subs[1..])
    else if subs[0].Num? then [1] + EncodeNum(subs[0].scale) + EncodeSubs(subs[1..])
    else [2] + subs[0].bytes + [0] + EncodeSubs(subs[1..])
  }

  function Encode(global: seq<int>, subs: seq<Sub>): seq<int>
  {
    global + [0] + EncodeSubs(subs)
  }

  // --- Decode (inverse of Encode) ---

  // Well-formed subscripts: Str bytes never contain the 0 terminator (M global
  // and string subscripts cannot contain NUL).
  predicate WellFormedSubs(subs: seq<Sub>)
  {
    forall i | 0 <= i < |subs| :: subs[i].Str? ==> 0 !in subs[i].bytes
  }

  // Longest prefix of key containing no 0 (the Str body, and also the global
  // name in a full key).
  function StrBody(key: seq<int>): seq<int>
    decreases |key|
  {
    if |key| == 0 then []
    else if key[0] == 0 then []
    else [key[0]] + StrBody(key[1..])
  }

  function DecodeSubs(key: seq<int>): seq<Sub>
    decreases |key|
  {
    if |key| == 0 then []
    else if key[0] == 0 then [Empty] + DecodeSubs(key[1..])
    else if key[0] == 1 then
      if |key| >= 2 then [Num(DecodeNum(key[1..]))] + DecodeSubs(key[2..]) else [Num(0)]
    else
      var body := StrBody(key[1..]);
      [Str(body)] + (if |key| >= 1 + |body| + 1 then DecodeSubs(key[1 + |body| + 1 ..]) else [])
  }

  function Decode(key: seq<int>): (seq<int>, seq<Sub>)
  {
    var g := StrBody(key);
    (g, if |g| < |key| then DecodeSubs(key[|g| + 1 ..]) else [])
  }

  // The body of a Str subscript is everything up to its 0 terminator.
  lemma StrBodyNoZero(bytes: seq<int>, rest: seq<int>)
    requires 0 !in bytes
    ensures StrBody(bytes + [0] + rest) == bytes
    decreases |bytes|
  {
    reveal StrBody;
    if |bytes| == 0 {
      assert bytes == [];
      assert StrBody([] + [0] + rest) == [];
    } else {
      assert bytes[0] != 0;
      StrBodyNoZero(bytes[1..], rest);
      assert bytes == [bytes[0]] + bytes[1..];
      assert bytes + [0] + rest == [bytes[0]] + (bytes[1..] + [0] + rest);
      assert (bytes + [0] + rest)[1..] == bytes[1..] + [0] + rest;
      assert StrBody(bytes + [0] + rest) == [bytes[0]] + StrBody(bytes[1..] + [0] + rest);
    }
  }

  // Decode inverts EncodeSubs for well-formed, encodable subscripts.
  lemma DecodeSubsRoundTrip(subs: seq<Sub>)
    requires WellFormedSubs(subs)
    requires EncodableSubs(subs)
    ensures DecodeSubs(EncodeSubs(subs)) == subs
    decreases |subs|
  {
    reveal DecodeSubs;
    reveal EncodeSubs;
    if subs == [] {
    } else if subs[0].Empty? {
      DecodeSubsRoundTrip(subs[1..]);
      assert EncodeSubs(subs) == [0] + EncodeSubs(subs[1..]);
      assert DecodeSubs(EncodeSubs(subs)) == [Empty] + DecodeSubs(EncodeSubs(subs[1..]));
    } else if subs[0].Num? {
      DecodeSubsRoundTrip(subs[1..]);
      NumCodecRoundTrip(subs[0].scale);
      assert EncodeSubs(subs) == [1, subs[0].scale] + EncodeSubs(subs[1..]);
      assert DecodeSubs(EncodeSubs(subs)) == [Num(subs[0].scale)] + DecodeSubs(EncodeSubs(subs[1..]));
    } else {
      assert 0 !in subs[0].bytes;
      DecodeSubsRoundTrip(subs[1..]);
      StrBodyNoZero(subs[0].bytes, EncodeSubs(subs[1..]));
      var rest := EncodeSubs(subs[1..]);
      var key := [2] + subs[0].bytes + [0] + rest;
      assert EncodeSubs(subs) == key;
      assert key[1..] == subs[0].bytes + [0] + rest;
      assert StrBody(key[1..]) == subs[0].bytes;
      assert 1 + |subs[0].bytes| + 1 <= |key|;
      assert key[1 + |subs[0].bytes| + 1 ..] == rest;
      assert DecodeSubs(key) == [Str(subs[0].bytes)] + DecodeSubs(rest);
    }
  }

  // Full round-trip: decode(encode(global, subs)) == (global, subs).
  lemma EncodeDecodeRoundTrip(global: seq<int>, subs: seq<Sub>)
    requires 0 !in global
    requires WellFormedSubs(subs)
    requires EncodableSubs(subs)
    ensures Decode(Encode(global, subs)) == (global, subs)
  {
    StrBodyNoZero(global, EncodeSubs(subs));
    assert StrBody(global + [0] + EncodeSubs(subs)) == global;
    DecodeSubsRoundTrip(subs);
    assert Decode(Encode(global, subs)) == (global, subs);
  }

}
