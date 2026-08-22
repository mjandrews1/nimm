# nimm Resume Instructions

## Objective
Build nimm, a M/MUMPS interpreter in Nim, achieving full ANSI/ISO + RSM + nimm extension conformance.

## Important Details
- **Primary server:** Utility-01 (192.168.0.103) — overnight soaks, RSM daemon, all testing
- **Utility-02 (Hetzner, 2.29.3.122):** DEPRECATED 2026-08-22 — no longer in use
- **nimm:** `/Users/mark/_diary/ports/nimm-annotated/`, binary `nimm` (built via `nim c -d:release -o:nimm main.nim`)
- **RSM:** `/Users/mark/_rsm/`, binary `rsm`, V1.83.1 (17458f03cf) — sole reference engine
- **RFC:** DEPRECATED — RSM is the sole reference engine

## Current State
- **Utility-01:** Active, primary testing server (192.168.0.103)
- **Utility-02:** DEPRECATED — no longer in use
- **nimm:** ISO suite 173/173, unit suites 19/19, extended 34/34
- **RSM:** Sole reference engine (RFC deprecated)
- **Critical path:** #289 — Phase 0 ✓, Phase 1 ✓, Phase 2 next (transactions)

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
