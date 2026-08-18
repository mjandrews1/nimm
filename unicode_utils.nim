# unicode.nim — Unicode UTF-8 support for nimm
# Provides UTF-8 validation, string functions, and character classification

import unicode
import strutils

proc isValidUtf8*(s: string): bool =
  ## Validate UTF-8 string
  var i = 0
  while i < s.len:
    let b = uint8(s[i])
    
    if b < 0x80:
      # ASCII
      inc i
    elif (b and 0xE0) == 0xC0:
      # 2-byte sequence
      if i + 1 >= s.len or (uint8(s[i+1]) and 0xC0) != 0x80:
        return false
      i += 2
    elif (b and 0xF0) == 0xE0:
      # 3-byte sequence
      if i + 2 >= s.len or (uint8(s[i+1]) and 0xC0) != 0x80 or (uint8(s[i+2]) and 0xC0) != 0x80:
        return false
      i += 3
    elif (b and 0xF8) == 0xF0:
      # 4-byte sequence
      if i + 3 >= s.len or (uint8(s[i+1]) and 0xC0) != 0x80 or (uint8(s[i+2]) and 0xC0) != 0x80 or (uint8(s[i+3]) and 0xC0) != 0x80:
        return false
      i += 4
    else:
      return false
  
  return true

proc utf8Len*(s: string): int =
  ## Count UTF-8 code points
  result = 0
  var i = 0
  while i < s.len:
    let b = uint8(s[i])
    if b < 0x80:
      inc i
    elif (b and 0xE0) == 0xC0:
      i += 2
    elif (b and 0xF0) == 0xE0:
      i += 3
    elif (b and 0xF8) == 0xF0:
      i += 4
    else:
      inc i
    inc result

proc utf8CharLen*(b: uint8): int =
  ## Get UTF-8 character length from first byte
  if b < 0x80: return 1
  if (b and 0xE0) == 0xC0: return 2
  if (b and 0xF0) == 0xE0: return 3
  if (b and 0xF8) == 0xF0: return 4
  return 1

proc utf8Substring*(s: string, start: int, length: int = -1): string =
  ## Extract substring by UTF-8 code point indices
  if start < 0:
    raise newException(IndexDefect, "utf8Substring start must be non-negative: " & $start)
  if length < -1:
    raise newException(IndexDefect, "utf8Substring length must be >= -1: " & $length)
  
  var startByte = 0
  var i = 0
  
  # Find start byte
  while i < start and startByte < s.len:
    startByte += utf8CharLen(uint8(s[startByte]))
    inc i
  
  if length == 0:
    return ""
  
  # Find end byte
  var endByte = startByte
  if length < 0:
    endByte = s.len
  else:
    i = 0
    while i < length and endByte < s.len:
      endByte += utf8CharLen(uint8(s[endByte]))
      inc i
  
  return s[startByte..<endByte]

proc utf8Reverse*(s: string): string =
  ## Reverse UTF-8 string
  var chars: seq[string] = @[]
  var i = 0
  while i < s.len:
    let len = utf8CharLen(uint8(s[i]))
    chars.add(s[i..<(i+len)])
    i += len
  
  result = ""
  for j in countdown(chars.len - 1, 0):
    result.add(chars[j])

proc utf8ToUpper*(s: string): string =
  ## Convert UTF-8 string to uppercase (ASCII only for now)
  return s.toUpperAscii()

proc utf8ToLower*(s: string): string =
  ## Convert UTF-8 string to lowercase (ASCII only for now)
  return s.toLowerAscii()

proc utf8IsAlpha*(s: string, pos: int = 0): bool =
  ## Check if character at position is alphabetic
  var bytePos = 0
  var i = 0
  while i < pos and bytePos < s.len:
    bytePos += utf8CharLen(uint8(s[bytePos]))
    inc i
  
  if bytePos >= s.len:
    return false
  
  let b = uint8(s[bytePos])
  if b < 128:
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)  # A-Z, a-z
  # Non-ASCII: assume alphabetic for now
  return true

proc utf8IsDigit*(s: string, pos: int = 0): bool =
  ## Check if character at position is a digit
  var bytePos = 0
  var i = 0
  while i < pos and bytePos < s.len:
    bytePos += utf8CharLen(uint8(s[bytePos]))
    inc i
  
  if bytePos >= s.len:
    return false
  
  let b = uint8(s[bytePos])
  return b >= 48 and b <= 57  # 0-9

proc utf8IsAlphaNum*(s: string, pos: int = 0): bool =
  ## Check if character at position is alphanumeric
  return utf8IsAlpha(s, pos) or utf8IsDigit(s, pos)

proc utf8CodePointAt*(s: string, pos: int): int =
  ## Get code point at position
  var bytePos = 0
  var i = 0
  while i < pos and bytePos < s.len:
    bytePos += utf8CharLen(uint8(s[bytePos]))
    inc i
  
  if bytePos >= s.len:
    return -1
  
  let b0 = int(uint8(s[bytePos]))
  if b0 < 128:
    return b0
  elif (b0 and 0xE0) == 0xC0:
    let b1 = int(uint8(s[bytePos+1])) and 0x3F
    return ((b0 and 0x1F) shl 6) or b1
  elif (b0 and 0xF0) == 0xE0:
    let b1 = int(uint8(s[bytePos+1])) and 0x3F
    let b2 = int(uint8(s[bytePos+2])) and 0x3F
    return ((b0 and 0x0F) shl 12) or (b1 shl 6) or b2
  elif (b0 and 0xF8) == 0xF0:
    let b1 = int(uint8(s[bytePos+1])) and 0x3F
    let b2 = int(uint8(s[bytePos+2])) and 0x3F
    let b3 = int(uint8(s[bytePos+3])) and 0x3F
    return ((b0 and 0x07) shl 18) or (b1 shl 12) or (b2 shl 6) or b3
  return -1

proc utf8FromCodePoint*(cp: int): string =
  ## Convert code point to UTF-8 string
  let rune = unicode.Rune(cp)
  return unicode.toUTF8(rune)
