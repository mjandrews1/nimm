# nimm v0.1.1 Critical Path

**Date:** 2026-08-20
**Status:** v0.1.1 Complete — 60/60 tests, 51/51 conformance
**Goal:** ANSI/ISO M/Mlang/Mumps conformance

---

## Phase 1: I/O Foundation (Critical)

### 1.1 Redesign I/O Model (#201)
**Status:** Done
- Channel table (array of 64 device handles) in Engine
- Channel 0 = principal device (stdin/stdout, always open)
- Channels 1-63 = user-assignable via OPEN
- OPEN/USE/CLOSE/READ/WRITE all channel-aware

### 1.2 Fix Argumentless FOR+QUIT (#196)
**Status:** Done
- QUIT postconditional inside argumentless FOR body works
- `FOR SET X=X+1 QUIT:X>3` terminates correctly

---

## Phase 2: Core Functions (High Priority)

### 2.1 Fix $QUERY Format (#208)
**Status:** Done
- $QUERY returns full global reference: `^GLOBAL(sub1,sub2,...)`

### 2.2 Implement $TEXT (#209)
**Status:** Done
- $TEXT returns source line from loaded routine
- Parses `label+offset^routine` format

### 2.3 Implement Missing Functions (#210)
**Status:** Done
- $NAME, $QLENGTH, $QSUBSCRIPT

### 2.4 Implement Missing Special Variables (#212)
**Status:** Done
- $ZVERSION, $ZERROR, $ZSTATUS, $ZTRAP

---

## Phase 3: Indirection (High Priority)

### 3.1 Implement Name Indirection (#206)
**Status:** Done
- @expr in SET, WRITE, etc.

### 3.2 Implement Naked References (#207)
**Status:** Done
- ^(sub1,sub2) syntax

---

## Phase 4: RSM Extensions (Medium Priority)

### 4.1 Implement Missing RSM Functions (#211)
**Status:** Done
- $ZDATETIME, $ZSTRIP, $ZSUBSTR, $ZPIECE, $ZORDER, $ZPREVIOUS

### 4.2 Implement Missing Commands (#202)
**Status:** Done
- JOB (posix_spawn), VIEW (no-op), ZALLOCATE (no-op), ZDEALLOCATE (no-op), ZEDIT ($EDITOR), ZLINK (reload)

### 4.3 Implement LOCK, MERGE, ZGOTO, ZQUIT (#197)
**Status:** Done

---

## Phase 5: ERIC Data Loader (Low Priority)

### 5.1 Complete ERIC Loader (#199)
**Status:** Done
- 11,929 thesaurus + 3,894 BT + 4,526 RT + 7,219 synonyms loaded

---

## Summary

| Phase | Priority | Issues | Status |
|-------|----------|--------|--------|
| 1. I/O Foundation | Critical | #201, #196 | **Done** |
| 2. Core Functions | High | #208, #209, #210, #212 | **Done** |
| 3. Indirection | High | #206, #207 | **Done** |
| 4. RSM Extensions | Medium | #211, #202, #197, #214-#225 | **Done** |
| 5. ERIC Loader | Low | #199 | **Done** |

**nimm v0.1.1: 60/60 tests, 51/51 conformance — all issues resolved.**
