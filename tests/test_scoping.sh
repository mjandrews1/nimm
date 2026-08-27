#!/bin/bash
# test_scoping.sh — Scoping and KILL behavior tests for nimm
# Tests: KILL descendants (LMDB vs in-memory), NEW+DO scoping,
#        cross-routine DO WRITE propagation
# Usage: ./tests/test_scoping.sh

set -e

NIMM="${1:-./bin/nimm}"
DB="/tmp/test_scoping_$$.lmdb"
DB2="/tmp/test_scoping2_$$.lmdb"

cleanup() { rm -f "$DB" "$DB-lock" "$DB2" "$DB2-lock"; }
trap cleanup EXIT

PASS=0 FAIL=0

run_test() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $name"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $name"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Scoping & KILL Behavior Tests ==="
echo

# ============================================================
# SECTION 1: KILL descendants (in-memory)
# ============================================================
echo "--- KILL descendants (in-memory) ---"

R=$($NIMM -x 'SET ^X(1)="a" SET ^X(2)="b" SET ^X(3)="c" KILL ^X WRITE $D(^X(1)),"|",$D(^X(2)),"|",$D(^X(3))')
run_test "KILL ^X removes ^X(1),^X(2),^X(3)" "0|0|0" "$R"

R=$($NIMM -x 'SET ^X(1,2)="deep" KILL ^X(1) WRITE $D(^X(1,2))')
run_test "KILL ^X(1) removes ^X(1,2)" "0" "$R"

R=$($NIMM -x 'SET ^X(1)="a" SET ^X(1,2)="b" SET ^X(1,2,3)="c" KILL ^X(1) WRITE $D(^X(1)),"|",$D(^X(1,2)),"|",$D(^X(1,2,3))')
run_test "KILL ^X(1) removes entire subtree" "0|0|0" "$R"

R=$($NIMM -x 'SET ^X(1)="a" SET ^X(2)="b" KILL ^X(1) WRITE ^X(2)')
run_test "KILL ^X(1) preserves ^X(2)" "b" "$R"

# ============================================================
# SECTION 2: KILL descendants (LMDB)
# ============================================================
echo
echo "--- KILL descendants (LMDB) ---"

rm -f "$DB" "$DB-lock"
$NIMM -d "$DB" -x 'SET ^X(1)="a" SET ^X(2)="b" SET ^X(3)="c"'
$NIMM -d "$DB" -x 'KILL ^X'
R=$($NIMM -d "$DB" -x 'WRITE $D(^X(1)),"|",$D(^X(2)),"|",$D(^X(3))')
run_test "LMDB: KILL ^X removes children" "0|0|0" "$R"

rm -f "$DB" "$DB-lock"
$NIMM -d "$DB" -x 'SET ^X(1,2)="deep"'
$NIMM -d "$DB" -x 'KILL ^X(1)'
R=$($NIMM -d "$DB" -x 'WRITE $D(^X(1,2))')
run_test "LMDB: KILL ^X(1) removes ^X(1,2)" "0" "$R"

rm -f "$DB" "$DB-lock"
$NIMM -d "$DB" -x 'SET ^X(1)="a" SET ^X(1,2)="b" SET ^X(1,2,3)="c"'
$NIMM -d "$DB" -x 'KILL ^X(1)'
R=$($NIMM -d "$DB" -x 'WRITE $D(^X(1)),"|",$D(^X(1,2)),"|",$D(^X(1,2,3))')
run_test "LMDB: KILL ^X(1) removes entire subtree" "0|0|0" "$R"

rm -f "$DB" "$DB-lock"
$NIMM -d "$DB" -x 'SET ^X(1)="a" SET ^X(2)="b"'
$NIMM -d "$DB" -x 'KILL ^X(1)'
R=$($NIMM -d "$DB" -x 'WRITE ^X(2)')
run_test "LMDB: KILL ^X(1) preserves ^X(2)" "b" "$R"

# ============================================================
# SECTION 3: NEW scoping
# ============================================================
echo
echo "--- NEW scoping (DO + QUIT) ---"

# Test: NEW inside DO, QUIT should restore
R=$($NIMM -x 'SET A="outer" DO SUB WRITE A')
run_test "DO SUB preserves outer A (no NEW)" "outer" "$R"

cat > /tmp/scoping_sub1.m << 'ENDM'
SUB ;
 SET A="inner"
 WRITE A,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub1.m -x 'SET A="outer" DO SUB WRITE A')
run_test "DO SUB overwrites A (no NEW in sub)" "inner
inner" "$R"

cat > /tmp/scoping_sub2.m << 'ENDM'
SUB ;
 NEW A
 SET A="inner"
 WRITE A,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub2.m -x 'SET A="outer" DO SUB WRITE A')
run_test "NEW A in SUB restores outer A" "inner
outer" "$R"

cat > /tmp/scoping_sub3.m << 'ENDM'
SUB ;
 NEW A,B
 SET A="inner_a"
 SET B="inner_b"
 WRITE A,"|",B,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub3.m -x 'SET A="outer_a" SET B="outer_b" DO SUB WRITE A,"|",B')
run_test "NEW A,B in SUB restores both" "inner_a|inner_b
outer_a|outer_b" "$R"

# Test: NEW inside nested DO
cat > /tmp/scoping_sub4.m << 'ENDM'
OUTER ;
 NEW A
 SET A="outer_new"
 DO INNER
 WRITE "outer:",A,!
 QUIT
 ;
INNER ;
 SET A="inner"
 WRITE "inner:",A,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub4.m -x 'SET A="global" DO OUTER WRITE "global:",A')
run_test "NEW in OUTER, SET in INNER (shares NEW'd var, restored on QUIT)" "inner:inner
outer:inner
global:global" "$R"

# ============================================================
# SECTION 4: NEW scoping with DO + QUIT interaction
# ============================================================
echo
echo "--- NEW + DO frame interaction ---"

# Test: NEW in DO'd routine, QUIT should not unwind caller's scopes
cat > /tmp/scoping_sub5.m << 'ENDM'
CALC ;
 NEW TYPE,VAL
 SET TYPE="test"
 SET VAL=42
 WRITE TYPE,"|",VAL,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub5.m -x 'SET TYPE="global" SET VAL=99 DO CALC WRITE TYPE,"|",VAL')
run_test "NEW in DO'd routine restores caller vars" "test|42
global|99" "$R"

# Test: Multiple NEW levels (labels L1/L2/L3 avoid the single-letter "B"=BREAK collision)
cat > /tmp/scoping_sub6.m << 'ENDM'
L1 ;
 NEW X
 SET X="a"
 DO L2
 WRITE "A:",X,!
 QUIT
L2 ;
 NEW X
 SET X="b"
 DO L3
 WRITE "B:",X,!
 QUIT
L3 ;
 SET X="c"
 WRITE "C:",X,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub6.m -x 'SET X="top" DO L1 WRITE "TOP:",X')
run_test "Nested NEW+DO preserves each scope" "C:c
B:c
A:a
TOP:top" "$R"

# ============================================================
# SECTION 5: Cross-routine DO WRITE propagation
# ============================================================
echo
echo "--- Cross-routine DO WRITE propagation ---"

cat > /tmp/scoping_rtn1.m << 'ENDM'
HELLO ;
 WRITE "hello from routine1",!
 QUIT
ENDM
cat > /tmp/scoping_rtn2.m << 'ENDM'
WORLD ;
 WRITE "world from routine2",!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_rtn1.m -r /tmp/scoping_rtn2.m -e 'DO HELLO^SCOPING_RTN1 DO WORLD^SCOPING_RTN2')
run_test "Cross-routine DO WRITEs both" "hello from routine1
world from routine2" "$R"

# Test: Cross-routine DO with return value via WRITE
cat > /tmp/scoping_rtn3.m << 'ENDM'
SCORE ;
 NEW A
 SET A=42
 WRITE A
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_rtn3.m -e 'DO SCORE^SCOPING_RTN3')
run_test "Cross-routine DO WRITE propagated" "42" "$R"

# Test: Cross-routine DO from wrapper routine
cat > /tmp/scoping_wrapper.m << 'ENDM'
WRAPPER ;
 DO SCORE^SCOPING_RTN3
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_rtn3.m -r /tmp/scoping_wrapper.m -e 'DO WRAPPER^SCOPING_WRAPPER')
run_test "Wrapper calling cross-routine DO WRITE" "42" "$R"

# ============================================================
# SECTION 6: QUIT inside DO block (not subroutine)
# ============================================================
echo
echo "--- QUIT inside FOR-DO block ---"

# Test: QUIT:cond inside FOR exits the FOR loop (not the whole program)
# Uses '< (not-less-than = >=) — '>=' is not valid M and mis-tokenizes.
cat > /tmp/scoping_forquit.m << 'ENDM'
FORQUIT ;
 SET X=0
 FOR I=1:1:5 SET X=X+1 QUIT:X'<3
 WRITE X
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_forquit.m -e 'DO FORQUIT^SCOPING_FORQUIT')
run_test "QUIT:cond exits FOR loop" "3" "$R"

# Test: QUIT in DO block exits DO, not FOR
cat > /tmp/scoping_sub7.m << 'ENDM'
CHECK ;
 SET X=0
 FOR I=1:1:5 D
 . SET X=X+1
 . IF X=3 QUIT
 WRITE X,!
 QUIT
ENDM
R=$($NIMM -r /tmp/scoping_sub7.m -e 'DO CHECK^SCOPING_SUB7')
run_test "QUIT in DO block exits DO, not FOR" "3" "$R"

# ============================================================
# Summary
# ============================================================
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
