# mcp_server.nim — MCP JSON-RPC server for nimm
# Implements Model Context Protocol server with auth and audit logging
# Uses synchronous HTTP server for cross-platform compatibility

import json
import strutils
import tables
import times
import os
import net

type
  AuditEntry = object
    timestamp: string
    clientIp: string
    httpMethod: string
    toolName: string
    params: string
    response: string

  MCPServer* = ref object
    ## MCP JSON-RPC server
    port*: int
    apiKey*: string
    tools*: Table[string, proc(params: JsonNode): JsonNode]
    toolDescriptions*: Table[string, string]
    toolSchemas*: Table[string, JsonNode]
    auditLog*: seq[AuditEntry]
    auditFile*: string

proc newMCPServer*(port: int = 8080, apiKey: string = ""): MCPServer =
  new(result)
  result.port = port
  result.apiKey = apiKey
  result.tools = initTable[string, proc(params: JsonNode): JsonNode]()
  result.toolDescriptions = initTable[string, string]()
  result.toolSchemas = initTable[string, JsonNode]()
  result.auditLog = @[]
  result.auditFile = ""

proc setAuditFile*(server: var MCPServer, path: string) =
  server.auditFile = path

proc logAudit(server: MCPServer, clientIp: string, httpMethod: string, toolName: string, params: string, response: string) =
  let entry = AuditEntry(
    timestamp: $now(),
    clientIp: clientIp,
    httpMethod: httpMethod,
    toolName: toolName,
    params: params,
    response: response
  )
  server.auditLog.add(entry)
  if server.auditFile.len > 0:
    try:
      let f = open(server.auditFile, fmAppend)
      f.writeLine(entry.timestamp & " | " & clientIp & " | " & httpMethod & " | " & toolName & " | " & params & " | " & response)
      f.close()
    except: discard

proc registerTool*(server: var MCPServer, name: string, description: string, schema: JsonNode, handler: proc(params: JsonNode): JsonNode) =
  server.tools[name] = handler
  server.toolDescriptions[name] = description
  server.toolSchemas[name] = schema

proc checkAuth(server: MCPServer, headers: string): bool =
  if server.apiKey.len == 0: return true
  if "X-API-Key: " & server.apiKey in headers: return true
  if "Authorization: Bearer " & server.apiKey in headers: return true
  return false

proc handleRequest(server: MCPServer, clientIp: string, headers: string, body: string): string =
  if not server.checkAuth(headers):
    server.logAudit(clientIp, "auth", "", "", "401")
    return $ %*{"jsonrpc": "2.0", "error": {"code": -32000, "message": "Unauthorized"}}

  try:
    let request = parseJson(body)
    if request.hasKey("method"):
      let httpMethod = request["method"].getStr()
      let params = if request.hasKey("params"): request["params"] else: newJObject()
      let id = if request.hasKey("id"): request["id"] else: newJNull()

      case httpMethod
      of "initialize":
        server.logAudit(clientIp, "initialize", "", "", "OK")
        return $ %*{"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "nimm-mcp", "version": "0.1.8"}}}
      of "tools/list":
        var tools: seq[JsonNode] = @[]
        for name, _ in server.tools:
          let desc = if name in server.toolDescriptions: server.toolDescriptions[name] else: "Tool: " & name
          let schema = if name in server.toolSchemas: server.toolSchemas[name] else: %*{"type": "object", "properties": {}}
          tools.add(%*{"name": name, "description": desc, "inputSchema": schema})
        server.logAudit(clientIp, "tools/list", "", "", "OK")
        return $ %*{"jsonrpc": "2.0", "id": id, "result": {"tools": tools}}
      of "tools/call":
        let toolName = params["name"].getStr()
        let toolParams = if params.hasKey("arguments"): params["arguments"] else: newJObject()
        if toolName in server.tools:
          let result = server.tools[toolName](toolParams)
          server.logAudit(clientIp, "tools/call", toolName, $toolParams, "OK")
          return $ %*{"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": $result}]}}
        else:
          server.logAudit(clientIp, "tools/call", toolName, $toolParams, "Error")
          return $ %*{"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found: " & toolName}}
      else:
        server.logAudit(clientIp, httpMethod, "", "", "Error")
        return $ %*{"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found: " & httpMethod}}
    else:
      server.logAudit(clientIp, "invalid", "", "", "Error")
      return $ %*{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid request"}}
  except:
    server.logAudit(clientIp, "parse_error", "", "", "Error")
    return $ %*{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}}

proc start*(server: MCPServer) =
  echo "MCP server starting on port ", server.port
  if server.apiKey.len > 0:
    echo "Authentication: enabled (API key required)"
  else:
    echo "Authentication: disabled"
  if server.auditFile.len > 0:
    echo "Audit log: ", server.auditFile

  var sock = newSocket()
  sock.setSockOpt(OptReuseAddr, true)
  sock.bindAddr(Port(server.port))
  sock.listen()
  echo "Listening on port ", server.port, "..."

  while true:
    var client: Socket
    sock.accept(client)
    try:
      # Read HTTP request — single recv with large buffer
      var data = ""
      var headerEnd = -1
      var contentLength = 0

      # Read full request (MCP requests are small, <8KB)
      var chunk = newString(16384)
      let bytesRead = client.recv(chunk, 16384)
      if bytesRead <= 0:
        client.close()
        continue
      data = chunk[0..<bytesRead]

      # Find end of headers
      headerEnd = data.find("\r\n\r\n")
      if headerEnd < 0:
        client.close()
        continue

      # Extract Content-Length
      let headerPart = data[0..<headerEnd]
      for line in headerPart.split("\r\n"):
        if line.startsWith("Content-Length:"):
          contentLength = parseInt(line[15..^1].strip())

      # Get body from initial read
      let bodyStart = headerEnd + 4
      var body = data[bodyStart..<data.len]

      # Read remaining body if needed
      while body.len < contentLength:
        var more = newString(4096)
        let moreBytes = client.recv(more, 4096)
        if moreBytes <= 0: break
        body.add(more[0..<moreBytes])

      let response = server.handleRequest("client", headerPart, body)
      let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " & $response.len & "\r\nConnection: close\r\n\r\n" & response
      client.send(httpResponse)
    except:
      discard
    finally:
      client.close()
