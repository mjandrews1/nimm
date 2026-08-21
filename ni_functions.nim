# ni_functions.nim — $NI functions for nimm
# Implements $NI_HTTP, $NI_JSON, $NI_UUID, $NI_SLEEP

import httpclient
import json
import os
import strutils
import times

const hexChars = "0123456789abcdef"

var urandomFile: File
var urandomOpen = false

proc ensureUrandom() =
  if not urandomOpen:
    urandomFile = open("/dev/urandom")
    urandomOpen = true

proc niHttp*(httpMethod: string, url: string, body: string = ""): string =
  ## $NI_HTTP: HTTP client
  ## Returns response body or empty string on error
  
  let client = newHttpClient()
  defer: client.close()
  
  try:
    let m = httpMethod.toUpperAscii()
    var response: Response
    
    case m
    of "GET":
      response = client.get(url)
    of "POST":
      response = client.post(url, body = body)
    of "PUT":
      response = client.put(url, body = body)
    of "DELETE":
      response = client.delete(url)
    of "PATCH":
      response = client.patch(url, body = body)
    else:
      return ""
    
    return response.body
  except:
    return ""

proc niJson*(action: string, data: string): string =
  ## $NI_JSON: JSON parse/stringify
  ## action: "parse" or "stringify"
  
  let a = action.toLowerAscii()
  
  if a == "stringify":
    # Wrap value in JSON string
    try:
      let parsed = parseJson(data)
      return $parsed
    except:
      # Not valid JSON, return as string
      return "\"" & data & "\""
  
  elif a == "parse":
    # Parse JSON and return as string
    try:
      let parsed = parseJson(data)
      return $parsed
    except:
      return ""
  
  return ""

proc niUuid*(): string =
  ## $NI_UUID: Generate UUID v4

  ensureUrandom()

  # Read 16 random bytes
  var bytes: array[16, uint8]
  discard urandomFile.readBytes(bytes, 0, 16)

  # Set version (4) and variant (10)
  bytes[6] = (bytes[6] and 0x0f'u8) or 0x40'u8
  bytes[8] = (bytes[8] and 0x3f'u8) or 0x80'u8

  # Format as UUID string (36 chars + null = 37 byte buffer)
  result = newString(36)
  var pos = 0
  template writeHex(b: uint8) =
    result[pos] = hexChars[b shr 4]
    result[pos+1] = hexChars[b and 0x0f'u8]
    pos += 2

  # 4-2-2-2-6 byte groups separated by dashes
  for i in 0..3: writeHex(bytes[i])
  result[pos] = '-'; inc pos
  for i in 4..5: writeHex(bytes[i])
  result[pos] = '-'; inc pos
  for i in 6..7: writeHex(bytes[i])
  result[pos] = '-'; inc pos
  for i in 8..9: writeHex(bytes[i])
  result[pos] = '-'; inc pos
  for i in 10..15: writeHex(bytes[i])

proc niSleep*(seconds: float) =
  ## $NI_SLEEP: Sleep for specified seconds
  os.sleep(int(seconds * 1000))
