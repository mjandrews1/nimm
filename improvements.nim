# improvements.nim — Additional improvements for nimm
# Implements $FNUMBER, $CASE, $QUERY, ZSYSTEM

import strutils
import tables
import os

proc fnumber*(value: float, format: string = "", precision: int = 0): string =
  ## $FNUMBER: Number formatting with decimal places
  ## Format flags: + (force sign), P (parentheses for negative)
  ## Note: Comma formatting not yet implemented
  
  # Format the number with precision
  var s = ""
  if precision > 0:
    s = formatFloat(value, ffDecimal, precision)
  else:
    if value == float(int(value)):
      s = $int(value)
    else:
      s = $value
  
  # Apply sign
  if '+' in format and value >= 0:
    s = "+" & s
  elif 'P' in format and value < 0:
    s = "(" & s[1..^1] & ")"
  
  return s

proc `case`*(expr: string, pairs: seq[(string, string)], default: string = ""): string =
  ## $CASE: Switch/case function
  ## pairs: seq of (value, result)
  for (val, res) in pairs:
    if expr == val:
      return res
  return default

proc query*(data: Table[string, string], key: string, direction: int = 1): string =
  ## $QUERY: Find next/previous defined node
  ## direction: 1 = forward, -1 = backward
  
  # Collect keys
  var sortedKeys: seq[string] = @[]
  for k in data.keys:
    sortedKeys.add(k)
  
  if sortedKeys.len == 0:
    return ""
  
  # Simple sort (bubble sort for simplicity)
  for i in 0..<sortedKeys.len - 1:
    for j in 0..<sortedKeys.len - i - 1:
      if sortedKeys[j] > sortedKeys[j + 1]:
        let tmp = sortedKeys[j]
        sortedKeys[j] = sortedKeys[j + 1]
        sortedKeys[j + 1] = tmp
  
  # Find current key position
  var pos = -1
  for i, k in sortedKeys:
    if k == key:
      pos = i
      break
  
  if pos < 0:
    # Key not found, return first/last
    if direction > 0:
      return sortedKeys[0]
    else:
      return sortedKeys[sortedKeys.len - 1]
  
  # Return next/previous
  let newPos = pos + direction
  if newPos >= 0 and newPos < sortedKeys.len:
    return sortedKeys[newPos]
  
  return ""

proc zsystem*(command: string): int =
  ## ZSYSTEM: Execute OS command
  ## Returns exit code
  return execShellCmd(command)
