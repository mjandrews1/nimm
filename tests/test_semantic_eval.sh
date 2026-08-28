#!/bin/bash
# test_semantic_eval.sh — #367 semantic indexing evaluation (BM25 baseline)
# Loads MeSH descriptors, builds BM25, runs golden queries, reports
# P@5 / R@10 / MRR / nDCG@10 per class (exact vs vocab).
#
# SLOW one-time eval (~2-3 min); not part of the fast run_all.sh suite.
# Usage: ./tests/test_semantic_eval.sh [data_dir] [max_records]

set -euo pipefail

DATA_DIR="${1:-/Users/mark/_diary-data}"
MAX_RECORDS="${2:-10000}"   # 0 = all (31K, slow); 10000 covers all golden docs

DB=/tmp/semantic_eval.lmdb
NIMM=./bin/nimm
BM25="$NIMM -r future_search_tool/src/bm25idx.m -d $DB"
GOLDEN=tests/golden_queries.tsv
DESC="$DATA_DIR/mesh-staging/xml/desc2026.xml"

rm -rf "$DB" "$DB-lock"

echo "=== #367: Semantic indexing evaluation (BM25 baseline) ==="
echo "Data: $DESC"
echo "Max records: $MAX_RECORDS"
echo

# --- 1. Load MeSH descriptors (subset) via Python + SET batches ---
echo "--- Loading MeSH descriptors ---"
python3 - "$DESC" "$DB" "$MAX_RECORDS" "$NIMM" << 'PYEOF'
import sys, subprocess, xml.etree.ElementTree as ET

desc, db, maxn, nimm = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
tree = ET.parse(desc)
root = tree.getroot()

def esc(s):
    # double quotes -> "" and control chars -> space (scope notes have newlines)
    return (s.replace('"', '""')
             .replace('\n', ' ').replace('\r', ' ').replace('\t', ' '))

batch = []
count = 0

def flush():
    global batch
    if batch:
        code = 'VIEW "BATCHON" ' + ' '.join(batch) + ' VIEW "BATCHCOMMIT"'
        subprocess.run([nimm, '-d', db, '-x', code],
                       check=True, capture_output=True)
        batch.clear()

for rec in root.findall('.//DescriptorRecord'):
    ui = rec.findtext('DescriptorUI', '')
    name = rec.findtext('DescriptorName/String', '')
    scope = rec.findtext('.//ScopeNote', '')  # nested under ConceptList/Concept
    if not ui or not name:
        continue
    batch.append(f'SET ^MESH("{esc(ui)}","name")="{esc(name)}"')
    if scope:
        batch.append(f'SET ^MESH("{esc(ui)}","scopeNote")="{esc(scope[:500])}"')
    count += 1
    if len(batch) >= 1000:
        flush()
    if maxn > 0 and count >= maxn:
        break
flush()
print(f"  Loaded {count} descriptors")
PYEOF

# --- 2. Build BM25 index ---
echo "--- Building BM25 index ---"
$BM25 -e 'DO BUILDMESH^BM25IDX' 2>&1 | tail -1

# --- 3. Run golden queries, collect ranked doc ids ---
echo "--- Running golden queries ---"
: > /tmp/semantic_rankings.txt
while IFS=$'\t' read -r cls query ui name; do
  [ -z "$query" ] && continue
  ranked=$($BM25 -x "S ^TMP(\"BM25\",\"type\")=\"MESH\",^TMP(\"BM25\",\"terms\")=\"$query\" DO SEARCH^BM25IDX" 2>&1 \
           | head -50 | cut -f1 | paste -sd, -)
  printf '%s\t%s\n' "$query" "$ranked" >> /tmp/semantic_rankings.txt
done < <(grep -v '^#' "$GOLDEN")

# --- 4. Compute metrics ---
echo "--- Metrics ---"
python3 - "$GOLDEN" /tmp/semantic_rankings.txt << 'PYEOF'
import sys, math, collections

golden_path, rankings_path = sys.argv[1], sys.argv[2]

golden = []
for line in open(golden_path):
    line = line.rstrip('\n')
    if not line or line.startswith('#'):
        continue
    p = line.split('\t')
    if len(p) >= 3:
        golden.append((p[0], p[1], p[2]))

rankings = {}
for line in open(rankings_path):
    line = line.rstrip('\n')
    if '\t' in line:
        q, rest = line.split('\t', 1)
        rankings[q] = [x for x in rest.split(',') if x]

by_class = collections.defaultdict(list)
for cls, query, ui in golden:
    by_class[cls].append((query, ui))

K5, K10 = 5, 10
for cls in ['exact', 'vocab']:
    if cls not in by_class:
        continue
    p5 = r10 = mrr = ndcg = 0.0
    n = 0
    detail = []
    for query, ui in by_class[cls]:
        ranked = rankings.get(query, [])
        n += 1
        rank = 0
        for i, d in enumerate(ranked):
            if d == ui:
                rank = i + 1
                break
        if 0 < rank <= K5:
            p5 += 1.0 / K5
        if 0 < rank <= K10:
            r10 += 1.0
        if rank > 0:
            mrr += 1.0 / rank
        if 0 < rank <= K10:
            ndcg += (1.0 / math.log2(rank + 1)) / 1.0  # IDCG = 1 (single relevant)
        detail.append(f"    {query:24s} -> rank {rank if rank else '-'}")
    print(f"  {cls}: n={n}  P@5={p5/n:.3f}  R@10={r10/n:.3f}  MRR={mrr/n:.3f}  nDCG@10={ndcg/n:.3f}")
    for d in detail:
        print(d)
PYEOF

echo
echo "=== Done ==="
rm -rf "$DB" "$DB-lock"
