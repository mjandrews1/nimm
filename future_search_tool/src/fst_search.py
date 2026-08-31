#!/usr/bin/env python3
"""
FST Search Engine — search NLM data via NimM's BM25 + entry-term expansion.

Delegates to bm25idx.m (DICT for entry-term lookup, SEARCH for BM25 ranking)
by shelling out to the nimm binary, then merges the two rankings.

Usage:
  python3 fst_search.py --db /path/to/fst.lmdb --query "heart attack"
  python3 fst_search.py --db /path/to/fst.lmdb --details D009203
"""

import argparse
import os
import subprocess

NIMM = os.environ.get("NIMM_BIN", "./bin/nimm")
BM25IDX = "future_search_tool/src/bm25idx.m"


def _escape(s):
    return s.replace('"', '""')


def run_mcode(db, code):
    """Execute M code via nimm -x and return stdout."""
    result = subprocess.run(
        [NIMM, "-d", db, "-x", code],
        capture_output=True, text=True, timeout=60
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def run_routine(db, code):
    """Execute M code with bm25idx.m loaded (-r)."""
    result = subprocess.run(
        [NIMM, "-r", BM25IDX, "-d", db, "-x", code],
        capture_output=True, text=True, timeout=60
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def batch_names(db, uis):
    """Look up ^MESH(ui,\"name\") for a list of UIs in a single M call."""
    if not uis:
        return {}
    joined = "^".join(uis)
    code = (f'S list="{joined}" '
            f'F I=1:1:$L(list,"^") S ui=$P(list,"^",I) '
            f'W ui,$C(9),$G(^MESH(ui,"name")),!')
    out = run_mcode(db, code)
    names = {}
    for line in out.splitlines():
        if "\t" in line:
            ui, name = line.split("\t", 1)
            names[ui.strip()] = name.strip()
    return names


def search_descriptors(db, query, max_results=20):
    """Search MeSH descriptors: entry-term dictionary first, then BM25."""
    q = _escape(query)

    # 1. entry-term dictionary lookup (exact name matches, then synonyms)
    dict_out = run_routine(db, f'S ^TMP("BM25","terms")="{q}" DO DICT^BM25IDX')
    dict_ids = [l.strip() for l in dict_out.splitlines() if l.strip()]

    # 2. BM25 search via $NI_SEARCH (Nim global_bm25 over the ^BM25* globals)
    search_out = run_mcode(db, f'W $NI_SEARCH("MESH","{q}",{max_results})')
    bm25_scores = {}
    bm25_order = []
    for line in search_out.splitlines():
        if "\t" in line:
            ui, score = line.split("\t", 1)
            ui = ui.strip()
            bm25_order.append(ui)
            try:
                bm25_scores[ui] = float(score.strip())
            except ValueError:
                bm25_scores[ui] = 0.0

    # 3. combine: dict hits first, then BM25 fill (dedup)
    combined = []
    seen = set()
    for ui in dict_ids:
        if ui not in seen:
            seen.add(ui)
            combined.append(ui)
    for ui in bm25_order:
        if ui not in seen:
            seen.add(ui)
            combined.append(ui)
    combined = combined[:max_results]

    # 4. names in one batch call
    names = batch_names(db, combined)

    results = []
    for ui in combined:
        results.append((ui, names.get(ui, ""), bm25_scores.get(ui, 0.0)))
    return results


def get_descriptor_details(db, desc_ui):
    """Get full details for a descriptor."""
    ui = _escape(desc_ui)
    details = {}

    details["name"] = run_mcode(db, f'W ^MESH("{ui}","name")').strip()

    scope = run_mcode(db, f'W ^MESH("{ui}","scopeNote")').strip()
    if scope:
        details["scopeNote"] = scope

    out = run_mcode(db, f'S t="" F  S t=$O(^MESH("{ui}","treeNumber",t)) Q:t=""  W t,"!"')
    details["treeNumbers"] = [l for l in out.split("!") if l.strip()]

    quals = []
    out = run_mcode(db, f'S q="" F  S q=$O(^MESH("{ui}","qualifier",q)) Q:q=""  W q,"|",$G(^QUAL(q,"name")),"!"')
    for line in out.split("!"):
        if "|" in line:
            q_ui, q_name = line.split("|", 1)
            quals.append({"ui": q_ui.strip(), "name": q_name.strip()})
    details["qualifiers"] = quals

    return details


def get_all_globals(db, global_name):
    """All values for a global (ui -> name), via $ORDER."""
    g = _escape(global_name)
    values = {}
    code = (f'S g="" F  S g=$O(^{g}(g)) Q:g=""  '
            f'W g,"|",$G(^{g}(g,"name")),"!"')
    out = run_mcode(db, code)
    for line in out.split("!"):
        if "|" in line:
            key, value = line.split("|", 1)
            values[key.strip()] = value.strip()
    return values


def main():
    parser = argparse.ArgumentParser(description="FST Search Engine")
    parser.add_argument("--db", required=True, help="LMDB database path")
    parser.add_argument("--query", help="Search query")
    parser.add_argument("--max-results", type=int, default=20, help="Max results")
    parser.add_argument("--details", help="Get details for descriptor UI")
    args = parser.parse_args()

    if args.details:
        details = get_descriptor_details(args.db, args.details)
        print(f"Descriptor: {args.details}")
        print(f"Name: {details.get('name', '')}")
        if details.get("scopeNote"):
            print(f"Scope: {details['scopeNote'][:200]}...")
        if details.get("treeNumbers"):
            print(f"Trees: {', '.join(details['treeNumbers'][:5])}")
        if details.get("qualifiers"):
            print(f"Qualifiers: {', '.join(q['name'] for q in details['qualifiers'][:5])}")
    else:
        results = search_descriptors(args.db, args.query or "", args.max_results)
        print(f"Search: {args.query}")
        print(f"Results: {len(results)}")
        print()
        for i, (desc_ui, name, score) in enumerate(results, 1):
            print(f"{i:2d}. [{desc_ui}] {name} (score: {score:.3f})")


if __name__ == "__main__":
    main()
