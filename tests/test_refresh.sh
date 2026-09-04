#!/usr/bin/env bash
# test_refresh.sh — the #470 refresh scheduler (deploy/refresh.sh).
# Exercises: manifest parsing, cadence thresholds, and the due/not-due flip via
# the ^FST("meta",source,"updated") marker. Uses a scratch DB; never runs the
# real loaders (only --list).
set -euo pipefail
NIMM="${1:-./bin/nimm}"
DB="$(mktemp -d)/refresh_test.lmdb"
PASS=0; FAIL=0

t() { # label actual expected
  if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1));
  else echo "  FAIL: $1"; echo "    got=[$2] expected=[$3]"; FAIL=$((FAIL+1)); fi
}

echo "=== refresh scheduler (#470) ==="

# A fresh marker for ^MESH makes it not-DUE, everything else (unset) is DUE.
NOW=$(date +%s)
"$NIMM" -d "$DB" -x "S ^FST(\"meta\",\"^MESH\",\"updated\")=\"$NOW\" W 1" >/dev/null 2>&1

LIST=$(NIMM_DIR="$(pwd)" DB="$DB" ./deploy/refresh.sh --list 2>&1)
t "^MESH annual (fresh, not due)" "$(echo "$LIST" | grep -F '^MESH' | grep -c 'DUE')" "0"
t "^PUBMED weekly (unset, due)" "$(echo "$LIST" | grep -F '^PUBMED' | grep -c 'DUE')" "1"
t "faers quarterly (unset, due)" "$(echo "$LIST" | grep -E '^faers' | grep -c 'DUE')" "1"
t "13 sources listed" "$(echo "$LIST" | grep -cE 'age=')" "13"

# An old marker for faers (366 days ago) keeps it DUE at quarterly.
OLD=$((NOW - 365*86400))
"$NIMM" -d "$DB" -x "S ^FST(\"meta\",\"faers\",\"updated\")=\"$OLD\" W 1" >/dev/null 2>&1
LIST=$(NIMM_DIR="$(pwd)" DB="$DB" ./deploy/refresh.sh --list 2>&1)
t "faers quarterly (366d old, due)" "$(echo "$LIST" | grep -E '^faers' | grep -c 'DUE')" "1"

rm -rf "$(dirname "$DB")"
echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
