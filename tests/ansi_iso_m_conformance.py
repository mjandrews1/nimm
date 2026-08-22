#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ANSI/ISO M Conformance Test Suite
=================================
Strict compliance tests for the M language (MUMPS) per:

  - ANSI X11.1-1994 (MUMPS Language Standard)
  - ISO/IEC 11756:1999 (Information technology — Programming languages — M)

Every expected value is derived from the standard text itself, NOT from any
implementation's observed behavior. Where an implementation disagrees with an
expectation here, that is a conformance finding against that implementation.

Scope: REQUIRED language features. Optional capabilities are excluded:
  - Transaction processing (TSTART/TCOMMIT/TROLLBACK) — optional per §11,
    tracked separately in GitHub issues #256-#263.
  - Error-mode output formatting (implementation-specific text).
  - Structured system variables (^$...) — optional.
  - Z-commands, VIEW, external calls — implementation-specific by design.

The SUSPECTBUGS category carries explicit regression tests for suspected
implementation bugs discovered during cross-implementation investigation
(BUG01..BUG12); each expectation is justified by the cited standard section.

Global-state note: RSM/RFC databases persist globals across invocations,
so every global-touching test KILLs its globals first.

Environment ports: paths configurable via env vars:
  NIMM_DIR, NIMM_BIN, RSM_BIN, RSM_DBFILE, RFC_BIN, RFC_DBFILE

Usage:
  python3 ansi_iso_m_conformance.py --impls nimm,rsm,rfc [options]
Options:
  --runs N      Repeat runs for timing stability (default 1)
  --timing      Print per-test timing table
  --failures    Print detailed failure listing
  --category C  Run only one category
"""

import argparse
import os
import subprocess
import sys
import time

# ── Engine wrappers ─────────────────────────────────────────────────────────


class Engine:
    """Base class: run(code) -> stdout string."""

    def __init__(self, name, path):
        self.name = name
        self.path = path


class RSMEngine(Engine):
    def run(self, code, timeout=5):
        try:
            env = dict(os.environ)
            env["RSM_DBFILE"] = os.environ.get("RSM_DBFILE", "/tmp/rsm_test.dat")
            r = subprocess.run(
                [self.path, "-x", code],
                capture_output=True, text=True, timeout=timeout, env=env)
            return r.stdout.rstrip("\n")
        except subprocess.TimeoutExpired:
            return "[TIMEOUT]"
        except Exception as e:
            return f"[ERROR: {e}]"


class RFCEngine(RSMEngine):
    def run(self, code, timeout=5):
        out = super().run(code, timeout)
        return "\n".join(
            l for l in out.splitlines() if not l.startswith("DEBUG:")
        )


class NimMEngine(Engine):
    def run(self, code, timeout=5):
        try:
            r = subprocess.run(
                [self.path, "-x", code],
                capture_output=True, text=True, timeout=timeout)
            return r.stdout.rstrip("\n")
        except subprocess.TimeoutExpired:
            return "[TIMEOUT]"
        except Exception as e:
            return f"[ERROR: {e}]"


def make_engine(name):
    if name == "rsm":
        return RSMEngine("RSM", os.environ.get("RSM_BIN", "/Users/mark/_rsm/rsm"))
    if name == "rfc":
        return RFCEngine("RFC", os.environ.get("RFC_BIN", "/Users/mark/_rfc/builddir/rfc"))
    if name == "nimm":
        base = os.environ.get("NIMM_DIR", "/Users/mark/_diary/ports/nimm-annotated")
        return NimMEngine("NimM", os.environ.get("NIMM_BIN", os.path.join(base, "nimm")))
    return None


# ── Test definitions ────────────────────────────────────────────────────────
# Tuple: (name, m_code, expected_stdout, category, std_ref, description)
# std_ref cites ANSI X11.1-1994 section numbering.

TESTS = [
    # ── NUM_CANON: canonical numeric forms (§5.2 Numeric forms; §2.2.5) ──
    ("NUM_LEAD_ZEROS",   'WRITE 007',                    "7",    "NumCanon",  "5.2",   "leading zeros stripped"),
    ("NUM_TRAIL_ZEROS",  'WRITE 7.500',                  "7.5",  "NumCanon",  "5.2",   "trailing fraction zeros stripped"),
    ("NUM_DOT_LEAD",     'WRITE .5',                     ".5",   "NumCanon",  "5.2",   "no redundant leading 0"),
    ("NUM_EXP_POS",      'WRITE 1E2',                    "100",  "NumCanon",  "5.2",   "exponent expanded"),
    ("NUM_NEG_FRAC",     'WRITE -.25',                   "-.25", "NumCanon",  "5.2",   "negative fraction canonical"),
    ("NUM_PLUS_PREFIX",  'WRITE +7',                     "7",    "NumCanon",  "5.2",   "unary plus drops"),
    ("NUM_INT_ZERO",     'WRITE 0.0',                    "0",    "NumCanon",  "5.2",   "zero canonicalizes"),
    ("NUM_CONCAT_FORM",  'WRITE 1_2',                    "12",   "NumCanon",  "5.2",   "canonical form in concatenation"),

    # ── ARITH: left-to-right evaluation, no precedence (§8.2) ──
    ("ARITH_PRECEDENCE", 'WRITE 2+3*4',                  "20",   "Arith",     "8.2",   "left-to-right, not 14"),
    ("ARITH_SUB_ADD",    'WRITE 10-2+3',                 "11",   "Arith",     "8.2",   "left-to-right chain"),
    ("ARITH_IDIV",       'WRITE 7\\2',                   "3",    "Arith",     "8.2.4", "integer divide truncates"),
    ("ARITH_IDIV_NEG",   'WRITE -7\\2',                  "-3",   "Arith",     "8.2.4", "truncate toward zero"),
    ("ARITH_MOD",        'WRITE 7#2',                    "1",    "Arith",     "8.2.5", "modulo"),
    ("ARITH_MOD_NEG",    'WRITE -7#2',                   "1",    "Arith",     "8.2.5", "sign follows divisor"),
    ("ARITH_POW",        'WRITE 2**3',                   "8",    "Arith",     "8.2.6", "exponentiation"),
    ("ARITH_POW_ASSOC",  'WRITE 2**3**2',                "64",   "Arith",     "8.2",   "(2**3)**2 left-assoc, not 512"),
    ("ARITH_UNARY_POW",  'WRITE -2**2',                  "4",    "Arith",     "8.2",   "unary binds tighter: (-2)**2"),
    ("ARITH_MIXED",      'WRITE 20\\3*2',                "12",   "Arith",     "8.2",   "(20\\3)*2"),
    ("ARITH_UNARY_CHAIN",'WRITE -+-3',                   "3",    "Arith",     "8.2",   "stacked unary operators"),
    ("ARITH_COERCE_NONNUM", 'WRITE 7-"xyz"',             "7",    "Arith",     "2.2.2", "non-numeric operand coerces to 0 (#284)"),
    ("ARITH_COERCE_PREFIX", 'WRITE 10-"7abc"',           "3",    "Arith",     "2.2.2", "leading numeric prefix used (#284)"),

    # ── COMPARE: numeric vs string comparison rules (§8.3) ──
    ("CMP_NUMERIC_STR",  'WRITE 5>"10"',                 "0",    "Compare",   "8.3",   "both numeric: 5>10 false"),
    ("CMP_NUM_CANON_EQ", 'WRITE "007"=7',                "1",    "Compare",   "8.3",   "numeric interpretation equal"),
    ("CMP_FRAC_EQ",      'WRITE "7.0"=7',                "1",    "Compare",   "8.3",   "numeric equality across forms"),
    ("CMP_FRAC_EQ_STR",  'WRITE "7.0"="7"',              "1",    "Compare",   "8.3",   "both numeric-looking: numeric compare"),
    ("CMP_SPACE_NOTNUM", 'WRITE " 5"=5',                 "0",    "Compare",   "8.3",   "space breaks numeric prefix"),
    ("CMP_PARTIAL_STR",  'WRITE "5x">"10"',              "1",    "Compare",   "8.3",   "non-numeric operand: string collation"),
    ("CMP_CASE",         'WRITE "A"<"a"',                "1",    "Compare",   "8.3",   "ASCII collation uppercase first"),
    ("CMP_DIGIT_LETTER", 'WRITE "9"<"A"',                "1",    "Compare",   "8.3",   "digits before letters"),
    ("CMP_NOT_EQUAL",    'WRITE 1\'=2',                  "1",    "Compare",   "8.3",   "not-equal operator"),

    # ── LOGICAL: & ! ' truth values (§8.4) ──
    ("LOG_AND",          'WRITE 1&1',                    "1",    "Logical",   "8.4",   "logical and"),
    ("LOG_AND_FALSE",    'WRITE 1&0',                    "0",    "Logical",   "8.4",   "and with false"),
    ("LOG_OR",           'WRITE 0!1',                    "1",    "Logical",   "8.4",   "logical or"),
    ("LOG_NOT",          "WRITE '0",                     "1",    "Logical",   "8.4",   "logical not"),
    ("LOG_NOT_TRUE",     "WRITE '1",                     "0",    "Logical",   "8.4",   "not of true"),

    # ── TRUTHINESS: numeric prefix rule (§2.2.4 Truth values) ──
    ("TRUTH_EMPTY",      'WRITE:"" "T"',                 "",     "Truth",     "2.2.4", "empty is false"),
    ("TRUTH_ZERO",       'WRITE:0 "T"',                  "",     "Truth",     "2.2.4", "zero is false"),
    ("TRUTH_ZERO_DEC",   'WRITE:"0.00" "T"',             "",     "Truth",     "2.2.4", "numeric-zero string is false"),
    ("TRUTH_ALPHA",      'WRITE:"abc" "T"',              "",     "Truth",     "2.2.4", "no numeric prefix: zero: false"),
    ("TRUTH_PREFIX",     'WRITE:"3apples" "T"',          "T",    "Truth",     "2.2.4", "longest numeric prefix: 3: true"),
    ("TRUTH_EXP",        'WRITE:"2e3" "T"',              "T",    "Truth",     "2.2.4", "scientific prefix true"),
    ("TRUTH_POSTCOND",   'SET I=3 WRITE:I>2 "T"',        "T",    "Truth",     "7.1.3", "postconditional true"),
    ("TRUTH_POSTCOND_F", 'SET I=3 WRITE:I<2 "T"',        "",     "Truth",     "7.1.3", "postconditional false skips"),

    # ── CONCAT: string concatenation operator _ (§8.2.7) ──
    ("CONCAT_BASIC",     'WRITE "a"_"b"',                "ab",   "Concat",    "8.2.7", "two literals"),
    ("CONCAT_MIXED",     'WRITE "A"_79_"B"',             "A79B", "Concat",    "8.2.7", "numbers concatenate canonically"),
    ("CONCAT_CHAIN",     'WRITE "x"_1_"y"_2_"z"',        "x1y2z","Concat",    "8.2.7", "left-assoc chain"),

    # ── PATTERN: ? pattern match operator (§8.6) ──
    ("PAT_MATCH_N",      'WRITE "123"?3N',               "1",    "Pattern",   "8.6",   "three digits"),
    ("PAT_FAIL_N",       'WRITE "12A"?3N',               "0",    "Pattern",   "8.6",   "letter breaks digit run"),
    ("PAT_UL",           'WRITE "Abc"?1U2L',             "1",    "Pattern",   "8.6",   "upper then lower"),
    ("PAT_REPEAT_ANY",   'WRITE "xyz"?1.E',              "1",    "Pattern",   "8.6",   ".E repeats any"),
    ("PAT_EXACT_ANY",    'WRITE "abc"?3E',               "1",    "Pattern",   "8.6",   "exactly three any-chars"),
    ("PAT_ZERO_OK",      'WRITE ""?.N',                  "1",    "Pattern",   "8.6",   "zero-length matches .N"),
    ("PAT_NEGATE",       "WRITE \"abc\"'?3N",            "1",    "Pattern",   "8.6",   "negated pattern match"),
    ("PAT_ALTERNATION",  'WRITE "A"?1"X"!1"A"',          "1",    "Pattern",   "8.6",   "alternation second branch"),
    ("PAT_LITERAL_SEQ",  'WRITE "abc"?1L1"b"1L',         "1",    "Pattern",   "8.6",   "mixed atoms sequence"),

    # ── FN_ASCII_CHAR: $ASCII / $CHAR (§9.1, §9.2) ──
    ("FN_ASCII_DEF",     'WRITE $ASCII("ABC")',          "65",   "FnAsciiChar","9.1",  "default position 1"),
    ("FN_ASCII_POS",     'WRITE $ASCII("ABC",3)',        "67",   "FnAsciiChar","9.1",  "third character"),
    ("FN_ASCII_OOB",     'WRITE $ASCII("A",2)',          "-1",   "FnAsciiChar","9.1",  "position beyond length: -1"),
    ("FN_ASCII_EMPTY",   'WRITE $ASCII("")',             "-1",   "FnAsciiChar","9.1",  "empty string: -1"),
    ("FN_CHAR_MULTI",    'WRITE $CHAR(72,73)',           "HI",   "FnAsciiChar","9.2",   "multiple codes"),

    # ── FN_EXTRACT: $EXTRACT (§9.4) ──
    ("FN_EXTRACT_ONE",   'WRITE $EXTRACT("ABCDE")',      "A",    "FnExtract", "9.4",   "single-arg: first char"),
    ("FN_EXTRACT_POS",   'WRITE $EXTRACT("ABCDE",3)',    "C",    "FnExtract", "9.4",   "single position: one char"),
    ("FN_EXTRACT_RANGE", 'WRITE $EXTRACT("ABCDE",2,4)',  "BCD",  "FnExtract", "9.4",   "range inclusive"),
    ("FN_EXTRACT_CLAMP", 'WRITE $EXTRACT("ABC",2,99)',   "BC",   "FnExtract", "9.4",   "end clamped to string end"),
    ("FN_EXTRACT_INV",   'WRITE $EXTRACT("ABC",3,2)',    "",     "FnExtract", "9.4",   "first>last: null"),

    # ── FN_LENGTH: $LENGTH (§9.8) ──
    ("LEN_CHARS",        'WRITE $LENGTH("abc")',         "3",    "FnLength",  "9.8",   "character count"),
    ("LEN_EMPTY",        'WRITE $LENGTH("")',            "0",    "FnLength",  "9.8",   "empty: zero"),
    ("LEN_PIECES",       'WRITE $LENGTH("a,b,c",",")',   "3",    "FnLength",  "9.8",   "delimiter count+1"),
    ("LEN_PIECES_EMPTY", 'WRITE $LENGTH("",",")',        "1",    "FnLength",  "9.8",   "empty has one empty piece"),
    ("LEN_PIECES_GAP",   'WRITE $LENGTH("a,b,,c",",")',  "4",    "FnLength",  "9.8",   "empty pieces counted"),

    # ── FN_FIND: $FIND (§9.5) ──
    ("FIND_FOUND",       'WRITE $FIND("ABCDE","CD")',    "5",    "FnFind",    "9.5",   "position AFTER substring"),
    ("FIND_MISSING",     'WRITE $FIND("ABCDE","XY")',    "0",    "FnFind",    "9.5",   "absent: zero"),
    ("FIND_START",       'WRITE $FIND("ABCDE","CD",3)',  "5",    "FnFind",    "9.5",   "start position honored"),
    ("FIND_EMPTY_TGT",   'WRITE $FIND("ABCDEF","",4)',   "4",    "FnFind",    "9.5",   "empty target: returns position"),

    # ── FN_PIECE: $PIECE (§9.12) ──
    ("PIECE_FIRST",      'WRITE $PIECE("a,b,c",",")',    "a",    "FnPiece",   "9.12",  "default: first piece"),
    ("PIECE_NTH",        'WRITE $PIECE("a,b,c",",",2)',  "b",    "FnPiece",   "9.12",  "second piece"),
    ("PIECE_RANGE",      'WRITE $PIECE("a,b,c",",",2,3)',"b,c",  "FnPiece",   "9.12",  "piece range inclusive"),
    ("PIECE_NO_DELIM",   'WRITE $PIECE("abc","x")',      "abc",  "FnPiece",   "9.12",  "delimiter absent: whole string"),
    ("PIECE_EMPTY_SEG",  'WRITE "["_$PIECE("a,,c",",",2)_"]"',"[]","FnPiece", "9.12",  "middle empty piece"),

    # ── FN_FORMAT: $JUSTIFY, $REVERSE, $TRANSLATE (§9.7/9.15/9.16) ──
    ("JUS_WIDTH",        'WRITE "["_$JUSTIFY(42,6)_"]"', "[    42]","FnFormat","9.7",  "right-justified width"),
    ("JUS_NEG",          'WRITE "["_$JUSTIFY(-3.2,6)_"]"',"[  -3.2]","FnFormat","9.7", "negative right-justified"),
    ("JUS_DECIMALS",     'WRITE $JUSTIFY(3.146,0,2)',    "3.15", "FnFormat",  "9.7",   "rounds to N decimals"),
    ("JUS_DEC_NONNUM",   'WRITE "["_$JUSTIFY("zz9",9,1)_"]"', "[      0.0]", "FnFormat", "9.7", "decimals arg forces numeric coercion (#285)"),
    ("REV_STRING",       'WRITE $REVERSE("ABC")',        "CBA",  "FnFormat",  "9.15",  "reverse characters"),
    ("TRANS_MAP",        'WRITE $TRANSLATE("HELLO","EL","IP")',"HIPPO","FnFormat","9.16","char mapping"),
    ("TRANS_DELETE",     'WRITE $TRANSLATE("ABC","BC","B")',  "AB","FnFormat","9.16", "unmapped old-chars deleted"),

    # ── FN_FLOW: $SELECT, $RANDOM (§9.13/§9.11) ──
    ("SEL_TRUE",         'WRITE $SELECT(1:"yes",1:"no")',"yes",  "FnFlow",    "9.13",  "first true wins"),
    ("SEL_DEFAULT",      'WRITE $SELECT(0:"a",1:"b")',   "b",    "FnFlow",    "9.13",  "falls to default arm"),
    ("RND_RANGE",        "SET X=$RANDOM(5) WRITE (X'<0)&(X<5)","1","FnFlow",  "9.11",  "$RANDOM(n) in [0,n)"),

    # ── FN_VAR: $DATA, $GET, $INCREMENT (§9.3/§9.6/§9.10) ──
    ("DATA_UNDEF",       'WRITE $DATA(ZZUNDEF)',         "0",    "FnVar",     "9.3",   "undefined local: 0"),
    ("DATA_DEFINED",     'SET A=1 WRITE $DATA(A)',       "1",    "FnVar",     "9.3",   "defined with value: 1"),
    ("DATA_INTERIOR",    'KILL ^D SET ^D(1,2)="v" WRITE $DATA(^D(1))',"10","FnVar",   "9.3",   "descendants only: 10"),
    ("DATA_BOTH",        'KILL ^D SET ^D(1)="v",^D(1,2)="w" WRITE $DATA(^D(1))',"11","FnVar","9.3","value+descendants: 11"),
    ("GET_DEFAULT",      'WRITE $GET(ZZUNDEF,"dflt")',   "dflt", "FnVar",     "9.6",   "default on undefined"),
    ("GET_DEFINED",      'SET A="v" WRITE $GET(A,"dflt")',"v",   "FnVar",     "9.6",   "value overrides default"),
    ("INCR_NEW",         'KILL IA WRITE $INCREMENT(IA)', "1",    "FnVar",     "9.10",  "undefined increments from 0"),
    ("INCR_STEP",        'SET A=1 WRITE $INCREMENT(A,5)',"6",    "FnVar",     "9.10",  "returns new value"),

    # ── FN_ORDER_QUERY: $ORDER, $QUERY, $QL, $QS (§9.9/§9.14/§9.17/§9.18) ──
    ("ORD_NEXT",         'SET A(1)=1,A(3)=1 WRITE $ORDER(A(1))',"3","FnOrderQuery","9.9","next subscript"),
    ("ORD_LAST",         'SET A(1)=1,A(3)=1 WRITE $ORDER(A(3))',"","FnOrderQuery","9.9","past last: null"),
    ("ORD_FIRST_VIA_EMPTY",'SET A(1)=1,A(3)=1 WRITE $ORDER(A(""))',"1","FnOrderQuery","9.9","empty start: lowest"),
    ("ORD_BACK_EMPTY",   'SET A(1)=1,A(3)=1 WRITE $ORDER(A("",-1))',"","FnOrderQuery","9.9","backward past first: null"),
    ("QRY_FIRST",        'KILL ^Q SET ^Q(1)="a",^Q(1,2)="b" WRITE $QUERY(^Q(""))',"^Q(1)","FnOrderQuery","9.14","first node path"),
    ("QRY_DEEP",         'KILL ^Q SET ^Q(1)="a",^Q(1,2)="b" WRITE $QUERY(^Q(1))',"^Q(1,2)","FnOrderQuery","9.14","depth-first next"),
    ("QRY_END",          'KILL ^Q SET ^Q(1)="a" WRITE $QUERY(^Q(1))',"",   "FnOrderQuery","9.14","no further node: null"),
    ("QLEN",             'WRITE $QL("^Q(1,2)")',         "2",    "FnOrderQuery","9.17","subscript count"),
    ("QSUB",             'WRITE $QS("^Q(1,""ab"")",2)',  "ab",   "FnOrderQuery","9.18","extract subscript"),
    ("ORD_GLOB",         'KILL ^G SET ^G(1)="a",^G(3)="b" WRITE $ORDER(^G(0))',"1","FnOrderQuery","9.9","global order"),

    # ── SV_BASIC: special variables (§6.3) ──
    ("SV_IO",            'WRITE $IO',                    "0",    "SpecVar",   "6.3.9", "principal device id"),
    ("SV_PRINCIPAL",     'WRITE $PRINCIPAL',             "0",    "SpecVar",   "6.3.13","principal device id"),
    ("SV_JOB",           'WRITE $JOB>0',                 "1",    "SpecVar",   "6.3.8", "job number positive"),
    ("SV_HOROLOG_FORM",  'WRITE $HOROLOG?.N1",".N',      "1",    "SpecVar",   "6.3.7", "days,seconds shape"),
    ("SV_HOROLOG_DAY",   'WRITE $P($HOROLOG,",")>60000', "1",    "SpecVar",   "6.3.7", "day count plausible"),
    ("SV_STACK",         'WRITE $STACK',                 "0",    "SpecVar",   "6.3.17","top level frame 0"),
    ("SV_ESTACK",        'WRITE $ESTACK',                "0",    "SpecVar",   "6.3.4", "error stack base 0"),
    ("SV_QUIT_TOP",      'WRITE $QUIT',                  "0",    "SpecVar",   "6.3.14","no frame to quit: 0"),
    ("SV_TLEVEL",        'WRITE $TLEVEL',                "0",    "SpecVar",   "6.3.20","no transaction: 0"),
    ("SV_TRESTART",      'WRITE $TRESTART',              "0",    "SpecVar",   "6.3.21","no restarts: 0"),
    ("SV_KEY_EMPTY",     'WRITE $LENGTH($KEY)',          "0",    "SpecVar",   "6.3.10","initially empty"),
    ("SV_ECODE_EMPTY",   'WRITE $LENGTH($ECODE)',        "0",    "SpecVar",   "6.3.3", "initially empty"),
    ("SV_ETRAP_EMPTY",   'WRITE $LENGTH($ETRAP)',        "0",    "SpecVar",   "6.3.5", "initially empty"),
    ("SV_STORAGE",       'WRITE $STORAGE>0',             "1",    "SpecVar",   "6.3.19","positive storage"),
    ("SV_X_AFTER_WRITE", 'WRITE "AB" WRITE $X',          "AB2",  "SpecVar",   "6.3.22","column advanced by 2"),
    ("SV_Y_AFTER_LF",    'WRITE !,"A" WRITE $Y',         "\nA1", "SpecVar",   "6.3.23","line counter after newline"),

    # ── CMD_SET: assignment semantics (§7.2.20) ──
    ("SET_GROUP",        'SET (A,B,C)=7 WRITE A_B_C',    "777",  "CmdSet",    "7.2.20","parenthesized multi-target"),
    ("SET_SEQUENTIAL",   'SET A=1,B=A+1 WRITE A_B',      "12",   "CmdSet",    "7.2.20","later items see earlier values"),
    ("SET_UNDEF_READ",   'SET E="" WRITE $LENGTH(E)',    "0",    "CmdSet",    "2.2.2", "empty string has zero length"),
    ("SET_KEYWORD_CASE", 'sEt Kc=1 wRite Kc',            "1",    "CmdSet",    "3.2",   "keywords case-insensitive"),
    ("SET_IDENT_CASE",   'SET Abc=1 SET abc=2 WRITE Abc_abc',"12","CmdSet",    "3.2",   "identifiers case-sensitive"),

    # ── CMD_IF_ELSE: IF, ELSE, comma conditions (§7.2.8/§7.2.4, $TEST) ──
    ("IF_SIMPLE",        'IF 1 WRITE "T"',               "T",    "CmdIfElse", "7.2.8", "true executes body"),
    ("IF_FALSE_SKIP",    'IF 0 WRITE "T"',               "",     "CmdIfElse", "7.2.8", "false skips rest of line"),
    ("IF_MULTI_ALL",     'IF 1,1 WRITE "T"',             "T",    "CmdIfElse", "7.2.8", "all conditions must hold"),
    ("IF_MULTI_STOP",    'IF 1,0 WRITE "T"',             "",     "CmdIfElse", "7.2.8", "second condition stops"),
    ("ELSE_RUNS",        'IF 0 ELSE  WRITE "E"',         "E",    "CmdIfElse", "7.2.4", "else when $TEST false"),
    ("ELSE_SKIPS",       'IF 1 ELSE  WRITE "E"',         "",     "CmdIfElse", "7.2.4", "else skipped when true"),

    # ── CMD_FOR: all FOR forms (§7.2.6) ──
    ("FOR_COUNTED",      'FOR I=1:1:3 WRITE I',          "123",  "CmdFor",    "7.2.6", "counted up"),
    ("FOR_DOWN",         'FOR I=4:-1:1 WRITE I',         "4321", "CmdFor",    "7.2.6", "negative step"),
    ("FOR_LIST",         'FOR I=1,3,5 WRITE I',          "135",  "CmdFor",    "7.2.6", "list form"),
    ("FOR_MIXED_LIST",   'FOR I=1,2:1:3 WRITE I',        "123",  "CmdFor",    "7.2.6", "list item may be a range"),
    ("FOR_EMPTY_RANGE",  'FOR I=1:1:0 WRITE I',          "",     "CmdFor",    "7.2.6", "limit<init: no iterations"),
    ("FOR_ARGLESS",      'SET I=0 FOR  SET I=I+1 QUIT:I>3  WRITE I',"123","CmdFor","7.2.6","argumentless with QUIT"),
    ("FOR_VAR_STEP",     'SET S=2 FOR I=1:S:5 WRITE I',  "135",  "CmdFor",    "7.2.6", "variable step size"),

    # ── CMD_NEW_KILL: scoping commands (§7.2.12/§7.2.9) ──
    ("NEW_EXCLUSIVE",    'SET A=1,B=2,C=3 NEW (A,B) WRITE $DATA(C)',"0","CmdNewKill","7.2.12","exclusive NEW discards unlisted"),
    ("NEW_EXCLUSIVE_KEEP",'SET A=1,B=2,C=3 NEW (A,B) WRITE $DATA(A)',"1","CmdNewKill","7.2.12","listed survive"),
    ("KILL_PLAIN",       'SET A=1 KILL A WRITE $DATA(A)',"0",    "CmdNewKill","7.2.9", "simple kill"),
    ("KILL_EXCLUSIVE",   'SET A=1,B=1,K1=1 KILL (A,B) WRITE $DATA(K1)',"0","CmdNewKill","7.2.9","kills everything but list"),
    ("KILL_EXCLUSIVE_KEEP",'SET A=1,B=1,K1=1 KILL (A,B) WRITE $DATA(B)',"1","CmdNewKill","7.2.9","kept variable survives"),
    ("KILL_GLOBAL_DESC", 'KILL ^K SET ^K(1,1)="a",^K(1,2)="b" KILL ^K(1) WRITE $DATA(^K(1))',"0","CmdNewKill","7.2.9","kill removes descendants"),
    ("KILL_BARE_LOCALS", 'SET L1=1,L2=2 KILL  WRITE $DATA(L1)+$DATA(L2)',"0","CmdNewKill","7.2.9","bare KILL clears locals"),

    # ── CMD_MISC: MERGE, LOCK, XECUTE, indirection (§7.2.11/§7.2.10/§7.2.24/§2.3) ──
    ("MERGE_COPIES",     'KILL ^S,^D SET ^S(1)="a",^S(2)="b" MERGE ^D=^S WRITE ^D(2)',"b","CmdMisc","7.2.11","tree copy to target"),
    ("MERGE_NONDESTRUCT",'KILL ^S,^D SET ^S(1)="a",^D(9)="old" MERGE ^D=^S WRITE ^D(9)_^D(1)',"olda","CmdMisc","7.2.11","existing target nodes survive"),
    ("LOCK_OK",          'LOCK +^L WRITE "ok" LOCK -^L', "ok",   "CmdMisc",   "7.2.10","incremental lock cycle"),
    ("XECUTE_ARG",       'SET X=41 XECUTE "WRITE X+1"',  "42",   "CmdMisc",   "7.2.24","caller locals visible in XECUTE frame"),
    ("IND_NAME_SET",     'SET B="C",@B=5 WRITE C',       "5",    "CmdMisc",   "2.3.2", "name indirection in SET target"),

    # ── GLOBALS: global storage behavior (§2.4) ──
    ("GLB_ROUNDTRIP",    'KILL ^Gr SET ^Gr(1,2)="val" WRITE ^Gr(1,2)',"val","Globals", "2.4",   "subscripted set/get"),
    ("GLB_NAKED",        'KILL ^Nk SET ^Nk(1,2)="x",^(3)="y" WRITE ^Nk(1,3)',"y","Globals","2.4.2","naked reference replaces last subscript"),
    ("GLB_STR_SUBS",     'KILL ^Gs SET ^Gs("abc")="x" WRITE ^Gs("abc")',"x","Globals","2.4",  "string subscripts"),
    ("GLB_MIXED_SUBS",   'KILL ^Gm SET ^Gm(1,"two")="z" WRITE ^Gm(1,"two")',"z","Globals","2.4",  "mixed-type subscript list"),
    ("GLB_CASE_SENS",    'KILL ^Cs SET ^Cs="x" SET ^cs="y" WRITE ^Cs_^cs',"xy","Globals","3.2","global names case-sensitive"),
    ("GLB_KILL_NODE",    'KILL ^Kd SET ^Kd="v" KILL ^Kd WRITE $DATA(^Kd)',"0","Globals","2.4",   "scalar kill"),
    ("GLB_GET_INTERIOR", 'KILL ^Gi SET ^Gi(1,2)="v" WRITE $GET(^Gi(1))',"","Globals","9.6",    "interior node has no value"),
    ("GLB_ORDER_ACROSS", 'SET ^Ga(1)="a",^Ga(2)="b" KILL ^Ga(1) WRITE $ORDER(^Ga(""))',"2","Globals","9.9","order reflects kills"),

    # ── SUSPECTBUGS: explicit regression tests for suspected bugs found
    #    during cross-implementation investigation. Expectations derived
    #    from the standard text, not from any implementation.
    #  BUG01/02 NimM truth-value rule   BUG03-05 RSM comparison semantics
    #  BUG06 RSM ELSE                   BUG07 modulo sign (settled §8.2.5)
    #  BUG08 RSM $ORDER empty backward  BUG09 RSM pattern alternation
    #  BUG10 NimM comma target lists    BUG11 NimM KILL descendants
    #  BUG12 NimM MERGE non-destructive
    ("BUG01_TRUTH_NONNUM", 'WRITE:"abc" "T"',          "",     "SuspectBugs","2.2.4", "BUG01: non-numeric string is FALSE"),
    ("BUG02_TRUTH_ZEROSTR",'WRITE:"0.00" "T"',         "",     "SuspectBugs","2.2.4", "BUG02: numeric-zero string is FALSE"),
    ("BUG03_COLLATE_LOWER",'WRITE "a"<"b"',            "1",    "SuspectBugs","8.3",   "BUG03: plain string collation"),
    ("BUG04_COLLATE_MIXED",'WRITE "9"<"A"',            "1",    "SuspectBugs","8.3",   "BUG04: digit<letter collation"),
    ("BUG05_NUMEQ_FORMS",  'WRITE "007"=7',            "1",    "SuspectBugs","8.3",   "BUG05: numeric compare across forms"),
    ("BUG06_ELSE_RUNS",    'IF 0 WRITE "no" ELSE  WRITE "yes"',"yes","SuspectBugs","7.2.4","BUG06: ELSE executes on false $TEST"),
    ("BUG07_MOD_NEGSIGN",  'WRITE -7#2',               "1",    "SuspectBugs","8.2.5", "BUG07: modulo sign follows divisor"),
    ("BUG08_ORD_BACK_EMPTY",'SET A(1)=1,A(3)=1 WRITE $ORDER(A("",-1))',"","SuspectBugs","9.9","BUG08: backward order past first is null"),
    ("BUG09_PAT_ALT",      'WRITE "A"?1"X"!1"A"',      "1",    "SuspectBugs","8.6",   "BUG09: pattern alternation"),
    ("BUG10_SET_GROUP",    'SET (A,B,C)=7 WRITE A_B_C',"777",  "SuspectBugs","7.2.20","BUG10: parenthesized SET target list"),
    ("BUG11_KILL_GLB_DESC",'KILL ^Bg SET ^Bg(1,1)="a",^Bg(1,2)="b" KILL ^Bg(1) WRITE $DATA(^Bg(1))',"0","SuspectBugs","7.2.9","BUG11: KILL removes global descendants"),
    ("BUG12_MERGE_KEEP",   'KILL ^Ms,^Md SET ^Ms(1)="a",^Md(9)="old" MERGE ^Md=^Ms WRITE ^Md(9)_^Md(1)',"olda","SuspectBugs","7.2.11","BUG12: MERGE preserves existing target nodes"),
]


# ── Runner ──────────────────────────────────────────────────────────────────


def run_suite(engines, tests, verbose=False):
    results = {}
    timings = {e.name: {} for e in engines}
    for name, code, expected, category, ref, desc in tests:
        results[name] = {}
        for eng in engines:
            t0 = time.perf_counter()
            actual = eng.run(code)
            dt = time.perf_counter() - t0
            timings[eng.name].setdefault(name, []).append(dt)
            results[name][eng.name] = (actual, expected, actual == expected)
            if verbose and actual != expected:
                print(f"  FAIL {eng.name}: {name} want {expected!r} got {actual!r}")
    return results, timings


def print_summary(results, engines, tests):
    print()
    print("=" * 76)
    print("ANSI/ISO M Conformance Results (ISO/IEC 11756:1999 / ANSI X11.1-1994)")
    print("=" * 76)
    print()
    print(f"{'Implementation':<14} {'Pass':>5} {'Fail':>5} {'Error':>6} {'Total':>6} {'Rate':>8}")
    print("-" * 48)
    for eng in engines:
        p = sum(1 for n, *_ in tests if results[n][eng.name][2])
        e = sum(1 for n, *_ in tests if results[n][eng.name][0].startswith("["))
        f = len(tests) - p
        rate = p / len(tests) * 100 if tests else 0
        print(f"{eng.name:<14} {p:>5} {f:>5} {e:>6} {len(tests):>6} {rate:>7.1f}%")

    cats = []
    for _, _, _, c, _, _ in tests:
        if c not in cats:
            cats.append(c)

    print()
    print("Per-Category Breakdown")
    print("-" * (16 + 8 * len(engines)))
    print(f"{'Category':<16}" + "".join(f"{e.name:>8}" for e in engines))
    for c in cats:
        ct = [t for t in tests if t[3] == c]
        row = f"{c:<16}"
        for eng in engines:
            ok = sum(1 for t in ct if results[t[0]][eng.name][2])
            row += f"{ok}/{len(ct):>4}"
        print(row)


def print_failures(results, engines, tests):
    print()
    print("=" * 76)
    print("Detailed Failures")
    print("=" * 76)
    any_fail = False
    for eng in engines:
        fails = [(n, code, exp, cat, ref, desc) for n, code, exp, cat, ref, desc in tests
                 if not results[n][eng.name][2]]
        if not fails:
            continue
        any_fail = True
        print(f"\n--- {eng.name}: {len(fails)} failure(s) ---")
        for n, code, exp, cat, ref, desc in fails:
            got = results[n][eng.name][0]
            print(f"\n{n} [{cat} §{ref}] {desc}")
            print(f"  Code:     {code}")
            print(f"  Expected: {exp!r}")
            print(f"  Got:      {got!r}")
    if not any_fail:
        print("\nAll implementations pass all tests.")


def print_timing(timings, engines, tests):
    print()
    print("=" * 76)
    print("Per-Test Timing (avg of runs)")
    print("=" * 76)
    totals = {e.name: 0.0 for e in engines}
    for name, *_ in tests:
        row = f"{name:<24}"
        for eng in engines:
            ts = timings[eng.name].get(name, [])
            if ts:
                avg = sum(ts) / len(ts)
                totals[eng.name] += avg
                row += f"{avg*1000:>10.2f}ms"
            else:
                row += f"{'—':>12}"
        print(row)
    row = f"{'TOTAL':<24}"
    for eng in engines:
        row += f"{totals[eng.name]*1000:>10.2f}ms"
    print(row)


def main():
    ap = argparse.ArgumentParser(description="ANSI/ISO M conformance suite")
    ap.add_argument("--impls", default="nimm,rsm,rfc",
                    help="comma-separated: nimm,rsm,rfc")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--timing", action="store_true")
    ap.add_argument("--failures", action="store_true")
    ap.add_argument("--category", help="run single category")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    tests = TESTS
    if args.category:
        tests = [t for t in tests if t[3].lower() == args.category.lower()]

    engines = []
    for impl in [s.strip().lower() for s in args.impls.split(",")]:
        eng = make_engine(impl)
        if eng is None:
            print(f"Unknown implementation: {impl}")
            sys.exit(1)
        engines.append(eng)

    print(f"Verifying engines...")
    live = []
    for eng in engines:
        out = eng.run('WRITE "hello"')
        ok = "hello" in out
        print(f"  {eng.name}: {'OK' if ok else 'FAIL (' + repr(out) + ')'}")
        if ok:
            live.append(eng)
    if not live:
        print("No functional engines.")
        sys.exit(1)

    print(f"\nRunning {len(tests)} tests x {args.runs} run(s) "
          f"against {', '.join(e.name for e in live)}...\n")

    results, timings = None, None
    for run in range(1, args.runs + 1):
        if args.runs > 1:
            print(f"-- Run {run}/{args.runs} --")
        rr, tt = run_suite(live, tests, args.verbose and run == 1)
        if results is None:
            results, timings = rr, tt
        else:
            for en, td in tt.items():
                for tn, times in td.items():
                    timings[en].setdefault(tn, []).extend(times)

    print_summary(results, live, tests)
    if args.timing or args.runs > 1:
        print_timing(timings, live, tests)
    if args.failures:
        print_failures(results, live, tests)
    print()


if __name__ == "__main__":
    main()
