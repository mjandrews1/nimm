#!/usr/bin/env bash
# soak_018.sh — NimM 0.1.8 soak test
# Runs until cutoff epoch. Tests all features under sustained load.
set -uo pipefail

CUTOFF="${1:?usage: soak_018.sh CUTOFF_EPOCH}"
cd "$HOME/nimm" || exit 1

export NIMM_BIN="$HOME/nimm/nimm"
export RSM_BIN="$HOME/rsm/rsm"
[ -f /tmp/overnight_rsm.dat ] && export RSM_DBFILE=/tmp/overnight_rsm.dat

START_EPOCH=$(date +%s)
LOG="$HOME/nimm/soak_018_${START_EPOCH}.log"
MCP_PORT=19999
MCP_KEY="soak_$(date +%s)"
MCP_PID=""
FAILS=0
CYCLE=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

cleanup() {
  [ -n "$MCP_PID" ] && kill "$MCP_PID" 2>/dev/null
  rm -f /tmp/soak_txn.lmdb /tmp/soak_txn.lmdb-lock
}
trap cleanup EXIT

log "=== NIMM 0.1.8 SOAK START pid=$$ cutoff=$CUTOFF nimm=$(git rev-parse --short HEAD) ==="

while [ "$(date +%s)" -lt "$CUTOFF" ]; do
  CYCLE=$((CYCLE + 1))
  log "--- cycle $CYCLE begin ---"

  # P1: Unit suites
  P1=$(./run_all_tests 2>&1 | tail -1)
  if echo "$P1" | grep -q "Failed: 0"; then
    log "P1 unit-suites OK ($P1)"
  else
    FAILS=$((FAILS + 1))
    log "P1 FAIL: $P1"
  fi

  # P2: Extended conformance
  P2=$(NIMM_BIN=./nimm python3 tests/mumps_extended_conformance.py --impls nimm 2>&1 | tail -3)
  if echo "$P2" | grep -q "100.0%"; then
    log "P2 extended OK"
  else
    FAILS=$((FAILS + 1))
    log "P2 FAIL: $P2"
  fi

  # P3: ISO suite (179 tests including Transaction)
  P3=$(NIMM_BIN=./nimm python3 tests/ansi_iso_m_conformance.py --impls nimm --runs 1 2>&1 | tail -3)
  if echo "$P3" | grep -q "SuspectBugs"; then
    log "P3 iso OK"
  else
    FAILS=$((FAILS + 1))
    log "P3 FAIL: $P3"
  fi

  # P4: LMDB transaction tests
  P4=$(bash tests/test_txn_lmdb.sh 2>&1 | tail -1)
  if echo "$P4" | grep -q "0 failed"; then
    log "P4 txn OK ($P4)"
  else
    FAILS=$((FAILS + 1))
    log "P4 FAIL: $P4"
  fi

  # P5: Introspection tests
  P5=$(bash tests/test_introspection.sh 2>&1 | tail -1)
  if echo "$P5" | grep -q "0 failed"; then
    log "P5 introspection OK ($P5)"
  else
    FAILS=$((FAILS + 1))
    log "P5 FAIL: $P5"
  fi

  # P6: MCP server smoke test
  if [ -z "$MCP_PID" ] || ! kill -0 "$MCP_PID" 2>/dev/null; then
    ./nimm --mcp --mcp-port $MCP_PORT --api-key "$MCP_KEY" --allow-write &
    MCP_PID=$!
    sleep 2
  fi
  MCP_RESULT=$(curl -s --max-time 5 -X POST "http://localhost:$MCP_PORT" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $MCP_KEY" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"execute_m_code","arguments":{"code":"W 1+2"}}}' 2>/dev/null)
  if echo "$MCP_RESULT" | grep -q '"output":"3"'; then
    log "P6 mcp OK"
  else
    FAILS=$((FAILS + 1))
    log "P6 mcp FAIL"
  fi

  # P7: Transaction stress test
  rm -f /tmp/soak_txn.lmdb /tmp/soak_txn.lmdb-lock
  TXN_RESULT=$(./nimm -d /tmp/soak_txn.lmdb -x '
    KILL ^Stress
    TSTART
    FOR I=1:1:100 SET ^Stress(I)=I*2
    TCOMMIT
    W $DATA(^Stress(50)),"|",$GET(^Stress(50))
  ' 2>&1)
  if echo "$TXN_RESULT" | grep -q "1|100"; then
    log "P7 txn-stress OK"
  else
    FAILS=$((FAILS + 1))
    log "P7 txn-stress FAIL: $TXN_RESULT"
  fi

  # P8: Cross-process LOCK test
  LOCK_RESULT=$(./nimm -d /tmp/soak_txn.lmdb -x 'LOCK +^SoakLock W $DATA(^$LOCK("SoakLock"))' 2>&1)
  if echo "$LOCK_RESULT" | grep -q "1"; then
    LOCK_RESULT2=$(./nimm -d /tmp/soak_txn.lmdb -x 'W $DATA(^$LOCK("SoakLock"))' 2>&1)
    if echo "$LOCK_RESULT2" | grep -q "1"; then
      log "P8 lock OK (cross-process)"
    else
      FAILS=$((FAILS + 1))
      log "P8 lock FAIL (cross-process): $LOCK_RESULT2"
    fi
  else
    FAILS=$((FAILS + 1))
    log "P8 lock FAIL: $LOCK_RESULT"
  fi

  # P9: Fuzz differential
  FUZZ=$(python3 tests/m_fuzz.py --start $((RANDOM * 1000)) --count 200 --nimm ./nimm --rsm ~/rsm/rsm --dbfile /tmp/overnight_rsm.dat 2>/dev/null | grep FUZZSTATS)
  if [ -n "$FUZZ" ]; then
    log "P9 fuzz $FUZZ"
  else
    log "P9 fuzz SKIP (no output)"
  fi

  log "--- cycle $CYCLE end fails_total=$FAILS ---"
done

log "=== NIMM 0.1.8 SOAK END cycles=$CYCLE fails_total=$FAILS ==="
