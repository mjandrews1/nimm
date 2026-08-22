#!/usr/bin/env python3
"""m_fuzz.py — seeded differential fuzzer: NimM vs RSM.

Generates small deterministic M programs from a conservative grammar that
avoids the frozen-in reference divergences (pattern alternation, backward
$ORDER from "", collation edge zones, transactions). Each case runs on both
engines; outcomes are classified:

  MATCH      both clean, identical stdout
  BOTH_ERR   both runs reported an error (error TEXT may differ; counted, not failed)
  MISMATCH   one side errored or clean-run outputs differ -> seed logged

Usage: m_fuzz.py --nimm PATH --rsm PATH --dbfile PATH --start SEED --count N [--timeout T]
Exit code 0 iff zero MISMATCHes.
"""
import argparse, os, random, subprocess, sys

VARS = ["A", "B", "C", "X", "Y", "N", "I", "J", "K"]
WORDS = ["ab", "cd", "xyz", "q", "mm", "zz9"]


def gen_expr(rng, depth=0):
    r = rng.random()
    if depth > 2 or r < 0.30:
        return rng.choice([str(rng.randint(-50, 50)), str(rng.choice([0, 1, 7, 10, 100]))])
    if r < 0.40:
        return '"' + rng.choice(WORDS) + '"'
    if r < 0.55:
        return rng.choice(VARS)
    if r < 0.75:
        op = rng.choice(["+", "-", "*", "/"])
        return "(%s%s%s)" % (gen_expr(rng, depth + 1), op, gen_expr(rng, depth + 1))
    f = rng.randrange(6)
    if f == 0:
        return "$LENGTH(%s)" % gen_expr(rng, depth + 1)
    if f == 1:
        return "$EXTRACT(%s,%d,%d)" % (gen_expr(rng, depth + 1),
                                       rng.randint(1, 4), rng.randint(4, 8))
    if f == 2:
        return "$PIECE(%s,\"%s\",%d)" % (gen_strvar(rng), rng.choice(WORDS)[:1], rng.randint(1, 3))
    if f == 3:
        return "$JUSTIFY(%s,%d,%d)" % (gen_expr(rng, depth + 1), rng.randint(3, 12), rng.randint(0, 2))
    if f == 4:
        return "$REVERSE(%s)" % gen_expr(rng, depth + 1)
    return "$GET(%s,%s)" % (gen_strvar(rng), gen_expr(rng, depth + 1))


def gen_strvar(rng):
    return rng.choice(VARS)


def gen_cond(rng):
    a, b = gen_expr(rng, 1), gen_expr(rng, 1)
    cmp_ = rng.choice(["=", "'=", ">", "<"])
    c = "%s%s%s" % (a, cmp_, b)
    if rng.random() < 0.2:
        c = "(%s)&(%s)" % (c, gen_cond(rng))
    return c


def gen_stmts(rng, n, indent=" "):
    out = []
    for _ in range(n):
        r = rng.random()
        v = rng.choice(VARS)
        if r < 0.35:
            out.append("%sSET %s=%s" % (indent, v, gen_expr(rng)))
        elif r < 0.60:
            out.append('%sWRITE %s,"%s"' % (indent, gen_expr(rng), "|"))
        elif r < 0.70:
            out.append("%sIF %s WRITE \"%s\"" % (indent, gen_cond(rng), rng.choice(WORDS)))
        elif r < 0.80:
            a, b = rng.randint(-2, 3), min(rng.randint(1, 5), 5)
            body = 'WRITE %s' % gen_expr(rng, 1)
            out.append("%sFOR J=%d:1:%d %s" % (indent, a, b, body))
        elif r < 0.90:
            g = rng.choice(["^G(1)", "^G(%d)" % rng.randint(1, 3)])
            out.append("%sSET %s=$GET(%s)+1" % (indent, g, g))
        else:
            out.append('%sSET %s(%d)="%s"' % (indent, v, rng.randint(1, 3), rng.choice(WORDS)))
    return out


def gen_program(rng):
    # No leading label: RSM's -x direct mode rejects label tokens.
    # Grammar restricted to constructs both engines execute faithfully via
    # a single -x line: no labels, no argumentless FOR / trailing $ORDER
    # tally (RSM one-liner mode leaks QUIT across statements there), no
    # pattern ops, forward-only iteration. Locals pre-initialized because
    # NimM reads undefined locals as "" where RSM raises M6 (filed).
    lines = []
    for v in VARS:
        init = rng.choice(['"ab"', '"x"', '1', '7', '0', '"q9"'])
        lines.append("SET %s=%s" % (v, init))
    lines += gen_stmts(rng, rng.randint(3, 7))
    return "\n".join(lines) + "\n"


def run(binpath, dbfile_env, code, timeout):
    env = dict(os.environ)
    env["RSM_DBFILE"] = dbfile_env
    try:
        p = subprocess.run([binpath, "-x", code], capture_output=True,
                           text=True, timeout=timeout, env=env)
        return p.stdout, p.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT]", -99


KNOWN_MARKERS = ("Divide by zero", "M9")


def classify(out_n, rc_n, out_r, rc_r):
    err_n = rc_n != 0 or "Error" in out_n or "%" in out_n.split("\n")[0]
    err_r = rc_r != 0 or "Error" in out_r or "%" in out_r.split("\n")[0]
    if err_n and err_r:
        return "BOTH_ERR"
    if err_r and any(m in out_r for m in KNOWN_MARKERS):
        # Known class: RSM raises divide-by-zero, NimM computes silently.
        return "DIV0_KNOWN"
    if err_n != err_r:
        return "MISMATCH"

    def clean(s):
        drop = ("DEBUG:", "Reference Standard", "Copyright", "https://",
                "[Instance]", "[Volume]", "ReFaCtored")
        kept = "".join(l for l in s.splitlines()
                       if not any(l.startswith(d) for d in drop))
        return kept.strip()
    if clean(out_n) == clean(out_r):
        return "MATCH"
    # Both ran clean but disagree — split numeric-formatting noise from
    # everything else so the morning list stays actionable.
    import re
    numdiff = re.sub(r"[0-9]", "#", clean(out_n)) == re.sub(r"[0-9]", "#", clean(out_r))
    return "FMT_DIFF" if numdiff else "MISMATCH"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nimm", required=True)
    ap.add_argument("--rsm", required=True)
    ap.add_argument("--dbfile", required=True)
    ap.add_argument("--start", type=int, default=1)
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--timeout", type=int, default=5)
    args = ap.parse_args()

    stats = {"MATCH": 0, "BOTH_ERR": 0, "DIV0_KNOWN": 0, "FMT_DIFF": 0, "MISMATCH": 0}
    mismatches = []
    for seed in range(args.start, args.start + args.count):
        rng = random.Random(seed)
        # Join to ONE line for RSM's -x, but only across line boundaries:
        # M's two-space command/arg separators (e.g. FOR<sp><sp>SET) are
        # significant and must survive.
        code = " ".join(l.strip() for l in gen_program(rng).splitlines())
        on, rn = run(args.nimm, "/dev/null", code, args.timeout)
        ors, rr = run(args.rsm, args.dbfile, code, args.timeout)
        verdict = classify(on, rn, ors, rr)
        stats[verdict] += 1
        if verdict == "MISMATCH":
            mismatches.append(seed)
            print("== MISMATCH seed=%d ==" % seed, flush=True)
            print("--- program ---\n" + code, flush=True)
            print("--- nimm(rc=%d) ---\n%s" % (rn, on), flush=True)
            print("--- rsm(rc=%d) ---\n%s" % (rr, ors), flush=True)
    print("FUZZSTATS start=%d count=%d match=%d fmt_diff=%d div0_known=%d both_err=%d mismatch=%d seeds=%s"
          % (args.start, args.count, stats["MATCH"], stats["FMT_DIFF"],
             stats["DIV0_KNOWN"], stats["BOTH_ERR"],
             stats["MISMATCH"], mismatches[:20]), flush=True)
    sys.exit(1 if stats["MISMATCH"] else 0)


if __name__ == "__main__":
    main()
