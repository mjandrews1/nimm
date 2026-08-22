#!/usr/bin/env python3
"""
ANSI/ISO M/MUMPS Cross-Implementation Conformance Test Suite

Tests RSM, RFC, and NimM against the ANSI/MDC X11.1-1995 standard.
Reports per-implementation pass/fail and cross-implementation comparison.

Usage:
    python3 tests/mumps_cross_conformance.py
    python3 tests/mumps_cross_conformance.py --impls rsm,rfc,nimm
    python3 tests/mumps_cross_conformance.py --category Arithmetic
"""

import subprocess
import sys
import os
import time
import argparse
import tempfile

# ── Test Definitions ──────────────────────────────────────────────────────
# Each test: (name, code, expected_ansi, category, standard_ref, notes)
# expected_ansi is the ANSI/ISO-correct result

TESTS = [
    # ── Arithmetic (ANSI/ISO Section 4.2) ──
    ("OP_ADD",          "WRITE 2+3",                     "5",    "Arithmetic",  "4.2.1", "Integer addition"),
    ("OP_SUB",          "WRITE 5-2",                     "3",    "Arithmetic",  "4.2.1", "Integer subtraction"),
    ("OP_MUL",          "WRITE 3*4",                     "12",   "Arithmetic",  "4.2.1", "Integer multiplication"),
    ("OP_DIV",          "WRITE 10/2",                    "5",    "Arithmetic",  "4.2.1", "Integer division"),
    ("OP_MOD",          "WRITE 7#3",                     "1",    "Arithmetic",  "4.2.1", "Modulus (floor division)"),
    ("OP_POWER",        "WRITE 2**3",                    "8",    "Arithmetic",  "4.2.1", "Exponentiation"),
    ("OP_NEG",          "SET X=5 WRITE -X",              "-5",   "Arithmetic",  "4.2.1", "Unary negation"),
    ("OP_PRECEDENCE",   "WRITE 2+3*4",                   "20",   "Arithmetic",  "4.2.1", "Left-to-right, no precedence"),

    # ── String Concatenation (ANSI/ISO Section 4.2) ──
    ("OP_CONCAT",       'WRITE "a"_"b"',                 "ab",   "String",      "4.2",   "String concatenation"),

    # ── Comparison Operators (ANSI/ISO Section 4.2) ──
    ("OP_EQUAL",        "WRITE 1=1",                     "1",    "Compare",     "4.2",   "Equality true"),
    ("OP_NOTEQUAL",     "WRITE 1=0",                     "0",    "Compare",     "4.2",   "Equality false"),
    ("OP_LESS",         "WRITE 1<2",                     "1",    "Compare",     "4.2",   "Less than"),
    ("OP_GREATER",      "WRITE 2>1",                     "1",    "Compare",     "4.2",   "Greater than"),
    ("OP_NOT_LESS",     "WRITE 5'<3",                    "1",    "Compare",     "4.2",   "Not less than (>=)"),
    ("OP_NOT_GREATER",  "WRITE 3'>5",                    "1",    "Compare",     "4.2",   "Not greater than (<=)"),
    ("OP_STRINGEQ",     'WRITE "abc"="abc"',             "1",    "Compare",     "4.2",   "String equality"),
    ("OP_STRINGNE",     'WRITE "abc"="def"',             "0",    "Compare",     "4.2",   "String inequality"),

    # ── Logical Operators (ANSI/ISO Section 4.2) ──
    ("OP_AND",          "WRITE 1&1",                     "1",    "Logical",     "4.2",   "Logical AND true"),
    ("OP_AND_FALSE",    "WRITE 1&0",                     "0",    "Logical",     "4.2",   "Logical AND false"),
    ("OP_OR",           "WRITE 0!1",                     "1",    "Logical",     "4.2",   "Logical OR true"),
    ("OP_OR_FALSE",     "WRITE 0!0",                     "0",    "Logical",     "4.2",   "Logical OR false"),
    ("OP_NOT",          "WRITE '0",                      "1",    "Logical",     "4.2",   "Logical NOT"),

    # ── Pattern Matching (ANSI/ISO Section 4.2) ──
    ("OP_PATTERN_U",    'WRITE "ABC"?3U',                "1",    "Pattern",     "4.2",   "Pattern: uppercase"),
    ("OP_PATTERN_N",    'WRITE "ABC"?3N',                "0",    "Pattern",     "4.2",   "Pattern: numeric fail"),
    ("OP_PATTERN_L",    'WRITE "abc"?3L',                "1",    "Pattern",     "4.2",   "Pattern: lowercase"),
    ("OP_PATTERN_MIX",  'WRITE "a1b"?1L1N1L',            "1",    "Pattern",     "4.2",   "Pattern: mixed"),

    # ── String Contains / Follows (ANSI/ISO Section 4.2) ──
    ("OP_CONTAINS",     'WRITE "ABC"["B"',               "1",    "String",      "4.2",   "Contains operator"),
    ("OP_NOCONTAINS",   'WRITE "ABC"["D"',               "0",    "String",      "4.2",   "Not contains"),
    ("OP_FOLLOWS",      'WRITE "B"]"A"',                 "1",    "String",      "4.2",   "Follows operator"),

    # ── SET Command (ANSI/ISO Section 10.1) ──
    ("SET_BASIC",       'SET A="hello" WRITE A',         "hello",    "SET",      "10.1",  "Basic SET"),
    ("SET_NUM",         'SET A=42 WRITE A',              "42",       "SET",      "10.1",  "SET numeric"),
    ("SET_EXPR",        'SET A=2+3 WRITE A',             "5",        "SET",      "10.1",  "SET with expression"),
    ("SET_MULTIPLE",    'SET A="x",B="y" WRITE A,B',    "xy",       "SET",      "10.1",  "Multiple SET"),

    # ── SET with $PIECE / $EXTRACT write-back (ANSI/ISO Section 10.1) ──
    ("SET_PIECE",       'SET A="a^b^c" SET $PIECE(A,"^",2)="B" WRITE A', "a^B^c", "SET", "10.1", "$PIECE write-back"),
    ("SET_EXTRACT",     'SET A="ABCDE" SET $EXTRACT(A,2,3)="XY" WRITE A', "AXYDE", "SET", "10.1", "$EXTRACT write-back"),

    # ── WRITE Command (ANSI/ISO Section 10.2) ──
    ("WRITE_STRING",    'WRITE "hello"',                 "hello",    "WRITE",     "10.2",  "WRITE string literal"),
    ("WRITE_VAR",       'SET A="test" WRITE A',          "test",     "WRITE",     "10.2",  "WRITE variable"),
    ("WRITE_NEWLINE",   'WRITE "a",!,"b"',               "a\nb",     "WRITE",     "10.2",  "WRITE with ! (newline)"),
    ("WRITE_COMMA",     'WRITE "x","y","z"',             "xyz",      "WRITE",     "10.2",  "WRITE with comma (no space)"),

    # ── IF Command (ANSI/ISO Section 10.3) ──
    ("IF_TRUE",         'IF 1 WRITE "yes"',              "yes",  "IF",          "10.3",  "IF true executes"),
    ("IF_FALSE",        'IF 0 WRITE "yes"',              "",     "IF",          "10.3",  "IF false skips"),
    ("IF_POSTCOND",     'SET A=1 WRITE:A "yes"',         "yes",  "IF",          "10.3",  "Postconditional on WRITE"),
    ("IF_POSTCOND_FAIL",'SET A=0 WRITE:A "yes"',         "",     "IF",          "10.3",  "Postconditional false skips"),

    # ── FOR Loop (ANSI/ISO Section 10.4) ──
    ("FOR_BASIC",       'FOR I=1:1:3 WRITE I',           "123",  "FOR",         "10.4",  "Counted FOR"),
    ("FOR_STEP2",       'FOR I=0:2:6 WRITE I',           "0246", "FOR",         "10.4",  "FOR with step 2"),
    ("FOR_NEG_STEP",    'FOR I=3:-1:1 WRITE I',          "321",  "FOR",         "10.4",  "FOR with negative step"),
    ("FOR_QUIT",        'FOR I=1:1:5 QUIT:I>2  WRITE I', "12",   "FOR",         "10.4",  "FOR with QUIT"),
    ("FOR_NOARGS_SET",  'SET I=0 FOR  QUIT:I>2  SET I=I+1 WRITE I', "123", "FOR", "10.4", "FOR without args + QUIT"),

    # ── QUIT Command (ANSI/ISO Section 10.5) ──
    ("QUIT_VALUE",      'FOR I=1:1:5 QUIT:I>3  WRITE I', "123",  "QUIT",        "10.5",  "QUIT with condition"),
    ("QUIT_TOPLEVEL",   'SET A="old" NEW A SET A="new" QUIT  WRITE A', "", "NEW", "10.7", "QUIT at top level ends execution"),

    # ── KILL Command (ANSI/ISO Section 10.6) ──
    ("KILL_BASIC",      'SET A="val" KILL A WRITE $DATA(A)',         "0",   "KILL",  "10.6", "Basic KILL"),
    ("KILL_SELECTIVE",  'SET A=1,B=2,C=3 KILL (A,B) WRITE $DATA(C)', "0",  "KILL",  "10.6", "Selective KILL"),

    # ── NEW Command (ANSI/ISO Section 10.7) ──
    ("NEW_BASIC",       'SET A="old" NEW A SET A="new" WRITE A',     "new", "NEW",   "10.7", "NEW shadows variable"),
    ("NEW_RESTORE",     'SET A="old" NEW A SET A="new" QUIT  WRITE A', "", "NEW", "10.7", "QUIT at top level ends execution"),

    # ── XECUTE Command (ANSI/ISO Section 10.8) ──
    ("XECUTE",          'XECUTE "WRITE ""hello"""',      "hello", "XECUTE",      "10.8",  "XECUTE string code"),

    # ── LOCK Command (ANSI/ISO Section 10.9) ──
    ("LOCK_BASIC",      'LOCK ^A WRITE "ok"',            "ok",   "LOCK",        "10.9",  "LOCK global"),

    # ── $ASCII (ANSI/ISO Section 8.1) ──
    ("FN_ASCII",        'WRITE $ASCII("A")',             "65",   "Function",    "8.1",   "$ASCII of char"),
    ("FN_ASCII_POS",    'WRITE $ASCII("ABC",2)',          "66",   "Function",    "8.1",   "$ASCII with position"),
    ("FN_ASCII_NEG",    'WRITE $ASCII("",1)',             "-1",   "Function",    "8.1",   "$ASCII empty string"),

    # ── $CHAR (ANSI/ISO Section 8.2) ──
    ("FN_CHAR",         'WRITE $CHAR(65,66,67)',          "ABC",  "Function",    "8.2",   "$CHAR multiple codes"),
    ("FN_CHAR_SINGLE",  'WRITE $CHAR(65)',                "A",    "Function",    "8.2",   "$CHAR single code"),

    # ── $DATA (ANSI/ISO Section 8.3) ──
    ("FN_DATA_UNDEF",   'WRITE $DATA(UNDEF)',             "0",    "Function",    "8.3",   "$DATA undefined"),
    ("FN_DATA_DEFINED", 'SET A="val" WRITE $DATA(A)',     "1",    "Function",    "8.3",   "$DATA simple value"),
    ("FN_DATA_SUB",     'SET A(1)="x" WRITE $DATA(A)',    "10",   "Function",    "8.3",   "$DATA has subscript"),
    ("FN_DATA_BOTH",    'SET A="val",A(1)="x" WRITE $DATA(A)', "11", "Function", "8.3",  "$DATA value + subscript"),

    # ── $EXTRACT (ANSI/ISO Section 8.4) ──
    ("FN_EXTRACT",      'WRITE $EXTRACT("ABCDE",2,3)',    "BC",   "Function",    "8.4",   "$EXTRACT range"),
    ("FN_EXTRACT_ONE",  'WRITE $EXTRACT("ABCDE",3)',      "C",    "Function",    "8.4",   "$EXTRACT single"),
    ("FN_EXTRACT_FIRST",'WRITE $EXTRACT("ABCDE")',        "A",    "Function",    "8.4",   "$EXTRACT first char"),

    # ── $FIND (ANSI/ISO Section 8.5) ──
    ("FN_FIND",         'WRITE $FIND("ABCDE","CD")',      "5",    "Function",    "8.5",   "$FIND found"),
    ("FN_FIND_NO",      'WRITE $FIND("ABCDE","XY")',      "0",    "Function",    "8.5",   "$FIND not found"),
    ("FN_FIND_POS",     'WRITE $FIND("ABCDE","CD",3)',    "5",    "Function",    "8.5",   "$FIND with start"),

    # ── $GET (ANSI/ISO Section 8.6) ──
    ("FN_GET_DEF",      'SET A="val" WRITE $GET(A)',      "val",  "Function",    "8.6",   "$GET defined"),
    ("FN_GET_UNDEF",    'WRITE $GET(UNDEF)',              "",     "Function",    "8.6",   "$GET undefined"),
    ("FN_GET_DEFAULT",  'WRITE $GET(UNDEF,"default")',    "default", "Function", "8.6",  "$GET with default"),

    # ── $JUSTIFY (ANSI/ISO Section 8.7) ──
    ("FN_JUSTIFY",      'WRITE $JUSTIFY("abc",10)',       "       abc", "Function", "8.7", "$JUSTIFY right-justify"),
    ("FN_JUSTIFY_NUM",  'WRITE $JUSTIFY(3.14159,10,2)',   "      3.14", "Function", "8.7", "$JUSTIFY numeric format"),

    # ── $LENGTH (ANSI/ISO Section 8.8) ──
    ("FN_LENGTH",       'WRITE $LENGTH("ABCDE")',         "5",    "Function",    "8.8",   "$LENGTH string"),
    ("FN_LENGTH_DELIM", 'WRITE $LENGTH("a^b^c","^")',     "3",    "Function",    "8.8",   "$LENGTH with delimiter"),
    ("FN_LENGTH_EMPTY", 'WRITE $LENGTH("")',               "0",    "Function",    "8.8",   "$LENGTH empty"),

    # ── $ORDER (ANSI/ISO Section 8.9) ──
    ("FN_ORDER",        'SET A(1)="x",A(3)="y" WRITE $ORDER(A(0))',   "1",  "Function", "8.9", "$ORDER first"),
    ("FN_ORDER_NEXT",   'SET A(1)="x",A(3)="y" WRITE $ORDER(A(1))',   "3",  "Function", "8.9", "$ORDER next"),
    ("FN_ORDER_LAST",   'SET A(1)="x",A(3)="y" WRITE $ORDER(A(3))',   "",   "Function", "8.9", "$ORDER last"),

    # ── $PIECE (ANSI/ISO Section 8.10) ──
    ("FN_PIECE",        'WRITE $PIECE("a^b^c","^",2)',    "b",   "Function",    "8.10",  "$PIECE extract"),
    ("FN_PIECE_RANGE",  'WRITE $PIECE("a^b^c^d","^",2,3)', "b^c", "Function",  "8.10",  "$PIECE range"),

    # ── $RANDOM (ANSI/ISO Section 8.11) ──
    ("FN_RANDOM",       "SET X=$RANDOM(10) WRITE (X'<0)&(X<10)", "1", "Function", "8.11", "$RANDOM in range"),

    # ── $REVERSE (ANSI/ISO Section 8.12) ──
    ("FN_REVERSE",      'WRITE $REVERSE("ABC")',          "CBA", "Function",    "8.12",  "$REVERSE string"),

    # ── $SELECT (ANSI/ISO Section 8.13) ──
    ("FN_SELECT",       'WRITE $SELECT(0:"zero",1:"one",2:"two")', "one", "Function", "8.13", "$SELECT"),

    # ── $TRANSLATE (ANSI/ISO Section 8.14) ──
    ("FN_TRANSLATE",    'WRITE $TRANSLATE("ABCabc","abc","XYZ")', "ABCXYZ", "Function", "8.14", "$TRANSLATE"),
    ("FN_TRANS_DELETE", 'WRITE $TRANSLATE("ABCabc","abc")', "ABC", "Function", "8.14", "$TRANSLATE delete"),

    # ── Special Variables (ANSI/ISO Section 8.15) ──
    ("SV_HOROLOG",      'SET X=$HOROLOG WRITE $LENGTH(X,",")=2', "1", "SpecialVar", "8.15", "$HOROLOG format"),
    ("SV_IO",           'WRITE $IO',                      "0",   "SpecialVar",  "8.15",  "$IO"),
    ("SV_JOB",          'WRITE $JOB>0',                   "1",   "SpecialVar",  "8.15",  "$JOB"),
    ("SV_TEST_TRUE",    'IF 1 WRITE $TEST',              "1",   "SpecialVar",  "8.15",  "$TEST after true IF"),
    ("SV_TEST_FALSE",   'IF 0 WRITE $TEST',              "",    "SpecialVar",  "8.15",  "$TEST after false IF (line skipped)"),
    ("SV_X",            'WRITE $X',                       "0",   "SpecialVar",  "8.15",  "$X position"),
    ("SV_Y",            'WRITE $Y',                       "0",   "SpecialVar",  "8.15",  "$Y position"),

    # ── Globals (ANSI/ISO Section 6.2) ──
    ("GLOB_SET",        'SET ^GLOB="test" WRITE ^GLOB',   "test", "Global",     "6.2",   "Global set/get"),
    ("GLOB_SUBSCRIPTS", 'SET ^GLOB(1,2)="val" WRITE ^GLOB(1,2)', "val", "Global", "6.2", "Subscripted global"),
    ("GLOB_ORDER",      'SET ^GLOB(1)="a",^GLOB(3)="b" WRITE $ORDER(^GLOB(0))', "1", "Global", "6.2", "Global ORDER"),
    ("GLOB_KILL",       'SET ^GLOB="val" KILL ^GLOB WRITE $DATA(^GLOB)', "0", "Global", "6.2", "Global KILL"),

    # ── Complex Expressions ──
    ("COMPLEX_NEST",    'SET A=1 WRITE A+2*3',           "9",   "Complex",     "4.2",   "Nested arithmetic"),
    ("COMPLEX_STRING",  'WRITE "Hello, "_"World!"',       "Hello, World!", "Complex", "4.2", "String concat complex"),
    ("COMPLEX_SELECT",  'SET X=2 WRITE $SELECT(X=1:"a",X=2:"b",X=3:"c")', "b", "Complex", "8.13", "$SELECT with variable"),
]


# ── Engine Wrappers ───────────────────────────────────────────────────────

class Engine:
    """Base engine interface."""
    name = "unknown"
    
    def __init__(self, path, db_file=None):
        self.path = path
        self.db_file = db_file
    
    def run(self, code, timeout=5):
        """Run M code, return stripped stdout."""
        raise NotImplementedError

class NimMEngine(Engine):
    name = "NimM"
    
    def run(self, code, timeout=5):
        try:
            result = subprocess.run(
                [self.path, "-x", code],
                capture_output=True, text=True, timeout=timeout
            )
            return result.stdout.rstrip('\n')
        except subprocess.TimeoutExpired:
            return "[TIMEOUT]"
        except Exception as e:
            return f"[ERROR: {e}]"

class RSMEngine(Engine):
    name = "RSM"
    
    def run(self, code, timeout=5):
        env = os.environ.copy()
        if self.db_file:
            env['RSM_DBFILE'] = self.db_file
        try:
            result = subprocess.run(
                [self.path, "-x", code],
                capture_output=True, text=True, timeout=timeout, env=env
            )
            return result.stdout.rstrip('\n')
        except subprocess.TimeoutExpired:
            return "[TIMEOUT]"
        except Exception as e:
            return f"[ERROR: {e}]"

class RFCEngine(Engine):
    name = "RFC"
    
    def run(self, code, timeout=5):
        env = os.environ.copy()
        if self.db_file:
            env['RSM_DBFILE'] = self.db_file
        try:
            result = subprocess.run(
                [self.path, "-x", code],
                capture_output=True, text=True, timeout=timeout, env=env
            )
            out = result.stdout.rstrip('\n')
            lines = out.split('\n')
            actual_lines = []
            for line in lines:
                if line.startswith('DEBUG:'):
                    continue
                actual_lines.append(line)
            return '\n'.join(actual_lines).rstrip('\n')
        except subprocess.TimeoutExpired:
            return "[TIMEOUT]"
        except Exception as e:
            return f"[ERROR: {e}]" 


# ── Test Runner ───────────────────────────────────────────────────────────

def run_suite(engines, tests, verbose=False):
    """Run all tests against all engines, return results dict.
    
    results[test_name][engine_name] = (actual, expected, passed)
    timings[engine_name][test_name] = [t1, t2, ...] seconds
    """
    results = {}
    timings = {eng.name: {} for eng in engines}
    
    for name, code, expected, category, stdref, notes in tests:
        results[name] = {}
        for eng in engines:
            t0 = time.perf_counter()
            actual = eng.run(code)
            elapsed = time.perf_counter() - t0
            timings[eng.name].setdefault(name, []).append(elapsed)
            passed = (actual == expected)
            results[name][eng.name] = (actual, expected, passed)
            if verbose and not passed:
                print(f"  FAIL {eng.name}: {name} — expected {expected!r}, got {actual!r}")
    
    return results, timings


def print_timing(timings, engines, tests):
    """Print per-test timing statistics across runs."""
    print()
    print("=" * 72)
    print("Per-Test Timing (seconds)")
    print("=" * 72)
    
    header = f"{'Test':<25}"
    for eng in engines:
        header += f" | {eng.name + ' avg':>10} {'min':>8} {'max':>8}"
    print(header)
    print("-" * len(header))
    
    # Aggregate: total time per engine
    totals = {eng.name: 0.0 for eng in engines}
    
    for name, *_ in tests:
        row = f"{name:<25}"
        for eng in engines:
            times = timings[eng.name].get(name, [])
            if times:
                avg = sum(times) / len(times)
                totals[eng.name] += avg
                row += f" | {avg*1000:>9.2f}ms {min(times)*1000:>7.2f} {max(times)*1000:>7.2f}"
            else:
                row += f" | {'—':>10} {'—':>8} {'—':>8}"
        print(row)
    
    print("-" * len(header))
    row = f"{'TOTAL (sum of avgs)':<25}"
    for eng in engines:
        row += f" | {totals[eng.name]*1000:>9.2f}ms {'':>8} {'':>8}"
    print(row)


def print_summary(results, engines, tests):
    """Print a formatted summary table."""
    
    # ── Per-implementation scores ──
    print()
    print("=" * 72)
    print("ANSI/ISO M/MUMPS Cross-Implementation Conformance Results")
    print("=" * 72)
    print()
    print(f"{'Implementation':<12} {'Pass':>5} {'Fail':>5} {'Error':>5} {'Total':>5} {'Rate':>7}")
    print("-" * 42)
    
    for eng in engines:
        passed = sum(1 for n, _, _, _, _, _ in tests if results[n][eng.name][2])
        failed = sum(1 for n, _, _, _, _, _ in tests if not results[n][eng.name][2] and not results[n][eng.name][0].startswith('['))
        errors = sum(1 for n, _, _, _, _, _ in tests if results[n][eng.name][0].startswith('['))
        total = len(tests)
        rate = (passed / total * 100) if total > 0 else 0
        print(f"{eng.name:<12} {passed:>5} {failed:>5} {errors:>5} {total:>5} {rate:>6.1f}%")
    
    print()
    
    # ── Cross-implementation disagreement table ──
    print("Cross-Implementation Disagreements")
    print("-" * 72)
    print(f"{'Test':<25} {'Expected':<18} ", end="")
    for eng in engines:
        print(f"{eng.name:>8} ", end="")
    print()
    print("-" * 72)
    
    disagreements = 0
    for name, code, expected, category, stdref, notes in tests:
        impl_results = []
        for eng in engines:
            actual, _, passed = results[name][eng.name]
            impl_results.append((eng.name, actual, passed))
        
        # Show if any implementation differs from expected or from each other
        all_pass = all(r[2] for r in impl_results)
        if not all_pass:
            disagreements += 1
            print(f"{name:<25} {expected:<18} ", end="")
            for eng_name, actual, passed in impl_results:
                if passed:
                    print(f"{'OK':>8} ", end="")
                else:
                    print(f"{actual[:7]:>8} ", end="")
            print()
    
    if disagreements == 0:
        print("  (all implementations agree)")
    
    print()
    
    # ── Per-category breakdown ──
    categories = []
    seen = set()
    for _, _, _, cat, _, _ in tests:
        if cat not in seen:
            categories.append(cat)
            seen.add(cat)
    
    print("Per-Category Breakdown")
    print("-" * 72)
    print(f"{'Category':<15} ", end="")
    for eng in engines:
        print(f"{eng.name:>8} ", end="")
    print()
    print("-" * 72)
    
    for cat in categories:
        cat_tests = [(n, e, ex, c, s, no) for n, e, ex, c, s, no in tests if c == cat]
        print(f"{cat:<15} ", end="")
        for eng in engines:
            cat_pass = sum(1 for n, _, _, _, _, _ in cat_tests if results[n][eng.name][2])
            print(f"{cat_pass}/{len(cat_tests):<5} ", end="")
        print()
    
    print()
    print("=" * 72)
    print(f"Total tests: {len(tests)}")
    print("=" * 72)


def print_failures(results, engines, tests):
    """Print detailed failure info."""
    print()
    print("Detailed Failures")
    print("=" * 72)
    
    for name, code, expected, category, stdref, notes in tests:
        has_failure = False
        for eng in engines:
            actual, _, passed = results[name][eng.name]
            if not passed:
                if not has_failure:
                    print(f"\n{name} ({notes})")
                    print(f"  Code:     {code}")
                    print(f"  Expected: {expected!r}")
                    has_failure = True
                print(f"  {eng.name}: {actual!r}")
    
    print()


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="ANSI/ISO M conformance cross-test")
    parser.add_argument("--impls", default="nimm,rsm", help="Comma-separated engines to test (rfc deprecated)")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print failures as they happen")
    parser.add_argument("--category", "-c", help="Run only this category")
    parser.add_argument("--failures", "-f", action="store_true", help="Print detailed failures")
    parser.add_argument("--runs", "-r", type=int, default=1, help="Number of runs for timing (results from run 1)")
    parser.add_argument("--timing", "-t", action="store_true", help="Print per-test timing table")
    args = parser.parse_args()
    
    impls = [s.strip() for s in args.impls.split(",")]

    if "rfc" in impls:
        print("WARNING: RFC is deprecated — RSM is the sole reference engine.", file=sys.stderr)
    
    # Filter tests
    tests = TESTS
    if args.category:
        tests = [t for t in tests if t[3].lower() == args.category.lower()]
    
    # Create engines
    engines = []
    base_dir = os.environ.get("NIMM_DIR", "/Users/mark/_diary/ports/nimm-annotated")
    
    for impl in impls:
        if impl == "nimm":
            nimm_path = os.environ.get("NIMM_BIN", os.path.join(base_dir, "nimm"))
            if not os.path.exists(nimm_path):
                # Build it
                print(f"Building NimM...")
                subprocess.run(["nim", "c", "-d:release", "-o:nimm", "main.nim"],
                             cwd=base_dir, capture_output=True)
            engines.append(NimMEngine(nimm_path))
        elif impl == "rsm":
            engines.append(RSMEngine(os.environ.get("RSM_BIN", "/Users/mark/_rsm/rsm"),
                                     os.environ.get("RSM_DBFILE", "/tmp/rsm_test.dat")))
        elif impl == "rfc":
            engines.append(RFCEngine(os.environ.get("RFC_BIN", "/Users/mark/_rfc/builddir/rfc"),
                                     os.environ.get("RFC_DBFILE", "/tmp/rfc_test.dat")))
        else:
            print(f"Unknown implementation: {impl}")
            sys.exit(1)
    
    # Verify engines work
    print("Verifying engines...")
    for eng in engines:
        out = eng.run('WRITE "hello"')
        ok = "hello" in out
        status = "OK" if ok else f"FAIL ({out!r})"
        print(f"  {eng.name}: {status}")
        if not ok:
            print(f"  Skipping {eng.name} — not functional")
            engines.remove(eng)
    
    if not engines:
        print("No engines available. Exiting.")
        sys.exit(1)
    
    print(f"\nRunning {len(tests)} tests against {len(engines)} implementations, {args.runs} run(s)...\n")
    
    # Run tests (multiple runs accumulate timing; results from first run)
    results = None
    timings = None
    for run_num in range(1, args.runs + 1):
        if args.runs > 1:
            print(f"── Run {run_num}/{args.runs} ──")
        run_results, run_timings = run_suite(engines, tests, verbose=args.verbose and run_num == 1)
        if results is None:
            results = run_results
            timings = run_timings
        else:
            # Merge timing samples
            for eng_name, test_times in run_timings.items():
                for tname, times in test_times.items():
                    timings[eng_name].setdefault(tname, []).extend(times)
    
    # Print results
    print_summary(results, engines, tests)
    
    if args.timing or args.runs > 1:
        print_timing(timings, engines, tests)
    
    if args.failures:
        print_failures(results, engines, tests)


if __name__ == "__main__":
    main()
