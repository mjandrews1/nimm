#!/usr/bin/env python3
"""
FST MCP Server — MCP server for FST search functionality.
Provides search tools for NLM data loaded in NimM's LMDB.

Usage:
  python3 fst_mcp_server.py --db /path/to/fst.lmdb [--port 8080]
"""

import argparse
import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from fst_search import search_descriptors, get_descriptor_details, get_all_globals


class MCPHandler(BaseHTTPRequestHandler):
    """HTTP handler for MCP JSON-RPC requests."""
    
    db_path = None
    
    def do_POST(self):
        """Handle POST requests (JSON-RPC)."""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        try:
            request = json.loads(body)
            response = self.handle_request(request)
        except Exception as e:
            response = {
                "jsonrpc": "2.0",
                "error": {"code": -32603, "message": str(e)},
                "id": None
            }
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())
    
    def handle_request(self, request):
        """Handle JSON-RPC request."""
        method = request.get("method")
        params = request.get("params", {})
        request_id = request.get("id")
        
        if method == "initialize":
            return self.handle_initialize(params, request_id)
        elif method == "tools/list":
            return self.handle_tools_list(params, request_id)
        elif method == "tools/call":
            return self.handle_tools_call(params, request_id)
        else:
            return {
                "jsonrpc": "2.0",
                "error": {"code": -32601, "message": f"Method not found: {method}"},
                "id": request_id
            }
    
    def handle_initialize(self, params, request_id):
        """Handle initialize request."""
        return {
            "jsonrpc": "2.0",
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fst-mcp-server", "version": "0.1.0"}
            },
            "id": request_id
        }
    
    def handle_tools_list(self, params, request_id):
        """Handle tools/list request."""
        tools = [
            {
                "name": "search_descriptors",
                "description": "Search MeSH descriptors using BM25 ranking",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "Search query"},
                        "max_results": {"type": "integer", "description": "Max results (default 20)"}
                    },
                    "required": ["query"]
                }
            },
            {
                "name": "get_descriptor",
                "description": "Get full details for a MeSH descriptor",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "desc_ui": {"type": "string", "description": "Descriptor UI (e.g., D000001)"}
                    },
                    "required": ["desc_ui"]
                }
            },
            {
                "name": "list_globals",
                "description": "List all values for a global variable",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "global_name": {"type": "string", "description": "Global name (e.g., MESH, QUAL)"}
                    },
                    "required": ["global_name"]
                }
            }
        ]
        return {"jsonrpc": "2.0", "result": {"tools": tools}, "id": request_id}
    
    def handle_tools_call(self, params, request_id):
        """Handle tools/call request."""
        tool_name = params.get("name")
        arguments = params.get("arguments", {})
        
        try:
            if tool_name == "search_descriptors":
                query = arguments.get("query", "")
                max_results = arguments.get("max_results", 20)
                results = search_descriptors(self.db_path, query, max_results)
                content = []
                for desc_ui, name, score in results:
                    content.append({"type": "text", "text": f"[{desc_ui}] {name} (score: {score:.3f})"})
                return {"jsonrpc": "2.0", "result": {"content": content}, "id": request_id}
            
            elif tool_name == "get_descriptor":
                desc_ui = arguments.get("desc_ui", "")
                details = get_descriptor_details(self.db_path, desc_ui)
                content = [{"type": "text", "text": json.dumps(details, indent=2)}]
                return {"jsonrpc": "2.0", "result": {"content": content}, "id": request_id}
            
            elif tool_name == "list_globals":
                global_name = arguments.get("global_name", "")
                values = get_all_globals(self.db_path, global_name)
                content = [{"type": "text", "text": json.dumps(values, indent=2)}]
                return {"jsonrpc": "2.0", "result": {"content": content}, "id": request_id}
            
            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {"code": -32601, "message": f"Tool not found: {tool_name}"},
                    "id": request_id
                }
        
        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "error": {"code": -32603, "message": str(e)},
                "id": request_id
            }
    
    def log_message(self, format, *args):
        """Suppress default logging."""
        pass


def main():
    parser = argparse.ArgumentParser(description="FST MCP Server")
    parser.add_argument("--db", required=True, help="LMDB database path")
    parser.add_argument("--port", type=int, default=8080, help="Server port")
    args = parser.parse_args()
    
    MCPHandler.db_path = args.db
    
    server = HTTPServer(('localhost', args.port), MCPHandler)
    print(f"FST MCP Server running on http://localhost:{args.port}")
    print(f"Database: {args.db}")
    print("Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
