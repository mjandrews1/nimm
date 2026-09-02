#!/usr/bin/env bash
# test_serial_link.sh — CATLINE→SERLINE "serial" link via ISSN join (#465).
set -euo pipefail
NIMM="${1:-./bin/nimm}"
LINKER="${2:-./bin/build_serial_link}"
DB=/tmp/serial_link_test_$$.lmdb
PASS=0; FAIL=0
cleanup() { rm -f "$DB" "$DB-lock"; }
trap cleanup EXIT

"$NIMM" -d "$DB" -x 'SET ^SERLINE("S1","issn")="0567-3771",^SERLINE("S2","issn")="1234-5678",^CATLINE("C1","issn")="0567-3771",^CATLINE("C2","issn")="9999-9999",^CATLINE("C3","title")="no issn"' >/dev/null 2>&1

OUT=$("$LINKER" "$DB" 2>&1)
if echo "$OUT" | grep -q "linked=1"; then
  echo "  PASS: reports linked=1"; PASS=$((PASS+1))
else echo "  FAIL: $OUT"; FAIL=$((FAIL+1)); fi

R=$("$NIMM" -d "$DB" -x 'W $G(^LINK("CATLINE","C1","SERLINE","S1")),"|",$D(^LINK("CATLINE","C2","SERLINE","S2"))' 2>&1)
if [ "$R" = "serial|0" ]; then
  echo "  PASS: matching ISSN linked, non-matching not"; PASS=$((PASS+1))
else echo "  FAIL: got '$R'"; FAIL=$((FAIL+1)); fi

echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
