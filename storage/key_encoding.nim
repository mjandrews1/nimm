# key_encoding.nim — M/MUMPS key encoding for LMDB
# Encodes global references to LMDB keys with M-collation order
#
# M-collation order:
#   1. Empty string sorts first
#   2. Numbers sort before strings
#   3. Numbers sort by numeric value (negative < zero < positive)
#   4. Strings sort lexicographically
#
# Key format:
#   global \x00  (type+data)*
# where each subscript is a type byte followed by fixed/terminated data:
#   \x00                              — empty string (no data)
#   \x01 + sign_byte + 18 digits      — number (sign + zero-padded integer)
#   \x02 + bytes + \x00               — string (null-terminated)
#
# The type byte alone disambiguates each subscript: \x00 is 0 data bytes,
# \x01 is a fixed 19 data bytes, \x02 runs to the next \x00. There is no
# separate separator byte between subscripts.
#
# Numeric encoding detail:
#   - Sign byte: \x00 for negative, \x01 for zero, \x02 for positive
#   - 18-digit zero-padded absolute value (handles integers up to 10^18)
#   - For decimals: multiply by 10^12 and encode as integer
#   - This preserves order: negative < zero < positive, and within each
#     category, numeric value order matches byte order
#
# String encoding detail:
#   - Type byte \x02 followed by raw bytes, terminated by \x00

import strutils
import math

func isNumeric*(s: string): bool =
  ## Check if string represents an M-canonical number that the 18-digit field
  ## can encode losslessly: optional '-', then either ".digits" (fractional),
  ## or a non-zero-led integer part (up to 6 digits) with optional ".digits".
  ## Leading zeros ("0402304", "00") and large integers (>= 1e6, e.g. 16-digit
  ## ids) are NOT numeric here — they are encoded as strings so the round-trip
  ## is lossless and collation is consistent with encodeKey.
  if s.len == 0: return false
  var i = 0
  if s[0] == '-': i = 1
  if i >= s.len: return false
  if s[i] == '.':
    # fractional-only form: .5, -.25
    i += 1
    if i >= s.len or (s[i] < '0' or s[i] > '9'): return false
    while i < s.len and s[i] >= '0' and s[i] <= '9': i += 1
    return i == s.len
  if s[i] < '0' or s[i] > '9': return false
  if s[i] == '0':
    # leading zero: canonical only as "0" or "0.xxx"
    i += 1
    if i < s.len and s[i] != '.': return false
  else:
    # non-zero-led integer part; count digits to bound magnitude < 1e6
    var intDigits = 0
    while i < s.len and s[i] >= '0' and s[i] <= '9':
      i += 1; intDigits += 1
    if intDigits >= 7: return false
  if i < s.len and s[i] == '.':
    i += 1
    if i >= s.len or (s[i] < '0' or s[i] > '9'): return false
    while i < s.len and s[i] >= '0' and s[i] <= '9': i += 1
  return i == s.len

const MaxEncodedMagnitude = 1_000_000.0
  ## Largest |num| whose scaled value (|num| * 1e12) fits the 18-digit field.

func encodeNumeric*(num: float64): string =
  ## Encode a number as order-preserving bytes
  ## Format: sign_byte + 18-digit zero-padded field
  ## Sign: \x00=negative, \x01=zero, \x02=positive
  ## The 18-digit field is the scaled magnitude for non-negatives, and its
  ## 9's-complement for negatives, so byte order == numeric order across
  ## the whole range (more-negative sorts before less-negative).
  var signByte: byte
  var absVal: float64
  
  if num < 0:
    signByte = 0x00
    absVal = -num
  elif num == 0:
    signByte = 0x01
    absVal = 0
  else:
    signByte = 0x02
    absVal = num
  
  # Convert to integer by scaling (handles up to 6 decimal places)
  let scaled = int64(absVal * 1_000_000_000_000.0)
  let field = if signByte == 0x00: 999_999_999_999_999_999'i64 - scaled
              else: scaled
  let digits = $field
  var padded = ""
  for j in 0..<(18 - digits.len):
    padded.add('0')
  padded.add(digits)
  
  result = ""
  result.add(chr(signByte))
  result.add(padded)

func encodeKey*(global: string, subs: seq[string] = @[]): string =
  ## Encode global[sub1,sub2,...] to LMDB key with M-collation order
  ## Format: global\x00(type+data)*
  ##
  ## Each subscript is a type byte + data. The type byte disambiguates the
  ## subscript length, so no separate separator byte is needed between subscripts.
  result = global
  result.add('\x00')  # global terminator (global names never contain \x00)
  for sub in subs:
    if sub.len == 0:
      # Empty string: single \x00 type byte (sorts first)
      result.add('\x00')
    elif isNumeric(sub):
      # Numeric subscript: type prefix + sign + 18 digits.
      # Values whose scaled magnitude overflows the 18-digit field (>= 1e6)
      # fall back to string encoding so the round-trip is lossless.
      try:
        let num = parseFloat(sub)
        if abs(num) >= MaxEncodedMagnitude:
          result.add('\x02')
          result.add(sub)
          result.add('\x00')
        else:
          result.add('\x01')
          result.add(encodeNumeric(num))
      except:
        # Fallback: treat as string
        result.add('\x02')
        result.add(sub)
        result.add('\x00')
    else:
      # String subscript: type prefix + raw bytes + null terminator
      result.add('\x02')
      result.add(sub)
      result.add('\x00')

func decodeKey*(key: string): (string, seq[string]) =
  ## Decode LMDB key to (global, [sub1, sub2, ...])
  ## Inverse of encodeKey
  ##
  ## Key format:
  ##   global\x00(type+data)*
  ## where type is:
  ##   \x00 = empty string (0 data bytes)
  ##   \x01 = number (19 data bytes: sign + 18 digits)
  ##   \x02 = string (data bytes until \x00 terminator)
  var parts: seq[string] = @[]
  var globalName = ""
  var i = 0
  
  # Find global name (everything before first \x00)
  while i < key.len and key[i] != '\x00':
    i += 1
  globalName = key[0..<i]
  i += 1  # skip the \x00 terminator after global
  
  # Decode subscripts: type byte + data, until key is exhausted.
  while i < key.len:
    let typeByte = key[i]
    i += 1  # move past type byte
    
    case typeByte
    of '\x00':
      # Empty string subscript
      parts.add("")
    of '\x01':
      # Number: sign byte + 18 digits
      if i + 19 <= key.len:
        let signByte = key[i]
        i += 1
        let digits = key[i..<i+18]
        i += 18
        
        # Parse the number
        try:
          let field = parseInt(digits)
          var absVal: int64
          if signByte == '\x00':  # negative — field is 9's-complement
            absVal = 999_999_999_999_999_999'i64 - field
          else:
            absVal = field
          var num: float64
          if signByte == '\x00':  # negative
            num = -absVal.float64 / 1_000_000_000_000.0
          elif signByte == '\x01':  # zero
            num = 0.0
          else:  # positive
            num = absVal.float64 / 1_000_000_000_000.0
          
          # Format in M-canonical form (drop leading zero: 0.5 -> ".5",
          # -0.25 -> "-.25") so decode is the inverse of encode.
          if num == floor(num) and abs(num) < 1e15:
            parts.add($int64(num))
          else:
            var s = $num
            if s.startsWith("-0."): s = "-" & s[2..^1]
            elif s.startsWith("0."): s = s[1..^1]
            parts.add(s)
        except:
          parts.add("0")
      else:
        break
    of '\x02':
      # String: read until \x00 terminator
      var s = ""
      while i < key.len and key[i] != '\x00':
        s.add(key[i])
        i += 1
      parts.add(s)
      # Skip the \x00 terminator
      if i < key.len and key[i] == '\x00':
        i += 1
    else:
      break
  
  result = (globalName, parts)

func mCollationCmp*(a, b: string): int =
  ## M-collation comparison: numeric before string
  ## Empty string sorts first
  if a.len == 0 and b.len == 0: return 0
  if a.len == 0: return -1
  if b.len == 0: return 1
  
  # Check if both are numeric
  let aIsNum = isNumeric(a)
  let bIsNum = isNumeric(b)
  
  if aIsNum and bIsNum:
    # Both numeric: compare as numbers
    try:
      let aNum = parseFloat(a)
      let bNum = parseFloat(b)
      if aNum < bNum: return -1
      if aNum > bNum: return 1
      return 0
    except:
      # Fallback to string comparison
      discard
  
  if aIsNum and not bIsNum: return -1
  if not aIsNum and bIsNum: return 1
  
  # Both strings: compare lexicographically
  return cmp(a, b)
