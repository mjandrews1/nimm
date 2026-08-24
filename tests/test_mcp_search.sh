#!/bin/bash
# test_mcp_search.sh — Test MCP search client
# Usage: ./tests/test_mcp_search.sh [host:port]

set -e

HOST="${1:-localhost:8080}"
CLIENT="python3 future_search_tool/src/mcp_search_client.py"

echo "=== MCP Search Test Suite ==="
echo "Target: $HOST"
echo

# Test1: Health check
echo "Test 1: Health check"
if curl -s "http://$HOST/health" | grep -q "ok"; then
    echo "  PASS: Server is healthy"
else
    echo "  FAIL: Server not responding"
    exit 1
fi

# Test2: Search for Calcimycin
echo "Test 2: Search for Calcimycin"
RESULT=$($CLIENT --host "$HOST" search "Calcimycin" 2>&1)
if echo "$RESULT" | grep -q "D000001"; then
    echo "  PASS: Found D000001"
else
    echo "  FAIL: D000001 not found"
    exit 1
fi

# Test3: Search for tree number
echo "Test 3: Search by tree number"
RESULT=$($CLIENT --host "$HOST" search "D02.540.576.625.125" 2>&1)
if echo "$RESULT" | grep -q "Calcimycin"; then
    echo "  PASS: Found by tree number"
else
    echo "  FAIL: Tree number search failed"
    exit 1
fi

# Test4: Get descriptor details
echo "Test 4: Get descriptor details"
RESULT=$($CLIENT --host "$HOST" get "D000001" 2>&1)
if echo "$RESULT" | grep -q "Calcimycin"; then
    echo "  PASS: Got descriptor details"
else
    echo "  FAIL: Could not get details"
    exit 1
fi

echo
echo "=== All MCP search tests passed ==="
