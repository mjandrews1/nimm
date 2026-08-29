#!/bin/bash
# fst_verify.sh <db_path> — verify an FST index (fst.lmdb) integrity via nimm ZVERIFY.
# Reports total keys, per-global counts, malformed keys, and stale locks.
# Usage: ./fst_verify.sh /path/to/fst.lmdb
set -euo pipefail

DB="${1:?usage: fst_verify.sh <db_path>}"
NIMM="${NIMM_BIN:-./bin/nimm}"

"$NIMM" -d "$DB" -x 'ZVERIFY'
