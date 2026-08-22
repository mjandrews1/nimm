#!/usr/bin/env python3
"""
Extended M/MUMPS Conformance Test Suite

Scope expansion beyond tests/ansi_iso_m_conformance.py (170 tests @ ISO/IEC
11756:1999 core):

  SSV     — Structured System Variables (^$JOB, ^$LOCK, ^$GLOBAL)   [§8.6]
  Std99   — Standard features not covered by the 170-test suite
            (indirection forms, $QLENGTH, FOR argument lists, MERGE
            destination preservation, $TRANSLATE/$REVERSE, negative
            $JUSTIFY width, $ECODE assignment)
  RSMExt  — RSM-documented implementation extensions (scientific exponent
            notation enabled by default; numeric-first collation for
            canonical subscripts)
  NimMExt — NimM-specific extensions ($NI_* data structures, $NI_JSON,
            $NI_UUID, $CASE). Runs ONLY when --impls nimm; expected values
            are NimM's own documented behavior (regression freeze).

Expected values verified empirically against frozen references RSM V1.83.1
and RFC V1.00.0 (both references agree on every test). NimM is under test.

Isolation discipline: RSM and RFC daemons must NEVER run concurrently.
Run one implementation's leg at a time:

    rsm -j 4 /tmp/rsm_test.dat &        # RSM daemon up
    python3 mumps_extended_conformance.py --impls rsm --runs 10
    rsm -k /tmp/rsm_test.dat            # stop before RFC starts

    rfc -j 4 /tmp/rfc_test.dat &        # RFC daemon up
    python3 mumps_extended_conformance.py --impls rfc --runs 10
    rfc -k /tmp/rfc_test.dat

    python3 mumps_extended_conformance.py --impls nimm --runs 10  # standalone

Environment ports: NIMM_DIR, NIMM_BIN, RSM_BIN, RFC_BIN, RSM_DBFILE,
RFC_DBFILE (identical to ansi_iso_m_conformance.py).
"""

import argparse
import os
import subprocess
import sys

# ── Engine wrappers (mirror ansi_iso_m_conformance.py) ─────────────────────


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
            env.update(getattr(self, "_rfc_env", {}))
            r = subprocess.run(
                [self.path, "-x", code],
                capture_output=True, text=True, timeout=timeout, env=env)
            return r.stdout.rstrip("\n")
        except subprocess.TimeoutExpired:
            return "[TIMEOUT]"
        except Exception as e:
            return f"[ERROR: {e}]"


class RFCEngine(RSMEngine):
    # The rfc binary shares rsm's client code: it connects to the database
    # named by RSM_DBFILE (RFC_DBFILE is not consulted). Point both at the
    # RFC environment.
    def run(self, code, timeout=5):
        self._rfc_env = {
            "RSM_DBFILE": os.environ.get("RFC_DBFILE", "/tmp/rfc_test.dat"),
            "RFC_DBFILE": os.environ.get("RFC_DBFILE", "/tmp/rfc_test.dat"),
        }
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
        path = os.environ.get("NIMM_BIN", os.path.join(base, "nimm"))
        if not os.path.exists(path):
            print(f"Building NimM...")
            subprocess.run(["nim", "c", "-d:release", "-o:nimm", "main.nim"],
                           cwd=base, capture_output=True)
        return NimMEngine("NimM", path)
    return None


# ── Test Definitions ───────────────────────────────────────────────────────
# Each test: (name, code, expected, category, ref, notes)
# Expected values = behavior agreed by both frozen references (RSM + RFC).

TESTS = [
    # ── Structured System Variables (ISO 11756 §8.6) ──
    ("SSV_JOB_SELF",
     'WRITE $DATA(^$JOB($JOB))',
     "1", "SSV", "8.6", "^$JOB contains own job entry"),
    ("SSV_LOCK_TAKE",
     'LOCK +^L1 SET X=$DATA(^$LOCK("^L1")) LOCK -^L1 SET Y=$DATA(^$LOCK("^L1")) WRITE X_Y',
     "10", "SSV", "8.6", "^$LOCK reflects lock taken then released"),
    ("SSV_G_ABSENT",
     'WRITE $DATA(^$GLOBAL("^NOSUCH"))',
     "0", "SSV", "8.6", "^$DATA of undefined global is 0"),
    ("SSV_G_ROOTVAL",
     'KILL ^G SET ^G(1)="a" WRITE $DATA(^$GLOBAL("^G"))',
     "0", "SSV", "8.6", "^$GLOBAL reports root value only (ref behavior)"),

    # ── Standard features not covered by the 170-test suite ──
    ("IND_SETVAR",
     'SET B="X",@B=5 WRITE X',
     "5", "Std99", "7.4", "SET via name indirection"),
    ("IND_EXPR",
     'SET A="1+2" WRITE @A',
     "3", "Std99", "7.4", "expression indirection evaluates"),
    ("IND_NAME",
     'SET A="B",B="hello" WRITE @A',
     "hello", "Std99", "7.4", "@ reads through two names"),
    ("FN_QLENGTH",
     'WRITE $QLength("^G(1,2,3)")',
     "3", "Std99", "8.16", "$QLENGTH counts subscripts"),
    ("FOR_LIST_ODD",
     'FOR I=1:2:5 WRITE I',
     "135", "Std99", "10.6", "FOR with incrementing range"),
    ("MERGE_PRESERVE",
     'KILL A,B SET A(1)="x",A="r" SET B(9)="keep" MERGE B=A WRITE B_B(1)_B(9)',
     "rxkeep", "Std99", "7.2.11", "MERGE overwrites root+overlap, keeps others"),
    ("FN_TRANSLATE",
     'WRITE $TRANSLATE("HELLO","LO","JP")',
     "HEJJP", "Std99", "8.20", "$TRANSLATE positional substitution"),
    ("FN_REVERSE",
     'WRITE $REVERSE("abc")',
     "cba", "Std99", "8.17", "$REVERSE reverses string"),
    ("FN_JUSTIFY_NEG",
     'WRITE "["_$JUSTIFY("ab",-5)_"]"',
     "[ab]", "Std99", "8.13", "negative width left-justifies (ref behavior)"),
    ("SV_ECODE_CLEAR",
     'SET $ECODE="" WRITE $ECODE=""',
     "1", "Std99", "6.3.3", "$ECODE assignable, clear reads empty"),

    # ── RSM-documented extensions ──
    ("EXP_NUM_PLUS",
     'WRITE +"2E3"',
     "2000", "RSMExt", "rsm doc", "exponent notation default: +'2E3'=2000"),
    ("EXP_STR_COERCE",
     'WRITE "1E2"+0',
     "100", "RSMExt", "rsm doc", "E-form string coerces numerically"),
    ("COLL_NUM_FIRST",
     'KILL C SET C(2)=1,C("10")=1 WRITE $ORDER(C(""))',
     "2", "RSMExt", "rsm doc", "canonical numeric subs collate first"),
    ("COLL_MIXED_SEQ",
     'KILL C SET C(2)=1,C("10")=1,C(30)=1 WRITE $ORDER(C(2))_"/"_$ORDER(C("10"))',
     "10/30", "RSMExt", "rsm doc", "mixed collation sequence 2 < '10' < 30"),

    # ── NimM extensions (run ONLY against NimM) ──
    # Data structures take (action, id, ...) and return the id on create.
    ("NIARR_BASIC",
     'SET X=$NI_ARRAY("create","ca1") SET N=$NI_ARRAY("add","ca1","v1") '
     'SET M=$NI_ARRAY("add","ca1","v2") '
     'WRITE $NI_ARRAY("len","ca1"),"|",$NI_ARRAY("get","ca1","0"),"|",$NI_ARRAY("get","ca1","1")',
     "2|v1|v2", "NimMExt", "nimm doc", "$NI_ARRAY add/get/len"),
    ("NIARR_SETGET",
     'SET X=$NI_ARRAY("create","ca2") SET Y=$NI_ARRAY("add","ca2","old") '
     'SET Z=$NI_ARRAY("set","ca2","0","new") WRITE $NI_ARRAY("get","ca2","0")',
     "new", "NimMExt", "nimm doc", "$NI_ARRAY set overwrites in place"),
    ("NIOBJ_FIELDS",
     'SET X=$NI_OBJECT("create","co1") SET Y=$NI_OBJECT("set","co1","name","val") '
     'WRITE $NI_OBJECT("get","co1","name"),"|",$NI_OBJECT("has","co1","name"),"|"'
     '_$NI_OBJECT("has","co1","missing"),"|",$NI_OBJECT("len","co1")',
     "val|1|0|1", "NimMExt", "nimm doc", "$NI_OBJECT set/get/has/len"),
    ("NISTK_LIFO",
     'SET X=$NI_STACK("create","cs1") SET A=$NI_STACK("push","cs1","one") '
     'SET B=$NI_STACK("push","cs1","two") '
     'WRITE $NI_STACK("pop","cs1"),"|",$NI_STACK("peek","cs1"),"|",$NI_STACK("len","cs1")',
     "two|one|1", "NimMExt", "nimm doc", "$NI_STACK LIFO order"),
    ("NIQUE_FIFO",
     'SET X=$NI_QUEUE("create","cq1") SET A=$NI_QUEUE("enqueue","cq1","first") '
     'SET B=$NI_QUEUE("enqueue","cq1","second") '
     'WRITE $NI_QUEUE("dequeue","cq1"),"|",$NI_QUEUE("peek","cq1")',
     "first|second", "NimMExt", "nimm doc", "$NI_QUEUE FIFO order"),
    ("NISET_UNIQ",
     'SET X=$NI_SET("create","ct1") SET Y=$NI_SET("add","ct1","a") '
     'SET Z=$NI_SET("add","ct1","a") SET W=$NI_SET("add","ct1","b") '
     'WRITE $NI_SET("has","ct1","a"),"|",$NI_SET("len","ct1")',
     "1|2", "NimMExt", "nimm doc", "$NI_SET deduplicates"),
    ("NIMAP_KV",
     'SET X=$NI_MAP("create","cm1") SET Y=$NI_MAP("set","cm1","k1","v1") '
     'SET Z=$NI_MAP("set","cm1","k2","v2") '
     'WRITE $NI_MAP("get","cm1","k2"),"|",$NI_MAP("has","cm1","k1"),"|",$NI_MAP("keys","cm1")',
     "v2|1|k1,k2", "NimMExt", "nimm doc", "$NI_MAP get/has/keys"),
    ("NISRT_ORDER",
     'SET X=$NI_SORTED("create","cd1") SET A=$NI_SORTED("add","cd1","banana") '
     'SET B=$NI_SORTED("add","cd1","apple") SET C=$NI_SORTED("add","cd1","cherry") '
     'WRITE $NI_SORTED("toseq","cd1"),"|",$NI_SORTED("len","cd1")',
     "apple,banana,cherry|3", "NimMExt", "nimm doc", "$NI_SORTED maintains order"),
    ("NISRT_LEXICO",
     'SET X=$NI_SORTED("create","cd2") SET A=$NI_SORTED("add","cd2","9") '
     'SET B=$NI_SORTED("add","cd2","10") WRITE $NI_SORTED("toseq","cd2")',
     "10,9", "NimMExt", "nimm doc", "$NI_SORTED orders lexicographically"),
    ("NIDQ_ENDS",
     'SET X=$NI_DEQUE("create","ce1") SET A=$NI_DEQUE("addfirst","ce1","f") '
     'SET B=$NI_DEQUE("addlast","ce1","b") '
     'WRITE $NI_DEQUE("peekfirst","ce1"),"|",$NI_DEQUE("poplast","ce1"),"|",$NI_DEQUE("len","ce1")',
     "f|b|1", "NimMExt", "nimm doc", "$NI_DEQUE both ends"),
    ("NIBAG_COUNT",
     'SET X=$NI_BAG("create","cg1") SET A=$NI_BAG("add","cg1","x") '
     'SET B=$NI_BAG("add","cg1","x") SET C=$NI_BAG("add","cg1","y") '
     'WRITE $NI_BAG("count","cg1","x"),"|",$NI_BAG("len","cg1")',
     "2|3", "NimMExt", "nimm doc", "$NI_BAG counts occurrences"),
    ("NIJSON_ROUND",
     'SET J=$NI_JSON("parse","[1,2,3]") SET S=$NI_JSON("stringify",J) WRITE "<"_S_">"',
     "<[1,2,3]>", "NimMExt", "nimm doc", "$NI_JSON parse/stringify round-trip"),
    ("NIJSON_STR",
     'WRITE "<"_$NI_JSON("stringify","hello")_">"',
     '<"hello">', "NimMExt", "nimm doc", "$NI_JSON string quoting"),
    ("NIUUID_SHAPE",
     'SET U=$NI_UUID() WRITE $LENGTH(U),"|",$EXTRACT(U,9),$EXTRACT(U,14),$EXTRACT(U,19),$EXTRACT(U,24)',
     "36|----", "NimMExt", "nimm doc", "$NI_UUID v4 shape (36 chars, dashes)"),
    ("NICASE_MATCH",
     'WRITE $CASE("b","a":1,"b":2,"c":3)',
     "2", "NimMExt", "nimm doc", "$CASE selects matching branch"),
    ("NICASE_MISS",
     'WRITE "["_$CASE("z","a":1,"b":2)_"]"',
     "[]", "NimMExt", "nimm doc", "$CASE no match returns empty"),
]


def run_suite(engine, tests):
    results, timings = {}, {}
    for name, code, exp, cat, ref, desc in tests:
        t0 = time.monotonic()
        got = engine.run(code)
        dt = time.monotonic() - t0
        ok = got == exp
        results[name] = (got, exp, ok)
        timings[name] = dt
    return results, timings


def print_summary(results, engine, tests):
    passed = sum(1 for t in tests if results[t[0]][2])
    total = len(tests)
    print()
    print("=" * 60)
    print("Extended M Conformance Results")
    print("=" * 60)
    print()
    print(f"Implementation  Pass  Fail  Total     Rate")
    print("-" * 48)
    print(f"{engine.name:<15}{passed:>5}{total-passed:>6}{total:>6}"
          f"{100.0*passed/total:>8.1f}%")
    print()


def print_timing(timings, engine, tests):
    print("=" * 60)
    print("Per-Test Timing (avg over runs)")
    print("=" * 60)
    total = 0.0
    for name, *_ in tests:
        ts = timings.get(name, [])
        if ts:
            avg = sum(ts) / len(ts)
            total += avg
            print(f"{name:<20}{avg*1000:>10.2f}ms")
    print(f"{'TOTAL':<20}{total*1000:>10.2f}ms")


def print_failures(results, tests):
    fails = [(n, c, e) for n, c, e, *_ in tests if not results[n][2]]
    if not fails:
        print("\nAll tests pass.")
        return
    print("\nDetailed Failures:")
    for n, code, exp in fails:
        got = results[n][0]
        print(f"\n{n}")
        print(f"  Code:     {code}")
        print(f"  Expected: {exp!r}")
        print(f"  Got:      {got!r}")


def main():
    ap = argparse.ArgumentParser(description="Extended M conformance suite")
    ap.add_argument("--impls", required=True, choices=["nimm", "rsm", "rfc"])
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--timing", action="store_true")
    ap.add_argument("--failures", action="store_true")
    args = ap.parse_args()

    engine = make_engine(args.impls)
    if engine is None:
        print("Unknown implementation.")
        sys.exit(1)

    # NimMExt tests exercise NimM-specific extensions — only meaningful
    # (and only run) against NimM.
    cats = ("SSV", "Std99", "RSMExt")
    if args.impls == "nimm":
        cats += ("NimMExt",)
    tests = [t for t in TESTS if t[3] in cats]

    print("Verifying engine...")
    out = engine.run('WRITE "hello"')
    if "hello" not in out:
        print(f"  {engine.name}: FAIL ({out!r}) — is its daemon running?")
        sys.exit(1)
    print(f"  {engine.name}: OK")

    print(f"\nRunning {len(tests)} tests x {args.runs} run(s) "
          f"against {engine.name}...\n")

    all_timings = {}
    results = None
    for run in range(1, args.runs + 1):
        if args.runs > 1:
            print(f"-- Run {run}/{args.runs} --")
        rr, tt = run_suite(engine, tests)
        if results is None:
            results = rr
        for tn, dt in tt.items():
            all_timings.setdefault(tn, []).append(dt)

    print_summary(results, engine, tests)
    if args.timing or args.runs > 1:
        print_timing(all_timings, engine, tests)
    if args.failures:
        print_failures(results, tests)
    print()


if __name__ == "__main__":
    import time
    main()
