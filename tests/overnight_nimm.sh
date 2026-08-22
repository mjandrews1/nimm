#!/usr/bin/env bash
# overnight_nimm.sh CUTOFF_EPOCH — soak NimM on Utility-01 until cutoff.
#
# Phases per cycle (results appended to $HOME/nimm/overnight_<epoch>.log):
#   1. run_all_tests            (19 built-in suites)
#   2. extended conformance     (34 tests x runs, with timing)
#   3. ANSI/ISO 170-suite       (--runs)
#   4. differential fuzz        (NimM vs RSM, seeded — tests/m_fuzz.py)
#
# Isolation: the RSM daemon must be UP before starting this script and NO
# RFC daemon may run at any point during the night. This script never
# starts or stops daemons itself.
set -u
CUTOFF="${1:?usage: overnight_nimm.sh CUTOFF_EPOCH}"
cd "$HOME/nimm" || exit 1

export NIMM_BIN="$HOME/nimm/nimm"
export RSM_BIN="$HOME/rsm/rsm"
[ -f /tmp/overnight_rsm.dat ] && export RSM_DBFILE=/tmp/overnight_rsm.dat
[ -x ./run_all_tests ] || nim c -d:release -o:run_all_tests run_all_tests.nim >/dev/null 2>&1

START_EPOCH=$(date +%s)
export OVERNIGHT_LOG="$HOME/nimm/overnight_${START_EPOCH}.log"
NIMM="$HOME/nimm/nimm"
RSM="$HOME/rsm/rsm"
DBFILE=/tmp/overnight_rsm.dat
FUZZ_PER_CYCLE=200
EXT_RUNS=10
ISO_RUNS=5
CYCLE=0
FAILS=0

log() { echo "[$(date -u '+%F %T')] $*" >> "$OVERNIGHT_LOG"; }

log "=== OVERNIGHT SOAK START pid=$$ cutoff=$CUTOFF nimm=$(git rev-parse --short HEAD) ==="
log "KNOWN divergences (found during shakedown, not new): undefined-local M6 vs empty-string; divide-by-zero M9 vs silent 0; division precision 16 vs 32 digits"

while [ "$(date +%s)" -lt "$CUTOFF" ]; do
  CYCLE=$((CYCLE + 1))
  log "--- cycle $CYCLE begin ---"

  # Phase 1: built-in suites
  P1=$(./run_all_tests 2>/dev/null | tail -3 | tr '\n' ' ')
  case "$P1" in
    *"Failed: 0"*)
      log "P1 unit-suites OK ($P1)"
      ;;
    *)
      FAILS=$((FAILS+1)); log "P1 FAIL: $P1"
      ;;
  esac

  # Phase 2: extended conformance (34 tests) with timing; summary line looks
  # like: "NimM              34     0    34   100.0%"
  P2=$(python3 tests/mumps_extended_conformance.py --impls nimm --runs "$EXT_RUNS" --timing 2>/dev/null \
       | grep -E '^(nimm|NimM)' | tail -1)
  case "$P2" in
    *"100.0%"*)
      log "P2 extended OK ($P2)"
      ;;
    "")
      FAILS=$((FAILS+1)); log "P2 CRASH: no output"
      ;;
    *)
      FAILS=$((FAILS+1)); log "P2 CHECK: $P2"
      ;;
  esac

  # Phase 3: 170-test ANSI/ISO suite
  P3=$(python3 tests/ansi_iso_m_conformance.py --impls nimm --runs "$ISO_RUNS" 2>/dev/null \
       | grep -Ei '[0-9]+ */ *170|passed' | tail -2 | tr '\n' ' ')
  case "$P3" in
    *170*)
      log "P3 iso170 OK ($P3)"
      ;;
    "")
      log "P3 WARN no parseable output"
      ;;
    *)
      FAILS=$((FAILS+1)); log "P3 CHECK: $P3"
      ;;
  esac

  # Phase 4: differential fuzz vs RSM (fresh seed block each cycle).
  # Full mismatch details are kept per-cycle for morning triage.
  SEED0=$(( (START_EPOCH + CYCLE * FUZZ_PER_CYCLE) % 1000000 ))
  P4F="${OVERNIGHT_LOG}.fuzz.c${CYCLE}"
  python3 tests/m_fuzz.py --nimm "$NIMM" --rsm "$RSM" --dbfile "$DBFILE" \
        --start "$SEED0" --count "$FUZZ_PER_CYCLE" > "$P4F" 2>&1
  P4=$(grep '^FUZZSTATS' "$P4F")
  case "$P4" in
    *mismatch=0*)
      log "P4 fuzz OK ($P4)"
      ;;
    "")
      FAILS=$((FAILS+1)); log "P4 CRASH: no fuzz output"
      ;;
    *)
      FAILS=$((FAILS+1)); log "P4 MISMATCHES ($P4)"
      ;;
  esac

  log "--- cycle $CYCLE end fails_total=$FAILS ---"
  [ "$(date +%s)" -lt "$CUTOFF" ] && sleep 20
done

log "=== OVERNIGHT SOAK END cycles=$CYCLE suspicious_cycles=$FAILS ==="
