#!/bin/bash
# formal/check_contracts.sh — enforce the Dafny-model ↔ Nim-mirror mapping at
# the *lemma* level (formal/contracts.tsv is the authoritative manifest).
#
#   1. Every `lemma` declared in formal/*.dfy is listed in contracts.tsv.
#   2. Every contracts.tsv entry names a real model + lemma (no stale rows).
#   3. Every mirror path (kind != support) exists.
#   4. Every model is also mentioned in the human-readable CONTRACTS.md.
#
# Exit 0 iff all hold. Run by `make formal` (and thus `make verify`).
set -euo pipefail
cd "$(dirname "$0")/.."

TSV="formal/contracts.tsv"
CONTRACTS="formal/CONTRACTS.md"
fail=0

# --- 1. lemma names actually declared in the models -------------------------
# A declaration is a line beginning with optional whitespace + "lemma".
# Grab the identifier immediately before the parameter list (handles
# `lemma {:axiom} Name(...)` too).
extract_lemmas() {
    sed -nE 's/^[[:space:]]*lemma[[:space:]]*(\{[^}]*\}[[:space:]]*)?([A-Za-z0-9_]+).*/\2/p' "$1"
}

tmp_decl="$(mktemp)"
for model in formal/*.dfy; do
    base="$(basename "$model")"
    while IFS= read -r name; do
        echo "$base|$name"
    done < <(extract_lemmas "$model")
done | sort > "$tmp_decl"

# --- 2. lemmas listed in the manifest -------------------------------------
grep -vE '^#|^[[:space:]]*$' "$TSV" | cut -d'|' -f1,2 | sort > "$(dirname "$tmp_decl")/tsv_lemmas"

# Missing from manifest (declared but not listed):
if diff <(sort "$tmp_decl") "$(dirname "$tmp_decl")/tsv_lemmas" >/dev/null 2>&1; then
    echo "contracts: lemma coverage OK ($(wc -l < "$tmp_decl" | tr -d ' ') lemmas)"
else
    echo "contracts: lemma coverage mismatch:"
    echo "  --- declared but not in contracts.tsv ---"
    comm -23 <(sort "$tmp_decl") "$(dirname "$tmp_decl")/tsv_lemmas" | sed 's/^/    /'
    echo "  --- in contracts.tsv but not declared ---"
    comm -13 <(sort "$tmp_decl") "$(dirname "$tmp_decl")/tsv_lemmas" | sed 's/^/    /'
    fail=1
fi
rm -f "$tmp_decl" "$(dirname "$tmp_decl")/tsv_lemmas"

# --- 3. mirror paths exist (skip support rows with mirror "-") -------------
echo "contracts: checking mirror paths ..."
while IFS='|' read -r model lemma kind mirror; do
    case "$model" in \#*|'') continue ;; esac
    if [ "$mirror" != "-" ] && [ ! -f "$mirror" ]; then
        echo "  MISSING mirror: $mirror (for $model $lemma)"
        fail=1
    fi
done < <(grep -vE '^#|^[[:space:]]*$' "$TSV")

# --- 4. every model mentioned in the human doc -----------------------------
for model in formal/*.dfy; do
    base="$(basename "$model")"
    if ! grep -qF "$base" "$CONTRACTS"; then
        echo "  MISSING from $CONTRACTS: $base"
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "contracts: FAILED"
    exit 1
fi
echo "contracts: OK"
