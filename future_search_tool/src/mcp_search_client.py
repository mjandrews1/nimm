#!/usr/bin/env python3
"""
MCP Search Client — Test client for FST MCP server.
Provides command-line interface for testing search functionality.

Usage:
  python3 mcp_search_client.py --host localhost:8080 search "query"
  python3 mcp_search_client.py --host localhost:8080 get D000001
  python3 mcp_search_client.py --host localhost:8080 list MESH
"""

import argparse
import json
import sys
import urllib.request


def mcp_request(host, method, params=None):
    """Send MCP JSON-RPC request."""
    url = f"http://{host}"
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
        "id": 1
    }
    
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None


def search(host, query, max_results=20):
    """Search MeSH descriptors."""
    response = mcp_request(host, "tools/call", {
        "name": "search_descriptors",
        "arguments": {"query": query, "max_results": max_results}
    })
    
    if not response:
        return
    
    result = response.get("result", {})
    content = result.get("content", [])
    
    print(f"Search: {query}")
    print(f"Results: {len(content)}")
    print()
    
    for i, item in enumerate(content, 1):
        print(f"{i:2d}. {item.get('text', '')}")


def get_descriptor(host, desc_ui):
    """Get descriptor details."""
    response = mcp_request(host, "tools/call", {
        "name": "get_descriptor",
        "arguments": {"desc_ui": desc_ui}
    })
    
    if not response:
        return
    
    result = response.get("result", {})
    content = result.get("content", [])
    
    if content:
        details = json.loads(content[0].get("text", "{}"))
        print(f"Descriptor: {desc_ui}")
        print(f"Name: {details.get('name', 'N/A')}")
        if details.get('scopeNote'):
            print(f"Scope: {details['scopeNote'][:200]}...")
        if details.get('treeNumbers'):
            print(f"Trees: {', '.join(details['treeNumbers'][:5])}")
        if details.get('qualifiers'):
            print(f"Qualifiers: {', '.join(q['name'] for q in details['qualifiers'][:5])}")


def list_globals(host, global_name):
    """List all values for a global."""
    response = mcp_request(host, "tools/call", {
        "name": "list_globals",
        "arguments": {"global_name": global_name}
    })
    
    if not response:
        return
    
    result = response.get("result", {})
    content = result.get("content", [])
    
    if content:
        values = json.loads(content[0].get("text", "{}"))
        print(f"Global: {global_name}")
        print(f"Count: {len(values)}")
        print()
        for key, value in list(values.items())[:20]:
            print(f"  {key}: {value}")


def main():
    parser = argparse.ArgumentParser(description="MCP Search Client")
    parser.add_argument("--host", default="localhost:8080", help="MCP server host:port")
    subparsers = parser.add_subparsers(dest="command", help="Command")
    
    # Search command
    search_parser = subparsers.add_parser("search", help="Search MeSH descriptors")
    search_parser.add_argument("query", help="Search query")
    search_parser.add_argument("--max-results", type=int, default=20, help="Max results")
    
    # Get command
    get_parser = subparsers.add_parser("get", help="Get descriptor details")
    get_parser.add_argument("desc_ui", help="Descriptor UI (e.g., D000001)")
    
    # List command
    list_parser = subparsers.add_parser("list", help="List global values")
    list_parser.add_argument("global_name", help="Global name (e.g., MESH, QUAL)")
    
    args = parser.parse_args()
    
    if args.command == "search":
        search(args.host, args.query, args.max_results)
    elif args.command == "get":
        get_descriptor(args.host, args.desc_ui)
    elif args.command == "list":
        list_globals(args.host, args.global_name)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
