#!/usr/bin/env python3
# dense_retrieval_eval.py — #391 option B: dense (bi-encoder) retrieval evaluation
# Embeds MeSH descriptors + golden vocab queries with a local CPU bi-encoder,
# ranks by cosine similarity, and reports per-query rank + vocab metrics.
#
# Usage: dense_retrieval_eval.py [data_dir] [max_records] [model]
# Requires: fastembed (run in the Python 3.12 venv, e.g. /tmp/fst_venv312)

import sys
import xml.etree.ElementTree as ET

DATA_DIR = sys.argv[1] if len(sys.argv) > 1 else "/Users/mark/_diary-data"
MAX_RECORDS = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
MODEL = sys.argv[3] if len(sys.argv) > 3 else "BAAI/bge-small-en-v1.5"

import numpy as np
from fastembed import TextEmbedding

GOLDEN = "tests/golden_queries.tsv"
DESC = f"{DATA_DIR}/mesh-staging/xml/desc2026.xml"

print(f"=== dense retrieval eval ({MODEL}) ===", flush=True)

# --- parse descriptors ---
print("parsing descriptors...", flush=True)
root = ET.parse(DESC).getroot()
docs = []  # (ui, text)
for rec in root.findall(".//DescriptorRecord"):
    ui = rec.findtext("DescriptorUI", "")
    name = rec.findtext("DescriptorName/String", "")
    scope = rec.findtext(".//ScopeNote", "")
    if not ui or not name:
        continue
    text = name
    if scope:
        text += " " + scope[:120]
    docs.append((ui, text))
    if MAX_RECORDS > 0 and len(docs) >= MAX_RECORDS:
        break

print(f"loaded {len(docs)} docs; embedding...", flush=True)
model = TextEmbedding(model_name=MODEL)
doc_embs = np.array(list(model.embed([d[1] for d in docs], batch_size=256)), dtype="float32")
doc_embs /= np.linalg.norm(doc_embs, axis=1, keepdims=True)

# --- golden vocab queries ---
vocab = []
for line in open(GOLDEN):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    p = line.split("\t")
    if len(p) >= 3 and p[0] == "vocab":
        vocab.append((p[1], p[2]))  # (query, expected_ui)

print(f"embedding {len(vocab)} queries...", flush=True)
q_embs = np.array(list(model.embed([q for q, _ in vocab], batch_size=64)), dtype="float32")
q_embs /= np.linalg.norm(q_embs, axis=1, keepdims=True)

sims = q_embs @ doc_embs.T  # (nq, ndoc) cosine similarities

# --- rank + metrics ---
K5, K10 = 5, 10
p5 = r10 = mrr = ndcg = 0.0
n = 0
print()
for qi, (query, expected_ui) in enumerate(vocab):
    n += 1
    order = np.argsort(-sims[qi])
    rank = 0
    for r, di in enumerate(order):
        if docs[di][0] == expected_ui:
            rank = r + 1
            break
    if 0 < rank <= K5:
        p5 += 1.0 / K5
    if 0 < rank <= K10:
        r10 += 1.0
    if rank > 0:
        mrr += 1.0 / rank
    if 0 < rank <= K10:
        ndcg += (1.0 / np.log2(rank + 1)) / 1.0
    top = [docs[di][0] for di in order[:3]]
    print(f"  {query:28s} -> rank {rank if rank else '-'}  (top3: {top})", flush=True)

print()
print(f"vocab: n={n}  P@5={p5/n:.3f}  R@10={r10/n:.3f}  MRR={mrr/n:.3f}  nDCG@10={ndcg/n:.3f}")
