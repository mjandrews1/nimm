# mcp_server.nim — MCP JSON-RPC server for nimm
# Implements Model Context Protocol server

import asynchttpserver
import asyncdispatch
import json
import strutils
import tables

type
  MCPServer* = ref object
    ## MCP JSON-RPC server
    port*: int
    tools*: Table[string, proc(params: JsonNode): JsonNode]

proc newMCPServer*(port: int = 8080): MCPServer =
  result.port = port
  result.tools = initTable[string, proc(params: JsonNode): JsonNode]()

proc registerTool*(server: var MCPServer, name: string, handler: proc(params: JsonNode): JsonNode) =
  ## Register a tool handler
  server.tools[name] = handler

proc handleRequest*(server: MCPServer, req: Request): Future[void] {.async.} =
  ## Handle HTTP request
  let body = req.body
  var response: JsonNode
  
  try:
    let request = parseJson(body)
    
    if request.hasKey("method"):
      let method = request["method"].getStr()
      let params = if request.hasKey("params"): request["params"] else: newJObject()
      let id = if request.hasKey("id"): request["id"] else: newJNull()
      
      case method
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
              "version": "1.0.0"
            }
          }
        }
      of "tools/list":
        var tools: seq[JsonNode] = @[]
        for name, _ in server.tools:
          tools.add(%*{
            "name": name,
            "description": "Tool: " & name,
            "inputSchema": {
              "type": "object",
              "properties": {}
            }
          })
        response = %*{
          "jsonrpc": "2.0",
          "id": id,
          "result": {
            "tools": tools
          }
        }
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
        else:
          response = %*{
            "jsonrpc": "2.0",
            "id": id,
            "error": {
              "code": -32601,
              "message": "Method not found: " & toolName
            }
          }
      else:
        response = %*{
          "jsonrpc": "2.0",
          "id": id,
          "error": {
            "code": -32601,
            "message": "Method not found: " & method
          }
        }
    else:
      response = %*{
        "jsonrpc": "2.0",
        "error": {
          "code": -32600,
          "message": "Invalid request"
        }
      }
  except:
    response = %*{
      "jsonrpc": "2.0",
      "error": {
        "code": -32700,
        "message": "Parse error"
      }
    }
  
  await req.respond(Http200, $response, newHttpHeaders([("Content-Type", "application/json")]))

proc start*(server: MCPServer) =
  ## Start the MCP server
  echo "MCP server starting on port ", server.port
  
  var httpServer = newAsyncHttpServer()
  
  proc handler(req: Request) {.async.} =
    await server.handleRequest(req)
  
  waitFor httpServer.serve(Port(server.port), handler)
