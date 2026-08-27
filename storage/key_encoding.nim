# key_encoding.nim — M/MUMPS key encoding for LMDB
# Encodes global references to LMDB keys with M-collation order
#
# M-collation order:
#   1. Empty string sorts first
#   2. Numbers sort before strings
#   3. Numbers sort by numeric value (negative < zero < positive)
#   4. Strings sort lexicographically
#
# Key format per subscript:
#   \x00                              — empty string (type byte only, no content)
#   \x01 + sign_byte + 18 digits      — number (zero-padded integer)
#   \x02 + bytes + \x00               — string (null-terminated)
#
# Separator: each subscript's type byte distinguishes it from the next.
# After a \x01 subscript, the next byte is always a type byte (\x00/\x01/\x02) or end-of-key.
# After a \x02 string, the \x00 terminator is followed by another type byte or end-of-key.
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
#   - The \x00 terminator also serves as the separator before the next subscript

import strutils
import math

proc isNumeric*(s: string): bool =
  ## Check if string represents a number
  if s.len == 0: return false
  var i = 0
  if s[0] == '-': i = 1
  if i >= s.len: return false
  if s[i] < '0' or s[i] > '9': return false
  while i < s.len and s[i] >= '0' and s[i] <= '9': i += 1
  if i < s.len and s[i] == '.':
    i += 1
    if i >= s.len or (s[i] < '0' or s[i] > '9'): return false
    while i < s.len and s[i] >= '0' and s[i] <= '9': i += 1
  return i == s.len

proc encodeNumeric*(num: float64): string =
  ## Encode a number as order-preserving bytes
  ## Format: sign_byte + 18-digit zero-padded absolute value
  ## Sign: \x00=negative, \x01=zero, \x02=positive
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
  let digits = $scaled
  var padded = ""
  for j in 0..<(18 - digits.len):
    padded.add('0')
  padded.add(digits)
  
  result = ""
  result.add(chr(signByte))
  result.add(padded)

proc encodeKey*(global: string, subs: seq[string] = @[]): string =
  ## Encode global[sub1,sub2,...] to LMDB key with M-collation order
  ## Format: global\x00encoded_sub1\x00encoded_sub2\x00...\x00
  ##
  ## For strings: the \x00 separator before the next subscript (or the trailing
  ## \x00) serves as the null terminator. No extra \x00 is added after string content.
  result = global
  for sub in subs:
    result.add('\x00')
    if sub.len == 0:
      # Empty string: single \x00 type byte (sorts first)
      result.add('\x00')
    elif isNumeric(sub):
      # Numeric subscript: type prefix + sign + 18 digits
      try:
        let num = parseFloat(sub)
        result.add('\x01')
        result.add(encodeNumeric(num))
      except:
        # Fallback: treat as string
        result.add('\x02')
        result.add(sub)
    else:
      # String subscript: type prefix + raw bytes
      # The \x00 separator added by the next iteration (or trailing) acts as terminator
      result.add('\x02')
      result.add(sub)
  result.add('\x00')

proc decodeKey*(key: string): (string, seq[string]) =
  ## Decode LMDB key to (global, [sub1, sub2, ...])
  ## Inverse of encodeKey
  ##
  ## Key format:
  ##   global\x00[subtype+data]*\x00
  ## where subtype is:
  ##   \x00 = empty string (immediately followed by next subtype or end-of-key)
  ##   \x01 = number (followed by 19 bytes: sign + 18 digits)
  ##   \x02 = string (followed by bytes until \x00 terminator)
  ##
  ## After the global separator, bytes are a stream of type+data.
  ## End-of-key is detected when the next byte is \x00 AFTER all subscripts
  ## have been consumed. We detect this by checking if we've consumed all bytes
  ## or if the next type byte indicates a new subscript.
  var parts: seq[string] = @[]
  var globalName = ""
  var i = 0
  
  # Find global name (everything before first \x00)
  while i < key.len and key[i] != '\x00':
    i += 1
  globalName = key[0..<i]
  i += 1  # skip the \x00 separator after global
  
  # Decode subscripts — the stream after global separator is:
  #   type_byte [data]* type_byte [data]* ... \x00 (end-of-key)
  # We read until we hit end-of-key (\x00 with no preceding type context)
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
          let absVal = parseInt(digits)
          var num: float64
          if signByte == '\x00':  # negative
            num = -absVal.float64 / 1_000_000_000_000.0
          elif signByte == '\x01':  # zero
            num = 0.0
          else:  # positive
            num = absVal.float64 / 1_000_000_000_000.0
          
          if num == floor(num) and abs(num) < 1e15:
            parts.add($int(num))
          else:
            parts.add($num)
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
      # After skipping, check if we've consumed everything
      # If next byte is \x00, it's the end-of-key marker
      # If next byte is \x01/\x02, it's the next subscript
    else:
      break
    
    # After processing a subscript, check if we've reached end-of-key
    # End-of-key is: we've consumed all bytes, OR next byte is \x00
    if i >= key.len:
      break
    if key[i] == '\x00':
      # This \x00 could be end-of-key OR an empty string subscript
      # Peek ahead: if there's a valid type byte after this \x00, it's an empty string
      if i + 1 < key.len:
        let nextType = key[i + 1]
        if nextType == '\x01' or nextType == '\x02':
          # This \x00 is an empty string subscript, not end-of-key
          continue
      # End-of-key
      break
  
  result = (globalName, parts)

proc mCollationCmp*(a, b: string): int =
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
