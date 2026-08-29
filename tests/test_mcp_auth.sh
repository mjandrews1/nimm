#!/bin/bash
# test_mcp_auth.sh — H5: MCP authentication + write-tool gating.
# Usage: ./tests/test_mcp_auth.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PORT="${MCP_TEST_PORT:-8099}"
PASS=0; FAIL=0

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

check_code() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected HTTP $expected, got $actual)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== H5: MCP auth + write gating ==="

SECRET="test-secret-$$"
"$NIMM" --mcp --mcp-port "$PORT" --api-key "$SECRET" &>/tmp/mcp_auth.log &
MCP_PID=$!
trap 'kill $MCP_PID 2>/dev/null || true; rm -f /tmp/mcp_auth.log' EXIT

# Wait for readiness
for _ in $(seq 1 20); do
  if curl -s -X POST "http://localhost:$PORT" -H 'Content-Type: application/json' \
      -H "X-API-Key: $SECRET" \
      --data-raw '{"jsonrpc":"2.0","id":0,"method":"tools/list","params":{}}' >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

# 1. Unauthenticated request → 401 Unauthorized
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$PORT" \
  -H 'Content-Type: application/json' \
  --data-raw '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
check_code "unauthenticated tools/list rejected" "401" "$CODE"

# 2. Wrong key → 401
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$PORT" \
  -H 'Content-Type: application/json' -H 'X-API-Key: wrong-key' \
  --data-raw '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
check_code "wrong API key rejected" "401" "$CODE"

# 3. Correct key → 200 + tools listed
OUT=$(curl -s -X POST "http://localhost:$PORT" -H 'Content-Type: application/json' \
  -H "X-API-Key: $SECRET" \
  --data-raw '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
check_contains "correct API key accepted" 'execute_m_code' "$OUT"

# 4. Write tools are absent when --allow-write is not given
if echo "$OUT" | grep -q '"name":"set_global"'; then
  echo "  FAIL: set_global present without --allow-write"
  FAIL=$((FAIL+1))
else
  echo "  PASS: write tools gated without --allow-write"
  PASS=$((PASS+1))
fi

kill $MCP_PID 2>/dev/null || true
wait $MCP_PID 2>/dev/null || true

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
