# nimm Resume Instructions

## Objective
Build nimm, a M/MUMPS interpreter in Nim, achieving full ANSI/ISO + RSM + nimm extension conformance.

## Important Details
- **Servers:** Utility-01 (97.119.105.79), Utility-02 (2.29.3.122)
- **nimm:** `/Users/mark/_diary/ports/nimm-annotated/`, binary `nimm` (built via `nim c -d:release -o:nimm main.nim`)
  - **v0.1.0** — FROZEN (tagged `v0.1.0`, 100% conformance)
  - **v0.1.1** — Current development version
- **RSM:** `/Users/mark/_rsm/`, binary `rsm`, V1.83.1 (17458f03cf) — **FROZEN** (no code changes; occasional rebuilds only)
- **RFC:** `/Users/mark/_rfc/`, binary `rfc`, RFC V1.00.0 — **FROZEN** (no code changes; occasional rebuilds only)
- **Conformance scripts:** `/Users/mark/_diary/scripts/conformance_rsm.sh`, `conformance_rfc.sh`, `conformance_nimm.sh`

## Current State
- **All servers synced:** Local, Utility-01, Utility-02 all have same commit (6e90b2c), same versions, 100% conformance
- **All issues closed:** #167, #168, #169
- **nimm:** 100% conformance (55/55 tests)
- **RSM:** 80% conformance (28/35 tests)
- **RFC:** 80% conformance (29/36 tests)

## Next Steps
1. Continue addressing remaining open issues by tier
2. Update RESUME.md when pausing

## Relevant Files
- `/Users/mark/_diary/ports/nimm-annotated/` — nimm source (all .nim files)
- `/Users/mark/_diary/ports/nimm-annotated/evaluator.nim` — evaluator with all functions
- `/Users/mark/_diary/ports/nimm-annotated/engine.nim` — engine with all commands
- `/Users/mark/_diary/ports/nimm-annotated/parser.nim` — parser with pattern parsing
- `/Users/mark/_diary/ports/nimm-annotated/main.nim` — CLI entry point
- `/Users/mark/_diary/ports/nimm-annotated/RESUME.md` — resume instructions
- `/Users/mark/_diary/ports/nimm-annotated/nim.cfg` — build configuration
- `/Users/mark/_diary/ports/nimm-annotated/test_conformance.nim` — 60 tests
- `/Users/mark/_diary/ports/nimm-annotated/run_all_tests.nim` — 19 unit test modules
- `/Users/mark/_diary/ports/nimm-annotated/test_integration.nim` — 29 integration tests
- `/Users/mark/_diary/ports/nimm-annotated/critical-path.md` — issue tracking
- `/Users/mark/_diary/scripts/conformance_rsm.sh` — RSM conformance
- `/Users/mark/_diary/scripts/conformance_rfc.sh` — RFC conformance
- `/Users/mark/_diary/scripts/conformance_nimm.sh` — nimm conformance
