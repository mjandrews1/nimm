# key_encoding.nim — M/MUMPS key encoding for LMDB
# Encodes global references to LMDB keys with M-collation

import strutils
import algorithm

proc encodeKey*(global: string, subs: seq[string] = @[]): string =
  ## Encode global[sub1,sub2,...] to LMDB key
  ## Format: global\x00sub1\x00sub2\x00...\x00
  result = global
  for sub in subs:
    result.add('\0')
    result.add(sub)
  result.add('\0')

proc decodeKey*(key: string): (string, seq[string]) =
  ## Decode LMDB key to (global, [sub1, sub2, ...])
  var parts: seq[string] = @[]
  var current = ""
  var isFirst = true
  for ch in key:
    if ch == '\0':
      if isFirst:
        result[0] = current
        isFirst = false
      else:
        if current.len > 0:
          result[1].add(current)
      current = ""
    else:
      current.add(ch)
  
  # Handle trailing content (shouldn't happen with proper encoding)
  if current.len > 0:
    if isFirst:
      result[0] = current
    else:
      result[1].add(current)

proc mCollationCmp*(a, b: string): int =
  ## M-collation comparison: numeric before string
  ## Empty string sorts first
  if a.len == 0 and b.len == 0: return 0
  if a.len == 0: return -1
  if b.len == 0: return 1
  
  # Check if both are numeric
  let aIsNum = a[0] in {'0'..'9', '-', '.'}
  let bIsNum = b[0] in {'0'..'9', '-', '.'}
  
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
