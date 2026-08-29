#!/bin/bash
# test_mcp_introspection.sh — Verify #389 Phase F: introspection MCP tools
# list_routines / list_variables / get_source / disassemble
# Usage: ./tests/test_mcp_introspection.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PORT="${MCP_TEST_PORT:-8099}"
PASS=0; FAIL=0

mcp_call() {
  # mcp_call '<json body>' — POST a raw JSON-RPC request to the MCP server
  curl -s -X POST "http://localhost:$PORT" -H 'Content-Type: application/json' --data-raw "$1"
}

check_contains() {
  local label="$1" needle="$2" actual="$3"
  if echo "$actual" | grep -q "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$needle' in output)"
    echo "    got: $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #389 Phase F: introspection MCP tools ==="

cat > /tmp/phasef.m <<'EOF'
MAIN ;
 WRITE "hi",!
 DO SUB
 QUIT
SUB ;
 WRITE "sub"
 QUIT
EOF

"$NIMM" -r /tmp/phasef.m --mcp --mcp-port "$PORT" &>/tmp/phasef_mcp.log &
MCP_PID=$!
trap 'kill $MCP_PID 2>/dev/null; rm -f /tmp/phasef.m /tmp/phasef_mcp.log' EXIT
sleep 2

# list_routines
OUT=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_routines","arguments":{}}}')
check_contains "list_routines" 'PHASEF' "$OUT"

# get_source
OUT=$(mcp_call '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_source","arguments":{"routine":"PHASEF"}}}')
check_contains "get_source returns source" 'source' "$OUT"

# disassemble
OUT=$(mcp_call '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"disassemble","arguments":{"routine":"PHASEF"}}}')
check_contains "disassemble" 'opPushConst' "$OUT"

# list_variables (after executing M code to set a variable)
mcp_call '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"execute_m_code","arguments":{"code":"SET X=42"}}}' >/dev/null
OUT=$(mcp_call '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_variables","arguments":{}}}')
check_contains "list_variables shows X" 'X' "$OUT"
check_contains "list_variables shows value" '42' "$OUT"

# get_source for a missing routine
OUT=$(mcp_call '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_source","arguments":{"routine":"NOPE"}}}')
check_contains "get_source missing routine" 'not found' "$OUT"

kill $MCP_PID 2>/dev/null || true
wait $MCP_PID 2>/dev/null || true

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
