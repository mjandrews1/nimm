#!/bin/bash
# test_store_parity.sh — C1: memGlobals (no -d) vs LMDB (-d) produce identical output.
# Usage: ./tests/test_store_parity.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

run_parity() {
  local desc="$1" code="$2"
  local mem_out lmdb_out db
  mem_out=$("$NIMM" -x "$code" 2>&1)
  db="/tmp/store_parity_$$.lmdb"
  rm -f "$db" "$db-lock"
  lmdb_out=$("$NIMM" -d "$db" -x "$code" 2>&1)
  rm -f "$db" "$db-lock"
  if [ "$mem_out" = "$lmdb_out" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "    mem =[$mem_out]"
    echo "    lmdb=[$lmdb_out]"
    FAIL=$((FAIL+1))
  fi
}

echo "=== C1: store parity (mem vs LMDB) ==="

run_parity "SET/GET root + subscripted" 'KILL ^G SET ^G="root",^G("a")=1 WRITE ^G,"|",^G("a")'
run_parity "multi-subscript" 'KILL ^G SET ^G(1,2)="v" WRITE ^G(1,2)'
run_parity "variable subscript" 'KILL ^G SET I=2,^G(I)="w" WRITE ^G(I)'
run_parity "\$DATA tri-state" 'KILL ^G SET ^G(1)=1,^G(1,2)=2 WRITE $DATA(^G),"|",$DATA(^G(1)),"|",$DATA(^G(1,2)),"|",$DATA(^G(9))'
run_parity "\$ORDER forward" 'KILL ^G SET ^G(1)=1,^G(2)=2,^G(10)=3 WRITE $ORDER(^G("")),"|",$ORDER(^G(1)),"|",$ORDER(^G(10))'
run_parity "\$ORDER backward" 'KILL ^G SET ^G(1)=1,^G(2)=2,^G(10)=3 WRITE $ORDER(^G(10),-1),"|",$ORDER(^G(""),-1)'
run_parity "\$ORDER multi-level" 'KILL ^G SET ^G(1,10)=1,^G(1,20)=2,^G(2,5)=3 WRITE $ORDER(^G(1,10)),"|",$ORDER(^G(1,"")),"|",$ORDER(^G(""))'
run_parity "\$ORDER negative/fractional" 'KILL ^G SET ^G(-1)=1,^G(0.5)=2 WRITE $ORDER(^G(-1)),"|",$ORDER(^G(0.5))'
run_parity "\$QUERY" 'KILL ^G SET ^G(1)=1,^G(1,2)=2 WRITE $QUERY(^G("")),"|",$QUERY(^G(1))'
run_parity "KILL node + descendants" 'KILL ^G SET ^G(1)=1,^G(1,2)=2 KILL ^G(1) WRITE $DATA(^G(1)),"|",$DATA(^G(1,2)),"|",$DATA(^G)'
run_parity "ZKILL keeps descendants" 'KILL ^G SET ^G(1)=1,^G(1,2)=2 ZKILL ^G(1) WRITE $DATA(^G(1)),"|",$DATA(^G(1,2))'
run_parity "MERGE" 'KILL ^A,^B SET ^A(1)=1,^A(2)=2 MERGE ^B=^A WRITE ^B(1),"|",^B(2)'
run_parity "TCOMMIT persists" 'KILL ^G TSTART SET ^G(1)=1 TCOMMIT WRITE ^G(1)'
run_parity "TROLLBACK discards" 'KILL ^G SET ^G=99 TSTART SET ^G=1 TROLLBACK WRITE ^G'
run_parity "nested txn" 'KILL ^G TSTART SET ^G=1 TSTART SET ^G=2 TCOMMIT TCOMMIT WRITE ^G'
run_parity "txn kill of descendants" 'KILL ^G SET ^G(1,2)=1 TSTART KILL ^G WRITE $DATA(^G(1,2)) TROLLBACK'

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
