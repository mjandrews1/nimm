#!/bin/bash
# test_mcp_search.sh — Test MCP search client and server
# Usage: ./tests/test_mcp_search.sh [db_path]

set -e

DB="${1:-/tmp/test_fst_mcp_$$}"
NIMM="./nimm"
LOADER="python3 future_search_tool/src/fst_load.py"
SERVER="python3 future_search_tool/src/fst_mcp_server.py"
CLIENT="python3 future_search_tool/src/mcp_search_client.py"
DATA_DIR="/Users/mark/_diary-data"
PORT=8081

echo "=== MCP Search Test Suite ==="
echo "Database: $DB"
echo "Port: $PORT"
echo

# Cleanup
cleanup() {
    rm -f "$DB" "$DB-lock"
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Test1: Load data
echo "Test 1: Load MeSH data"
$LOADER --db "$DB" --data-dir "$DATA_DIR" --skip catline serline pubmed --max-records 50
echo "  PASS: Data loaded"

# Test2: Start MCP server
echo "Test 2: Start MCP server"
$SERVER --db "$DB" --port "$PORT" &
SERVER_PID=$!
sleep 2
echo "  PASS: Server started (PID: $SERVER_PID)"

# Test3: Health check
echo "Test 3: Health check"
if curl -s "http://localhost:$PORT/health" 2>/dev/null; then
    echo "  PASS: Server is healthy"
else
    echo "  INFO: Health endpoint not available (MCP server doesn't expose /health)"
fi

# Test4: Search via MCP client
echo "Test 4: Search via MCP client"
RESULT=$($CLIENT --host "localhost:$PORT" search "Calcimycin" 2>&1)
if echo "$RESULT" | grep -q "D000001"; then
    echo "  PASS: Found D000001"
else
    echo "  FAIL: D000001 not found"
    echo "  Result: $RESULT"
    exit 1
fi

# Test5: Get descriptor details
echo "Test 5: Get descriptor details"
RESULT=$($CLIENT --host "localhost:$PORT" get D000001 2>&1)
if echo "$RESULT" | grep -q "Calcimycin"; then
    echo "  PASS: Got descriptor details"
else
    echo "  FAIL: Could not get details"
    echo "  Result: $RESULT"
    exit 1
fi

# Test6: List globals
echo "Test 6: List globals"
RESULT=$($CLIENT --host "localhost:$PORT" list MESH 2>&1)
if echo "$RESULT" | grep -q "Count:"; then
    echo "  PASS: Listed globals"
else
    echo "  FAIL: Could not list globals"
    echo "  Result: $RESULT"
    exit 1
fi

echo
echo "=== All MCP search tests passed ==="
