#!/usr/bin/env bash
# run_samples.sh — run the sample programs on one engine.
#
#   ./run_samples.sh nimm            # NimM only (runs all three samples)
#   ./run_samples.sh rsm             # RSM: strict.m + rsmext.m
#   ./run_samples.sh rfc             # RFC: strict.m + rsmext.m
#
# Isolation discipline (see tests/mumps_extended_conformance.py): the RSM and
# RFC daemons must NEVER run concurrently. Start one daemon, run its leg, then
# stop it before starting the other. For rsm/rfc legs, point RSM_DBFILE at the
# running environment; for rfc also set RFC_DBFILE.
#
# Routine loading mechanics:
#   - NimM loads .m files directly via `-r file.m`.
#   - RSM/RFC have no CLI file loader; we import by MERGE-ing source lines
#     into the ^$ROUTINE structured system variable (same path as %RR),
#     then DO the routine.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${1:?usage: run_samples.sh nimm|rsm|rfc}"
RSM_BIN="${RSM_BIN:-/Users/mark/_rsm/rsm}"
RFC_BIN="${RFC_BIN:-/Users/mark/_rfc/builddir/rfc}"
NIMM_BIN="${NIMM_BIN:-$DIR/../nimm}"

run_mfile() {
  local mfile="$1"
  local name
  name="$(basename "$mfile" .m)"
  case "$ENGINE" in
    nimm)
      "$NIMM_BIN" -r "$mfile" -x "DO ${name}" 2>&1
      ;;
    rsm|rfc)
      local bin payload
      bin="$RSM_BIN"
      [ "$ENGINE" = "rfc" ] && bin="$RFC_BIN"
      payload="$(python3 - "$mfile" <<'PYEOF'
import sys

lines = open(sys.argv[1]).read().rstrip("\n").split("\n")
name = lines[0].split()[0]
cmds = ["KILL ^T"]
for i, ln in enumerate(lines, 1):
    cmds.append('SET ^T(%d)="%s"' % (i, ln.replace('"', '""')))
cmds.append('MERGE ^$routine("%s")=^T' % name)
cmds += ["KILL ^T", "DO ^%s" % name]
print(" ".join(cmds))
PYEOF
)"
      "$bin" -x "$payload" 2>&1 |
        grep -v '^DEBUG:\|^Reference Standard\|^Copyright\|^https://\|^\[Instance\]\|^\[Volume'
      ;;
  esac
}

for f in "$DIR"/strict.m "$DIR"/rsmext.m "$DIR"/nimmext.m "$DIR"/labeled.m; do
  base="$(basename "$f")"
  [ "$base" = "nimmext.m" ] && [ "$ENGINE" != "nimm" ] && continue
  echo "=== $base [$ENGINE] ==="
  run_mfile "$f"
done
