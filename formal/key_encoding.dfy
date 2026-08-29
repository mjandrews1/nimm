// formal/key_encoding.dfy
//
// Formal model of NimM `storage/key_encoding.nim`: the LMDB key framing and
// M-collation ordering. This models the SPEC (unambiguous type-byte framing,
// and the order Empty < Num < Str). The Nim implementation is checked against
// it by tests/test_encoding_roundtrip.nim and the conformance suite.
//
// Verify with:  dafny verify formal/key_encoding.dfy

module KeyEncoding {

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
    ensures DecodeNum(EncodeNum(scale)) == scale
  {
  }

  // Encode a global + subscripts into a framed byte sequence.
  function Encode(global: seq<int>, subs: seq<Sub>): seq<int>
    decreases |subs|
  {
    if subs == [] then global + [0]
    else if subs[0].Empty? then Encode(global + [0, 0], subs[1..])
    else if subs[0].Num? then Encode(global + [1] + EncodeNum(subs[0].scale), subs[1..])
    else Encode(global + [2] + subs[0].bytes + [0], subs[1..])
  }

}
