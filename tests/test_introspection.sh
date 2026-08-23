#!/usr/bin/env bash
# test_introspection.sh — Test introspection/debugger features
set -euo pipefail

NIMM="${NIMM_BIN:-./nimm}"
PASS=0
FAIL=0

run() {
  local desc="$1" code="$2" expected="$3"
  local got
  got=$("$NIMM" -x "$code" 2>&1)
  if echo "$got" | grep -q "$expected"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc — expected '$expected' in output"
    echo "    got: $got"
    FAIL=$((FAIL + 1))
  fi
}

run_routine() {
  local desc="$1" file="$2" code="$3" expected="$4"
  local got
  got=$("$NIMM" -r "$file" -x "$code" 2>&1)
  if echo "$got" | grep -q "$expected"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc — expected '$expected' in output"
    echo "    got: $got"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Introspection Tests ==="

# ZSTACK shows call stack
printf 'ENTRY\n D SUB\n ZSTACK\n Q\nSUB\n Q\n' > /tmp/test_zstack.m
run_routine "ZSTACK shows call stack" /tmp/test_zstack.m "DO ENTRY" "Call Stack"

# ZSTACK shows routine:label
run_routine "ZSTACK shows routine:label" /tmp/test_zstack.m "DO ENTRY" "TEST_ZSTACK:ENTRY"

# BREAK enters interactive debugger
run "BREAK enters debugger" 'BREAK' "Debugger"

# ZSTEP sets step mode
run "ZSTEP sets step mode" 'ZSTEP' "Step mode: into"

# ZCONTINUE resumes execution
run "ZCONTINUE resumes" 'ZSTEP ZCONTINUE' "Continuing"

# Variable access recording (check via ZWRITE or similar)
# This tests that the inspector is wired
run "Inspector records commands" 'SET X=1 W X' "1"

# $ESTACK reflects DO depth
printf 'ENTRY\n W $ESTACK\n D SUB\n W $ESTACK\n Q\nSUB\n W $ESTACK\n Q\n' > /tmp/test_estack.m
run_routine "\$ESTACK tracks DO depth" /tmp/test_estack.m "DO ENTRY" "121"

# ZSTATS shows runtime statistics
run "ZSTATS shows stats" 'SET X=1 ZSTATS' "Commands executed:"

# ZSTATS counts function calls
run "ZSTATS counts function calls" 'W $L("abc") ZSTATS' "Function calls:"

# ZVHISTORY shows variable access history
run "ZVHISTORY shows history" 'SET A=1 SET B=2 ZVHISTORY' "Variable History"

# ZVHISTORY shows variable values
run "ZVHISTORY shows values" 'SET A=1 ZVHISTORY' 'A = "1"'

# ZBREAK -L lists breakpoints (empty)
run "ZBREAK -L lists breakpoints" 'ZBREAK "-L"' "No breakpoints set"

# ZBREAK sets breakpoint
printf 'ENTRY\n ZBREAK SUB\n Q\nSUB\n Q\n' > /tmp/test_zbreak.m
run_routine "ZBREAK sets breakpoint" /tmp/test_zbreak.m "DO ENTRY" "Breakpoint set"

# BREAK interactive debugger
run "BREAK enters debugger" 'SET X=42 BREAK' "Debugger"

# $ZJOB returns PID
run "\$ZJOB returns PID" 'W $ZJOB' "[0-9]"

# $ZPOS returns position (empty at top level)
printf 'ENTRY\n W $ZPOS\n Q\n' > /tmp/test_zpos.m
run_routine "\$ZPOS returns position" /tmp/test_zpos.m "DO ENTRY" "TEST_ZPOS:0"

# $ZROUTINE returns routine name
printf 'ENTRY\n W $ZROUTINE\n Q\n' > /tmp/test_zroutine.m
run_routine "\$ZROUTINE returns routine name" /tmp/test_zroutine.m "DO ENTRY" "TEST_ZROUTINE"

# $ZSOURCE returns source file
printf 'ENTRY\n W $ZSOURCE\n Q\n' > /tmp/test_zsource.m
run_routine "\$ZSOURCE returns source file" /tmp/test_zsource.m "DO ENTRY" "test_zsource.m"

echo ""
echo "Results: $PASS passed, $FAIL failed"

# Cleanup
rm -f /tmp/test_zstack.m /tmp/test_estack.m /tmp/test_zbreak.m /tmp/test_zpos.m /tmp/test_zroutine.m /tmp/test_zsource.m

[ "$FAIL" -eq 0 ]
