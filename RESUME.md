# nimm Work Resume Point

**Date:** 2026-08-18
**Last Action:** Fixed #152 (version flag), #156 (LMDB txn leaks), #157 (copyMem UB)

## Current State

### Conformance: ~90% (test runner needs execProcess fix)
The conformance test runner uses `execCmdEx` which interprets `$` as shell variables. Fix: use `execProcess` instead.

### Files Modified
- `main.nim` — Added `--version`/`-V` flag, Version const = "0.1.0"
- `storage/lmdb_store.nim` — Fixed copyMem UB, added try/finally for txn cleanup
- `nim.cfg` — Added `--out:nimm` for binary name

### Git Status
- **nimm repo:** Up to date (63062fc)
- **diary repo:** Needs update

## Immediate Next Steps

1. **Fix test_conformance.nim** — Replace `execCmdEx` with `execProcess`
2. **Run conformance tests** to get real score
3. **Commit** and push

## Open Issues (97)
| Category | Count |
|----------|-------|
| Bug | 7 |
| ANSI/ISO | 19 |
| RSM Extension | 24 |
| nimm Extension | 13 |
| Stub | 6 |
| Noop | 8 |
| Bounds | 10 |
| Port | 10 |

## Servers
| Server | IP | Status |
|--------|-----|--------|
| Utility-01 | 192.168.0.103 | Local, synced |
| Utility-02 | 2.29.3.122 | Hetzner, synced |

## DNS
- flamingyak.com → 2.29.3.122
- www.flamingyak.com → 2.29.3.122
- mcp.flamingyak.com → 2.29.3.122
