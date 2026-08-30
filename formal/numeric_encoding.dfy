// formal/numeric_encoding.dfy
//
// Formal model of encodeNumeric (storage/key_encoding.nim): a scaled integer
// is encoded as a sign byte (0=neg, 1=zero, 2=pos) followed by an 18-digit
// field, 9's-complemented for negatives, so that byte order coincides with
// numeric order. This is what makes LMDB keys sort per M collation.
//
// Verify with:  dafny verify formal/key_encoding.dfy formal/numeric_encoding.dfy

module NumericEncoding {

  import opened KeyEncoding   // for LexLt (byte lexicographic order)

  // 18-digit field ceiling: 10^18 - 1.
  const MAX_FIELD := 999999999999999999

  // Sign byte: 0 = negative, 1 = zero, 2 = positive (byte order == numeric order).
  function SignByte(scale: int): int {
    if scale < 0 then 0 else if scale == 0 then 1 else 2
  }

  // The field: for negatives, 9's-complement (MAX_FIELD + scale); else scale.
  // This is monotonic within each sign class.
  function Field(scale: int): int
    requires -MAX_FIELD <= scale <= MAX_FIELD
  {
    if scale < 0 then MAX_FIELD + scale else scale
  }

  // Encoded numeric key: [sign, field].
  function EncodeNumeric(scale: int): seq<int>
    requires -MAX_FIELD <= scale <= MAX_FIELD
  {
    [SignByte(scale), Field(scale)]
  }

  // Field is monotonic within each sign class.
  lemma FieldMonotonic(x: int, y: int)
    requires -MAX_FIELD <= x < y <= MAX_FIELD
    ensures (x < 0 && y < 0) ==> Field(x) < Field(y)
    ensures x >= 0 ==> Field(x) < Field(y)
  {
    reveal Field;
  }

  // The encoding is order-preserving: x < y implies Encode(x) is
  // lexicographically before Encode(y).
  lemma EncodeOrderPreserving(x: int, y: int)
    requires -MAX_FIELD <= x < y <= MAX_FIELD
    ensures LexLt(EncodeNumeric(x), EncodeNumeric(y))
  {
    reveal LexLt;
    reveal EncodeNumeric;
    reveal SignByte;
    if SignByte(x) == SignByte(y) {
      // Same sign class → the field orders them.
      if x < 0 {
        FieldMonotonic(x, y);
        assert Field(x) < Field(y);
      } else {
        FieldMonotonic(x, y);
        assert Field(x) < Field(y);
      }
    } else {
      // Different sign classes: negative (0) < zero (1) < positive (2), and
      // since x < y, SignByte(x) < SignByte(y).
      assert SignByte(x) < SignByte(y);
    }
  }

  // --- Round-trip (decode is the inverse of encode) ---

  // Decode [sign, field] back to a scale. The 9's-complement of the field
  // recovers the magnitude for negatives.
  function DecodeNumeric(enc: seq<int>): int
    requires |enc| == 2 && 0 <= enc[1] <= MAX_FIELD
  {
    if enc[0] == 0 then -(MAX_FIELD - enc[1])
    else if enc[0] == 1 then 0
    else enc[1]
  }

  // decodeNumeric(encodeNumeric(scale)) == scale, for the whole range.
  lemma NumericRoundTrip(scale: int)
    requires -MAX_FIELD <= scale <= MAX_FIELD
    ensures DecodeNumeric(EncodeNumeric(scale)) == scale
  {
    reveal EncodeNumeric;
    reveal SignByte;
    reveal Field;
    if scale < 0 {
      assert Field(scale) == MAX_FIELD + scale;
    } else if scale == 0 {
    } else {
    }
  }

}
