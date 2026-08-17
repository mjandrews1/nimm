# ni_functions.nim — $NI functions for nimm
# Implements $NI_HTTP, $NI_JSON, $NI_UUID, $NI_SLEEP

import httpclient
import json
import os
import strutils
import times

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
  
  # Use /dev/urandom for random bytes
  var bytes: array[16, uint8]
  let f = open("/dev/urandom")
  discard f.readBytes(bytes, 0, 16)
  f.close()
  
  # Set version (4) and variant (10)
  bytes[6] = (bytes[6] and 0x0f'u8) or 0x40'u8
  bytes[8] = (bytes[8] and 0x3f'u8) or 0x80'u8
  
  # Format as UUID string
  result = ""
  for i in 0..3:
    result.add(bytes[i].toHex(2))
  result.add('-')
  for i in 4..5:
    result.add(bytes[i].toHex(2))
  result.add('-')
  for i in 6..7:
    result.add(bytes[i].toHex(2))
  result.add('-')
  for i in 8..9:
    result.add(bytes[i].toHex(2))
  result.add('-')
  for i in 10..15:
    result.add(bytes[i].toHex(2))
  result = result.toLowerAscii()

proc niSleep*(seconds: float) =
  ## $NI_SLEEP: Sleep for specified seconds
  os.sleep(int(seconds * 1000))
