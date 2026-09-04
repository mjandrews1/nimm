#!/bin/bash
# fetch_pubmed_baseline.sh — resume-safe PubMed baseline backfill (#474).
#
# Fetches the full pubmed26nNNNN.xml.gz baseline (0001..~1334) into
# $DATA_DIR/pubmed-baseline/, skipping files already present or already logged
# in FETCHED.log, verifying each against NLM's .md5 before keeping it. Safe to
# kill and re-run: it resumes by diffing the directory + log against the
# listing.
#
# Endpoint is HTTPS (rsync:// is refused from this host). ~1235 files ≈ 19 GB.
#
# Usage: DATA_DIR=/home/mark/data ./deploy/fetch_pubmed_baseline.sh
set -euo pipefail

BASE_URL="https://ftp.ncbi.nlm.nih.gov/pubmed/baseline"
DATA_DIR="${DATA_DIR:-/home/mark/data}"
DEST="$DATA_DIR/pubmed-baseline"
LOG="$DEST/FETCHED.log"

mkdir -p "$DEST"
touch "$LOG"

log() { echo "[$(date "+%F %T")] $*"; }

log "listing baseline files from $BASE_URL/ ..."
listing="$(curl -fsSL "$BASE_URL/")"
# Sorted, de-duplicated, full file list (0001..1334), case-exact.
mapfile -t FILES < <(printf '%s\n' "$listing" \
  | grep -oE 'pubmed26n[0-9]+\.xml\.gz' | sort -u -V)

total="${#FILES[@]}"
done=0
skipped=0
failed=0
log "total baseline files: $total"

for f in "${FILES[@]}"; do
  # Skip if already present (existing) or already fetched (logged).
  if [[ -e "$DEST/$f" ]] || grep -qxF "$f" "$LOG"; then
    skipped=$((skipped+1))
    continue
  fi

  part="$DEST/$f.part"
  # curl -C - resumes a partial .part if one exists.
  if ! curl -fL -C - --retry 3 --retry-delay 2 \
       -o "$part" "$BASE_URL/$f"; then
    log "FAIL download $f (retrying on next run)"
    failed=$((failed+1))
    continue
  fi

  # Verify md5 against NLM's sidecar.
  expected="$(curl -fsSL "$BASE_URL/$f.md5" | sed -nE 's/^MD5\(.*\)=[[:space:]]*([0-9a-f]+).*/\1/p')"
  if [[ -z "$expected" ]]; then
    log "FAIL md5 fetch $f (no md5)"; failed=$((failed+1)); continue
  fi
  actual="$(md5sum "$part" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    log "FAIL md5 mismatch $f (expected $expected got $actual)"
    failed=$((failed+1))
    rm -f "$part"
    continue
  fi

  mv "$part" "$DEST/$f"
  echo "$f" >> "$LOG"
  done=$((done+1))
  if (( done % 20 == 0 )); then
    log "progress: $done downloaded, $skipped present, $failed failed (of $total)"
  fi
  sleep 1   # light rate-limit; NLM tolerates bulk HTTP but not hammering
done

log "DONE downloaded=$done skipped=$skipped failed=$failed total=$total"
