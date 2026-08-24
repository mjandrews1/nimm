#!/usr/bin/env python3
"""
FST BM25 Search Engine — Search NLM data loaded in NimM's LMDB.
Uses BM25 ranking for relevance scoring.

Usage:
  python3 fst_search.py --db /path/to/fst.lmdb --query "search terms"
"""

import argparse
import math
import os
import subprocess
import sys
from collections import Counter


def run_mcode(db, code):
    """Execute M code via nimm -x and return output."""
    result = subprocess.run(
        ["./nimm", "-d", db, "-x", code],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()


def get_all_globals(db, global_name):
    """Get all values for a global.
    Workaround: NimM's $ORDER skips first key with LMDB (#355).
    Uses direct key access with known keys from index file."""
    import json
    index_file = db + ".index.json"
    if os.path.exists(index_file):
        with open(index_file) as f:
            index = json.load(f)
        return index.get(global_name, {})
    # Fallback: try $ORDER (will miss first key)
    values = {}
    code = f'S g="" F  S g=$O(^{global_name}(g)) Q:g=""  W g,"|",^{global_name}(g,"name"),"!"'
    output = run_mcode(db, code)
    for line in output.split("!"):
        if "|" in line:
            key, value = line.split("|", 1)
            values[key] = value
    return values


def get_descriptors_by_tree(db, tree_prefix):
    """Get descriptors matching a tree number prefix."""
    descriptors = []
    code = f'S d="" F  S d=$O(^MESH(d)) Q:d=""  S t="" F  S t=$O(^MESH(d,"treeNumber",t)) Q:t=""  I $E(t,1,$L("{tree_prefix}"))="{tree_prefix}"  W d,"|",^MESH(d,"name"),"!",! Q'
    output = run_mcode(db, code)
    for line in output.split("!"):
        if "|" in line:
            key, value = line.split("|", 1)
            descriptors.append((key, value))
    return descriptors


def search_descriptors(db, query, max_results=20):
    """Search MeSH descriptors using BM25 scoring."""
    query_terms = query.lower().split()
    descriptors = get_all_globals(db, "MESH")
    
    # Calculate BM25 scores
    scores = []
    avg_dl = sum(len(v.split()) for v in descriptors.values()) / max(len(descriptors), 1)
    k1 = 1.5
    b = 0.75
    
    for desc_ui, name in descriptors.items():
        doc_terms = name.lower().split()
        dl = len(doc_terms)
        doc_term_counts = Counter(doc_terms)
        
        score = 0.0
        for term in query_terms:
            if term in doc_term_counts:
                tf = doc_term_counts[term]
                df = sum(1 for v in descriptors.values() if term in v.lower())
                idf = math.log((len(descriptors) - df + 0.5) / (df + 0.5) + 1)
                tf_norm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avg_dl))
                score += idf * tf_norm
        
        if score > 0:
            scores.append((desc_ui, name, score))
    
    # Sort by score descending
    scores.sort(key=lambda x: x[2], reverse=True)
    return scores[:max_results]


def get_descriptor_details(db, desc_ui):
    """Get full details for a descriptor."""
    details = {}
    
    # Get name
    name = run_mcode(db, f'W ^MESH("{desc_ui}","name")')
    details["name"] = name
    
    # Get scope note
    scope = run_mcode(db, f'W ^MESH("{desc_ui}","scopeNote")')
    if scope:
        details["scopeNote"] = scope
    
    # Get tree numbers
    trees = []
    code = f'S t="" F  S t=$O(^MESH("{desc_ui}","treeNumber",t)) Q:t=""  W t,"!"'
    output = run_mcode(db, code)
    for line in output.split("!"):
        if line.strip():
            trees.append(line.strip())
    details["treeNumbers"] = trees
    
    # Get qualifiers
    quals = []
    code = f'S q="" F  S q=$O(^MESH("{desc_ui}","qualifier",q)) Q:q=""  W q,"|",^QUAL(q,"name"),"!"'
    output = run_mcode(db, code)
    for line in output.split("!"):
        if "|" in line:
            q_ui, q_name = line.split("|", 1)
            quals.append({"ui": q_ui, "name": q_name})
    details["qualifiers"] = quals
    
    return details


def main():
    parser = argparse.ArgumentParser(description="FST BM25 Search Engine")
    parser.add_argument("--db", required=True, help="LMDB database path")
    parser.add_argument("--query", required=True, help="Search query")
    parser.add_argument("--max-results", type=int, default=20, help="Max results")
    parser.add_argument("--details", help="Get details for descriptor UI")
    args = parser.parse_args()

    if args.details:
        details = get_descriptor_details(args.db, args.details)
        print(f"Descriptor: {args.details}")
        print(f"Name: {details['name']}")
        if details.get('scopeNote'):
            print(f"Scope: {details['scopeNote'][:200]}...")
        if details.get('treeNumbers'):
            print(f"Trees: {', '.join(details['treeNumbers'][:5])}")
        if details.get('qualifiers'):
            print(f"Qualifiers: {', '.join(q['name'] for q in details['qualifiers'][:5])}")
    else:
        results = search_descriptors(args.db, args.query, args.max_results)
        print(f"Search: {args.query}")
        print(f"Results: {len(results)}")
        print()
        for i, (desc_ui, name, score) in enumerate(results, 1):
            print(f"{i:2d}. [{desc_ui}] {name} (score: {score:.3f})")


if __name__ == "__main__":
    main()
