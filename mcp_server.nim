# mcp_server.nim — MCP JSON-RPC server for nimm
# Implements Model Context Protocol server with auth and audit logging

{.push warning[GCUnsafe]: off.}

import asynchttpserver
import asyncdispatch
import json
import strutils
import tables
import times
import os

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

var auditLog {.threadvar.}: seq[AuditEntry]
var auditLogFile {.threadvar.}: string

proc newMCPServer*(port: int = 8080, apiKey: string = ""): MCPServer =
  result.port = port
  result.apiKey = apiKey
  result.tools = initTable[string, proc(params: JsonNode): JsonNode]()
  result.toolDescriptions = initTable[string, string]()
  result.toolSchemas = initTable[string, JsonNode]()

proc setAuditFile*(path: string) =
  ## Set audit log file path
  auditLogFile = path

proc logAudit(clientIp: string, httpMethod: string, toolName: string, params: string, response: string) {.gcsafe.} =
  ## Log an audit entry (in-memory only)
  let entry = AuditEntry(
    timestamp: $now(),
    clientIp: clientIp,
    httpMethod: httpMethod,
    toolName: toolName,
    params: params,
    response: response
  )
  auditLog.add(entry)

proc registerTool*(server: var MCPServer, name: string, description: string, schema: JsonNode, handler: proc(params: JsonNode): JsonNode) =
  ## Register a tool handler with description and schema
  server.tools[name] = handler
  server.toolDescriptions[name] = description
  server.toolSchemas[name] = schema

proc checkAuth(server: MCPServer, req: Request): bool =
  ## Check API key authentication
  if server.apiKey.len == 0:
    return true  # No auth required
  
  # Check Authorization header
  let authHeader = req.headers.getOrDefault("Authorization")
  if authHeader.startsWith("Bearer "):
    let token = authHeader[7..^1]
    return token == server.apiKey
  
  # Check X-API-Key header
  let apiKeyHeader = req.headers.getOrDefault("X-API-Key")
  if apiKeyHeader.len > 0:
    return apiKeyHeader == server.apiKey
  
  return false

proc handleRequest*(server: MCPServer, req: Request): Future[void] {.async.} =
  ## Handle HTTP request
  let clientIp = req.hostname
  let body = req.body
  var response: JsonNode
  
  # Check authentication
  if not server.checkAuth(req):
    response = %*{
      "jsonrpc": "2.0",
      "error": {
        "code": -32000,
        "message": "Unauthorized: invalid or missing API key"
      }
    }
    logAudit(clientIp, "auth", "", "", "401 Unauthorized")
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
        response = %*{
          "jsonrpc": "2.0",
          "id": id,
          "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
              "tools": {}
            },
            "serverInfo": {
              "name": "nimm-mcp",
              "version": "0.1.6"
            }
          }
        }
        logAudit(clientIp, "initialize", "", "", "OK")
        
      of "tools/list":
        var tools: seq[JsonNode] = @[]
        for name, _ in server.tools:
          let desc = if name in server.toolDescriptions: server.toolDescriptions[name] else: "Tool: " & name
          let schema = if name in server.toolSchemas: server.toolSchemas[name] else: %*{"type": "object", "properties": {}}
          tools.add(%*{
            "name": name,
            "description": desc,
            "inputSchema": schema
          })
        response = %*{
          "jsonrpc": "2.0",
          "id": id,
          "result": {
            "tools": tools
          }
        }
        logAudit(clientIp, "tools/list", "", "", "OK")
        
      of "tools/call":
        let toolName = params["name"].getStr()
        let toolParams = if params.hasKey("arguments"): params["arguments"] else: newJObject()
        
        if toolName in server.tools:
          let result = server.tools[toolName](toolParams)
          response = %*{
            "jsonrpc": "2.0",
            "id": id,
            "result": {
              "content": [
                {
                  "type": "text",
                  "text": $result
                }
              ]
            }
          }
          logAudit(clientIp, "tools/call", toolName, $toolParams, "OK")
        else:
          response = %*{
            "jsonrpc": "2.0",
            "id": id,
            "error": {
              "code": -32601,
              "message": "Method not found: " & toolName
            }
          }
          logAudit(clientIp, "tools/call", toolName, $toolParams, "Error: method not found")
      else:
        response = %*{
          "jsonrpc": "2.0",
          "id": id,
          "error": {
            "code": -32601,
            "message": "Method not found: " & httpMethod
          }
        }
        logAudit(clientIp, httpMethod, "", "", "Error: method not found")
    else:
      response = %*{
        "jsonrpc": "2.0",
        "error": {
          "code": -32600,
          "message": "Invalid request"
        }
      }
      logAudit(clientIp, "invalid", "", "", "Error: invalid request")
  except:
    response = %*{
      "jsonrpc": "2.0",
      "error": {
        "code": -32700,
        "message": "Parse error"
      }
    }
    logAudit(clientIp, "parse_error", "", "", "Error: parse error")
  
  await req.respond(Http200, $response, newHttpHeaders([("Content-Type", "application/json")]))

proc start*(server: MCPServer) {.gcsafe.} =
  ## Start the MCP server
  echo "MCP server starting on port ", server.port
  if server.apiKey.len > 0:
    echo "Authentication: enabled (API key required)"
  else:
    echo "Authentication: disabled (no API key set)"
  if auditLogFile.len > 0:
    echo "Audit log: ", auditLogFile
  
  var httpServer = newAsyncHttpServer()
  
  proc handler(req: Request) {.async.} =
    {.cast(gcsafe).}:
      await server.handleRequest(req)
  
  waitFor httpServer.serve(Port(server.port), handler)
