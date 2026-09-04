#!/bin/bash
# deploy/refresh.sh — refresh stale FST sources (#470).
#
# Reads deploy/sources.tsv (source | cadence), checks each source's last-updated
# epoch marker ^FST("meta",source,"updated"), and runs the loader for every
# source that is stale for its cadence. Idempotent: loaders are safe to re-run;
# each loader writes the marker via markUpdated() on completion.
#
# Usage:
#   ./deploy/refresh.sh            # refresh only the sources that are due
#   ./deploy/refresh.sh --force    # refresh every source regardless of age
#   ./deploy/refresh.sh --list     # print each source + age, take no action
#
# Env (defaults match the Utility-01 layout, overridable like rebuild_fst_full.sh):
#   NIMM_DIR  repo checkout (default /home/mark/nimm)
#   DB        LMDB database path (default /home/mark/fst.lmdb)
#   DATA_DIR  staging data dir  (default /home/mark/data)
set -euo pipefail

NIMM_DIR="${NIMM_DIR:-/home/mark/nimm}"
DB="${DB:-/home/mark/fst.lmdb}"
DATA_DIR="${DATA_DIR:-/home/mark/data}"
MANIFEST="$NIMM_DIR/deploy/sources.tsv"

cd "$NIMM_DIR"
NIMM=./bin/nimm

FORCE=0
LIST=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --list)  LIST=1 ;;
  esac
done

# cadence -> age seconds (week=7d, month=30d, quarter=91d, year=365d)
age_of() {
  case "$1" in
    weekly)    echo $((7 * 86400))   ;;
    monthly)   echo $((30 * 86400))  ;;
    quarterly) echo $((91 * 86400))  ;;
    annual)    echo $((365 * 86400)) ;;
    *)         echo 0 ;;
  esac
}

nimm() { "$NIMM" -d "$DB" -x "$1"; }

# The loader dispatch — mirrors rebuild_fst_full.sh so one mechanism, not two.
run_source() {
  local src="$1"
  case "$src" in
    ^MESH)       nimm "ZLOADXML \"$DATA_DIR/mesh-staging/xml/desc2026.xml\",\"^MESH\",\"mesh\"" ;;
    ^QUAL)       nimm "ZLOADXML \"$DATA_DIR/mesh-staging/xml/qual2026.xml\",\"^QUAL\",\"qualifier\"" ;;
    ^SUPP)       nimm "ZLOADXML \"$DATA_DIR/mesh-staging/xml/supp2026\",\"^SUPP\",\"scr\"" ;;
    ^CATLINE)    for f in "$DATA_DIR"/nlm-staging/catplus-marcxml/catplus*.marcxml.xml; do
                   [ -f "$f" ] || continue; nimm "ZLOADXML \"$f\",\"^CATLINE\",\"catline\""
                 done ;;
    ^SERLINE)    for f in "$DATA_DIR"/nlm-staging/serfile-marcxml/serfile*.marcxml.xml; do
                   [ -f "$f" ] || continue; nimm "ZLOADXML \"$f\",\"^SERLINE\",\"catline\""
                 done ;;
    ^PUBMED)     for f in "$DATA_DIR"/pubmed-baseline/*.xml.gz; do
                   [ -f "$f" ] || continue; nimm "ZLOADXML \"$f\",\"^PUBMED\",\"pubmed\""
                 done ;;
    reporter)    ./bin/build_reporter_link "$DB" "$DATA_DIR/reporter-staging/linktables" ;;
    orangebook)  ./bin/build_orangebook "$DB" "$DATA_DIR/orangebook-staging" ;;
    clinicaltrials) ./bin/build_clinicaltrials "$DB" "$DATA_DIR/clinicaltrials-full/clinicaltrials_full.json" ;;
    medicare)    ./bin/build_medicare "$DB" "$DATA_DIR/medicare-staging/providers.json" ;;
    cdc)         ./bin/build_cdc "$DB" "$DATA_DIR/cdc-staging" ;;
    faers)       ./bin/build_faers "$DB" "$DATA_DIR/faers-staging" ;;
    biorxiv)     ./bin/build_biorxiv "$DB" medrxiv 2013-01-01 2026-01-01 ;;
    *) echo "refresh: unknown source '$src'" >&2 ;;
  esac
}

now=$(date +%s)
while IFS=$'\t' read -r src cadence; do
  case "$src" in ''|'#'*) continue ;; esac
  updated=$(nimm "W \$G(^FST(\"meta\",\"$src\",\"updated\"))" | tail -1)
  updated=${updated:-0}
  age=$(( now - ${updated:-0} ))
  limit=$(age_of "$cadence")
  if [ "$LIST" = 1 ]; then
    printf '%-14s %-10s age=%ss limit=%ss%s\n' "$src" "$cadence" "$age" "$limit" \
      "$([ "$FORCE" = 1 ] || [ "$age" -ge "$limit" ] && echo '  DUE' || true)"
    continue
  fi
  if [ "$FORCE" = 1 ] || [ "$age" -ge "$limit" ]; then
    echo "[$(date "+%F %T")] refresh $src (cadence=$cadence, age=${age}s)"
    run_source "$src"
  fi
done < "$MANIFEST"
