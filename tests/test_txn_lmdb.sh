#!/usr/bin/env bash
# test_txn_lmdb.sh — Test M transaction processing with LMDB backend
# Verifies TSTART/TCOMMIT/TROLLBACK persist correctly to LMDB.
set -euo pipefail

NIMM="${1:-./bin/nimm}"
DB="/tmp/test_txn_lmdb_$$"
PASS=0
FAIL=0

cleanup() { rm -f "$DB" "$DB-lock"; }
trap cleanup EXIT

run() {
  local desc="$1" code="$2" expected="$3"
  local got
  got=$("$NIMM" -d "$DB" -x "$code" 2>&1)
  if [ "$got" = "$expected" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc — expected '$expected', got '$got'"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== LMDB Transaction Tests ==="

# Basic commit persists
run "TCOMMIT persists" \
  'KILL ^TxnA TSTART SET ^TxnA(1)="x" TCOMMIT WRITE $DATA(^TxnA(1))' \
  "1"

# Rollback discards
run "TROLLBACK discards" \
  'KILL ^TxnB TSTART SET ^TxnB(1)="x" TROLLBACK WRITE $DATA(^TxnB(1))' \
  "0"

# Commit persists across processes (LMDB durability)
run "TCOMMIT durable across processes" \
  'KILL ^TxnC TSTART SET ^TxnC="persist" TCOMMIT' \
  ""
run "TCOMMIT readable in new process" \
  'WRITE ^TxnC' \
  "persist"

# Rollback durable across processes
run "TROLLBACK durable across processes" \
  'SET ^TxnD=99 TSTART SET ^TxnD=1 TROLLBACK' \
  ""
run "TROLLBACK readable in new process" \
  'WRITE ^TxnD' \
  "99"

# Nested commit
run "Nested TCOMMIT" \
  'KILL ^TxnE TSTART SET ^TxnE=1 TSTART SET ^TxnE=2 TCOMMIT TCOMMIT WRITE ^TxnE' \
  "2"

# Nested rollback preserves outer
run "Nested TROLLBACK preserves outer" \
  'KILL ^TxnF TSTART SET ^TxnF=1 TSTART SET ^TxnF=2 TROLLBACK WRITE ^TxnF' \
  "1"

# Kill in transaction
run "KILL in transaction persists on commit" \
  'SET ^TxnG=1 TSTART KILL ^TxnG TCOMMIT WRITE $DATA(^TxnG)' \
  "0"

run "KILL in transaction restored on rollback" \
  'SET ^TxnH=1 TSTART KILL ^TxnH TROLLBACK WRITE ^TxnH' \
  "1"

# $TLEVEL
run '$TLEVEL tracks nesting' \
  'WRITE $TLEVEL,"." TSTART WRITE $TLEVEL,"." TCOMMIT WRITE $TLEVEL' \
  "0.1.0"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
