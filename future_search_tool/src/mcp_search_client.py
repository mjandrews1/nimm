#!/usr/bin/env python3
"""
MCP Search Client for NimM FST
Connects to nimm MCP server and performs search operations.

Usage:
  python3 mcp_search_client.py [--host HOST] [--port PORT] [--api-key KEY]

Examples:
  python3 mcp_search_client.py --port 9999 --api-key test123
  python3 mcp_search_client.py --host 192.168.0.103 --port 9999
"""

import argparse
import json
import sys
import urllib.request
import urllib.error


class MCPClient:
    def __init__(self, host: str = "localhost", port: int = 8080, api_key: str = ""):
        self.url = f"http://{host}:{port}"
        self.api_key = api_key
        self.request_id = 0

    def _call(self, method: str, params: dict = None) -> dict:
        """Make a JSON-RPC call to the MCP server."""
        self.request_id += 1
        payload = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": method,
        }
        if params:
            payload["params"] = params

        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["X-API-Key"] = self.api_key

        req = urllib.request.Request(
            self.url,
            data=json.dumps(payload).encode(),
            headers=headers,
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            return {"error": f"HTTP {e.code}: {e.reason}"}
        except urllib.error.URLError as e:
            return {"error": f"Connection error: {e.reason}"}
        except Exception as e:
            return {"error": str(e)}

    def initialize(self) -> dict:
        """Initialize connection to MCP server."""
        return self._call("initialize")

    def list_tools(self) -> dict:
        """List available tools."""
        return self._call("tools/list")

    def call_tool(self, name: str, arguments: dict = None) -> dict:
        """Call a tool with arguments."""
        params = {"name": name}
        if arguments:
            params["arguments"] = arguments
        return self._call("tools/call", params)

    def execute_m_code(self, code: str) -> dict:
        """Execute M code and return output."""
        return self.call_tool("execute_m_code", {"code": code})

    def read_global(self, name: str, subscripts: list = None) -> dict:
        """Read a global variable value."""
        args = {"name": name}
        if subscripts:
            args["subscripts"] = subscripts
        return self.call_tool("read_global", args)

    def search_index(self, prefix: str = "") -> dict:
        """Index globals for search."""
        args = {}
        if prefix:
            args["prefix"] = prefix
        return self.call_tool("search_index", args)

    def search_query(self, query: str, record_type: str = "", top_k: int = 10) -> dict:
        """Search indexed data."""
        args = {"query": query, "topK": top_k}
        if record_type:
            args["type"] = record_type
        return self.call_tool("search_query", args)

    def search_links(self, record_type: str, record_id: str) -> dict:
        """Find related records."""
        return self.call_tool("search_links", {"type": record_type, "id": record_id})


def print_result(result: dict):
    """Pretty-print a JSON-RPC result."""
    if "error" in result:
        print(f"Error: {result['error']}")
        return
    if "result" in result:
        content = result["result"].get("content", [])
        for item in content:
            if item.get("type") == "text":
                try:
                    data = json.loads(item["text"])
                    print(json.dumps(data, indent=2))
                except json.JSONDecodeError:
                    print(item["text"])
    elif "error" in result:
        print(f"Error: {result['error'].get('message', result['error'])}")


def interactive_mode(client: MCPClient):
    """Interactive REPL for MCP search."""
    print("MCP Search Client")
    print("=================")
    print("Commands:")
    print("  init                    - Initialize connection")
    print("  tools                   - List available tools")
    print("  exec <code>             - Execute M code")
    print("  read <global> [subs...] - Read global variable")
    print("  index [prefix]          - Index globals for search")
    print("  search <query> [type]   - Search indexed data")
    print("  links <type> <id>       - Find related records")
    print("  quit                    - Exit")
    print()

    while True:
        try:
            line = input("mcp> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not line:
            continue

        parts = line.split(None, 1)
        cmd = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""

        if cmd in ("quit", "exit", "q"):
            break
        elif cmd == "init":
            print_result(client.initialize())
        elif cmd == "tools":
            result = client.list_tools()
            if "result" in result:
                tools = result["result"].get("tools", [])
                for t in tools:
                    print(f"  {t['name']}: {t.get('description', '')}")
            else:
                print_result(result)
        elif cmd == "exec":
            if not args:
                print("Usage: exec <M code>")
                continue
            print_result(client.execute_m_code(args))
        elif cmd == "read":
            if not args:
                print("Usage: read <global> [subs...]")
                continue
            parts = args.split()
            name = parts[0]
            subs = parts[1:] if len(parts) > 1 else None
            print_result(client.read_global(name, subs))
        elif cmd == "index":
            print_result(client.search_index(args))
        elif cmd == "search":
            if not args:
                print("Usage: search <query> [type]")
                continue
            parts = args.split(None, 1)
            query = parts[0]
            record_type = parts[1] if len(parts) > 1 else ""
            print_result(client.search_query(query, record_type))
        elif cmd == "links":
            if not args:
                print("Usage: links <type> <id>")
                continue
            parts = args.split()
            if len(parts) < 2:
                print("Usage: links <type> <id>")
                continue
            print_result(client.search_links(parts[0], parts[1]))
        else:
            print(f"Unknown command: {cmd}")
            print("Type 'help' for available commands")


def main():
    parser = argparse.ArgumentParser(description="MCP Search Client for NimM FST")
    parser.add_argument("--host", default="localhost", help="MCP server host")
    parser.add_argument("--port", type=int, default=8080, help="MCP server port")
    parser.add_argument("--api-key", default="", help="API key for authentication")
    parser.add_argument("--command", "-c", help="Execute single command and exit")
    args = parser.parse_args()

    client = MCPClient(args.host, args.port, args.api_key)

    if args.command:
        # Single command mode
        parts = args.command.split(None, 1)
        cmd = parts[0].lower()
        cmd_args = parts[1] if len(parts) > 1 else ""

        if cmd == "init":
            print_result(client.initialize())
        elif cmd == "tools":
            result = client.list_tools()
            if "result" in result:
                tools = result["result"].get("tools", [])
                for t in tools:
                    print(f"  {t['name']}: {t.get('description', '')}")
            else:
                print_result(result)
        elif cmd == "exec":
            print_result(client.execute_m_code(cmd_args))
        elif cmd == "search":
            parts = cmd_args.split(None, 1)
            query = parts[0]
            record_type = parts[1] if len(parts) > 1 else ""
            print_result(client.search_query(query, record_type))
        else:
            print(f"Unknown command: {cmd}")
            sys.exit(1)
    else:
        # Interactive mode
        interactive_mode(client)


if __name__ == "__main__":
    main()
