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

    print("Verifying engine...")
    out = engine.run('WRITE "hello"')
    if "hello" not in out:
        print(f"  {engine.name}: FAIL ({out!r}) — is its daemon running?")
        sys.exit(1)
    print(f"  {engine.name}: OK")

    print(f"\nRunning {len(TESTS)} tests x {args.runs} run(s) "
          f"against {engine.name}...\n")

    all_timings = {}
    results = None
    for run in range(1, args.runs + 1):
        if args.runs > 1:
            print(f"-- Run {run}/{args.runs} --")
        rr, tt = run_suite(engine, TESTS)
        if results is None:
            results = rr
        for tn, dt in tt.items():
            all_timings.setdefault(tn, []).append(dt)

    print_summary(results, engine, TESTS)
    if args.timing or args.runs > 1:
        print_timing(all_timings, engine, TESTS)
    if args.failures:
        print_failures(results, TESTS)
    print()


if __name__ == "__main__":
    import time
    main()
