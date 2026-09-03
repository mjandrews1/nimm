#!/bin/bash
# rebuild_fst_full.sh — full FST rebuild from scratch: ZLOADXML loaders
# (mesh/qualifier/catline/serline/pubmed) + Nim BM25 index build.
#
# Canonical FST pipeline (see #454). Defaults target the Utility-01 layout;
# override with env vars for a different host:
#   NIMM_DIR  repo checkout dir (default: /home/mark/nimm)
#   DB        LMDB database path (default: /home/mark/fst.lmdb)
#   DATA_DIR  staging data dir  (default: /home/mark/data)
#
# Usage: ./rebuild_fst_full.sh
set -euo pipefail

NIMM_DIR="${NIMM_DIR:-/home/mark/nimm}"
DB="${DB:-/home/mark/fst.lmdb}"
DATA_DIR="${DATA_DIR:-/home/mark/data}"
LOG="${LOG:-/home/mark/fst_rebuild.log}"

cd "$NIMM_DIR"
NIMM=./bin/nimm
BUILD_BM25=./bin/build_bm25

log() { echo "[$(date "+%F %T")] $*" >> "$LOG"; }

log "=== FULL FST REBUILD START ==="

# 1. MeSH descriptors + qualifiers
log "load MeSH descriptors (desc2026.xml -> ^MESH)"
"$NIMM" -d "$DB" -x "ZLOADXML \"$DATA_DIR/mesh-staging/xml/desc2026.xml\",\"^MESH\",\"mesh\"" >> "$LOG" 2>&1
log "load MeSH qualifiers (qual2026.xml -> ^QUAL)"
"$NIMM" -d "$DB" -x "ZLOADXML \"$DATA_DIR/mesh-staging/xml/qual2026.xml\",\"^QUAL\",\"qualifier\"" >> "$LOG" 2>&1

# 1b. MeSH Supplementary Concept Records (supp2026 -> ^SUPP, MESH->SUPP links)
log "load MeSH Supplementary Concept Records (supp2026 -> ^SUPP)"
"$NIMM" -d "$DB" -x "ZLOADXML \"$DATA_DIR/mesh-staging/xml/supp2026\",\"^SUPP\",\"scr\"" >> "$LOG" 2>&1

# 2. CatLine (all catplus files)
log "load CatLine"
for f in "$DATA_DIR"/nlm-staging/catplus-marcxml/catplus*.marcxml.xml; do
  [ -f "$f" ] || continue
  log "  $(basename "$f")"
  "$NIMM" -d "$DB" -x "ZLOADXML \"$f\",\"^CATLINE\",\"catline\"" >> "$LOG" 2>&1
done

# 2b. SerLine (serfile)
log "load SerLine"
for f in "$DATA_DIR"/nlm-staging/serfile-marcxml/serfile*.marcxml.xml; do
  [ -f "$f" ] || continue
  log "  $(basename "$f")"
  "$NIMM" -d "$DB" -x "ZLOADXML \"$f\",\"^SERLINE\",\"catline\"" >> "$LOG" 2>&1
done

# 3. PubMed (baseline files)
log "load PubMed"
n=0
for f in "$DATA_DIR"/pubmed-baseline/*.xml.gz; do
  [ -f "$f" ] || continue
  n=$((n+1))
  [ $((n % 10)) -eq 0 ] && log "  [$n] ..."
  "$NIMM" -d "$DB" -x "ZLOADXML \"$f\",\"^PUBMED\",\"pubmed\"" >> "$LOG" 2>&1
done
log "  done PubMed ($n files)"

# 3b. PUBMED→REPORTER funding links (ExPORTER publications link tables)
log "build PUBMED->REPORTER funding links"
BUILD_REPORTER=./bin/build_reporter_link
"$BUILD_REPORTER" "$DB" "$DATA_DIR/reporter-staging/linktables" >> "$LOG" 2>&1

# 3c. FDA Orange Book (products/patents/exclusivity -> ^ORANGEBOOK + SCR links)
log "load Orange Book"
BUILD_OB=./bin/build_orangebook
"$BUILD_OB" "$DB" "$DATA_DIR/orangebook-staging" >> "$LOG" 2>&1

# 4. BM25 index build (Nim buildIndex; batched flush, #457)
log "build BM25 MESH"
"$BUILD_BM25" "$DB" MESH "^MESH" "name^scopeNote" >> "$LOG" 2>&1
log "build BM25 CATLINE"
"$BUILD_BM25" "$DB" CATLINE "^CATLINE" "title" >> "$LOG" 2>&1
log "build BM25 SERLINE"
"$BUILD_BM25" "$DB" SERLINE "^SERLINE" "title" >> "$LOG" 2>&1
log "build BM25 PUBMED"
"$BUILD_BM25" "$DB" PUBMED "^PUBMED" "title^abstract^journal" >> "$LOG" 2>&1

# 5. Consistency audit (read-only; framing/round-trip/ordering + LINK/df probes, #464)
log "run db_audit"
DB_AUDIT=./bin/db_audit
"$DB_AUDIT" "$DB" 2000 500 -1 10000000 >> "$LOG" 2>&1 || log "  db_audit reported violations (see log)"

# 6. Summary
log "=== FULL FST REBUILD DONE ==="
log "--- index summary ---"
"$NIMM" -d "$DB" -x "W ^BM25META(\"MESH\",\"N\"),\" mesh / \",^BM25META(\"CATLINE\",\"N\"),\" catline / \",^BM25META(\"SERLINE\",\"N\"),\" serline / \",^BM25META(\"PUBMED\",\"N\"),\" pubmed\"" >> "$LOG" 2>&1
log "--- supplementary concept records ---"
"$NIMM" -d "$DB" -x "W \" supp records: \",$G(^FST(\"load\",\"supp2026\"))" >> "$LOG" 2>&1
