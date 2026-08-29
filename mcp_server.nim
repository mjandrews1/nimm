# mcp_server.nim — MCP JSON-RPC server for nimm
# Implements Model Context Protocol server with auth and audit logging
# Uses asynchttpserver with asyncCheck+poll for cross-platform compat

import asynchttpserver
import asyncdispatch
import json
import strutils
import tables
import times

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
    httpServer*: AsyncHttpServer

proc newMCPServer*(port: int = 8080, apiKey: string = ""): MCPServer =
  new(result)
  result.port = port
  result.apiKey = apiKey
  result.tools = initTable[string, proc(params: JsonNode): JsonNode]()
  result.toolDescriptions = initTable[string, string]()
  result.toolSchemas = initTable[string, JsonNode]()
  result.auditLog = @[]
  result.auditFile = ""
  result.httpServer = newAsyncHttpServer()

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

proc checkAuth(server: MCPServer, req: Request): bool =
  if server.apiKey.len == 0: return true
  let authHeader = req.headers.getOrDefault("Authorization")
  if authHeader.startsWith("Bearer "):
    return authHeader[7..^1] == server.apiKey
  let apiKeyHeader = req.headers.getOrDefault("X-API-Key")
  if apiKeyHeader.len > 0:
    return apiKeyHeader == server.apiKey
  return false

proc handleRequest*(server: MCPServer, req: Request): Future[void] {.async.} =
  let clientIp = req.hostname
  let body = req.body
  var response: JsonNode

  if not server.checkAuth(req):
    response = %*{"jsonrpc": "2.0", "error": {"code": -32000, "message": "Unauthorized"}}
    server.logAudit(clientIp, "auth", "", "", "401")
    await req.respond(Http401, $response, newHttpHeaders([("Content-Type", "application/json")]))
    return

  try:
    let request = parseJson(body)
    if request.hasKey("method"):
      let httpMethod = request["method"].getStr()
      let params = if request.hasKey("params"): request["params"] else: newJObject()
      let id = if request.hasKey("id"): request["id"] else: newJNull()

      case httpMethod
      of "initialize":
        response = %*{"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "nimm-mcp", "version": "0.1.6"}}}
        server.logAudit(clientIp, "initialize", "", "", "OK")
      of "tools/list":
        var tools: seq[JsonNode] = @[]
        for name, _ in server.tools:
          let desc = if name in server.toolDescriptions: server.toolDescriptions[name] else: "Tool: " & name
          let schema = if name in server.toolSchemas: server.toolSchemas[name] else: %*{"type": "object", "properties": {}}
          tools.add(%*{"name": name, "description": desc, "inputSchema": schema})
        response = %*{"jsonrpc": "2.0", "id": id, "result": {"tools": tools}}
        server.logAudit(clientIp, "tools/list", "", "", "OK")
      of "tools/call":
        let toolName = params["name"].getStr()
        let toolParams = if params.hasKey("arguments"): params["arguments"] else: newJObject()
        if toolName in server.tools:
          let result = server.tools[toolName](toolParams)
          response = %*{"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": $result}]}}
          server.logAudit(clientIp, "tools/call", toolName, $toolParams, "OK")
        else:
          response = %*{"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found: " & toolName}}
          server.logAudit(clientIp, "tools/call", toolName, $toolParams, "Error")
      else:
        response = %*{"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found: " & httpMethod}}
        server.logAudit(clientIp, httpMethod, "", "", "Error")
    else:
      response = %*{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid request"}}
      server.logAudit(clientIp, "invalid", "", "", "Error")
  except:
    response = %*{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}}
    server.logAudit(clientIp, "parse_error", "", "", "Error")

  await req.respond(Http200, $response, newHttpHeaders([("Content-Type", "application/json")]))

proc start*(server: MCPServer) =
  echo "MCP server starting on port ", server.port
  if server.apiKey.len > 0:
    echo "Authentication: enabled (API key required)"
  else:
    echo "Authentication: disabled"
  if server.auditFile.len > 0:
    echo "Audit log: ", server.auditFile

  proc handler(req: Request) {.async.} =
    {.cast(gcsafe).}:
      await server.handleRequest(req)

  # Use asyncCheck + poll instead of waitFor for cross-platform compat
  asyncCheck server.httpServer.serve(Port(server.port), handler)
  echo "Listening on port ", server.port, "..."
  runForever()
