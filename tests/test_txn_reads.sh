#!/bin/bash
# test_txn_reads.sh — Verify #396: transaction overlay read visibility
# $DATA/$ORDER/$QUERY/listSubs must see uncommitted writes/kills (read-your-own-writes).
# Usage: ./tests/test_txn_reads.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #396: transaction overlay read visibility ==="

# $DATA sees uncommitted write (in-memory)
check "\$DATA in-memory" "1" "$($NIMM -x 'TSTART SET ^G(1)="x" WRITE $DATA(^G(1))' 2>&1)"

# $DATA sees uncommitted write (LMDB)
DB=/tmp/test_txn_reads_$$.lmdb
rm -f "$DB" "$DB-lock"
check "\$DATA LMDB" "1" "$($NIMM -d "$DB" -x 'TSTART SET ^G(1)="x" WRITE $DATA(^G(1))' 2>&1)"
rm -f "$DB" "$DB-lock"

# $ORDER sees uncommitted write
check "\$ORDER sees uncommitted write" "1" "$($NIMM -x 'KILL ^O TSTART SET ^O(1)="x" WRITE $ORDER(^O(""))' 2>&1)"

# $QUERY sees uncommitted write
check "\$QUERY sees uncommitted write" "^Q(1)" "$($NIMM -x 'KILL ^Q TSTART SET ^Q(1)="x" WRITE $QUERY(^Q(""))' 2>&1)"

# $DATA = 0 for a node killed inside the transaction
check "KILL hides \$DATA" "0" "$($NIMM -x 'SET ^G(1)="x" TSTART KILL ^G(1) WRITE $DATA(^G(1))' 2>&1)"

# TROLLBACK restores the pre-transaction value
check "TROLLBACK restores" "x" "$($NIMM -x 'SET ^G(1)="x" TSTART SET ^G(1)="y" TROLLBACK WRITE ^G(1)' 2>&1)"

# TCOMMIT persists; $DATA still 1 after commit
check "TCOMMIT persists" "1" "$($NIMM -x 'KILL ^G TSTART SET ^G(1)="x" TCOMMIT WRITE $DATA(^G(1))' 2>&1)"

# Nested transaction: innermost write wins for read
check "nested txn read" "b|1" "$($NIMM -x 'TSTART SET ^G(1)="a" TSTART SET ^G(1)="b" WRITE ^G(1),"|",$DATA(^G(1))' 2>&1)"

# $DATA tri-state: node with children but no own value -> 10
check "\$DATA node with children" "10" "$($NIMM -x 'KILL ^G TSTART SET ^G(1,2)="x" WRITE $DATA(^G(1))' 2>&1)"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
