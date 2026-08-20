# nimm v0.1.1 Critical Path

**Date:** 2026-08-20
**Status:** Active Development
**Goal:** ANSI/ISO M/Mlang/Mumps conformance

---

## Phase 1: I/O Foundation (Critical)

### 1.1 Redesign I/O Model (#201)
**Priority:** Critical
**Blocks:** #195, #198, #200, #199
**Effort:** Large

- Add channel table (array of 64 device handles) to Engine
- Channel 0 = principal device (stdin/stdout, always open)
- Channels 1-63 = user-assignable via OPEN
- OPEN syntax: `OPEN channel:(file:mode)[:timeout]`
- USE syntax: `USE channel[:params]`
- CLOSE syntax: `CLOSE channel`
- Update WRITE to use current device
- Update READ to use current device

**Test:** `OPEN 1:("/tmp/test.txt":"WRITE") USE 1 WRITE "Hello" CLOSE 1 USE 0`

### 1.2 Fix Argumentless FOR+QUIT (#196)
**Priority:** Critical
**Blocks:** File I/O loading, ERIC loader
**Effort:** Medium

- Debug QUIT postconditional inside argumentless FOR body
- Fix: `FOR SET X=X+1 QUIT:X>3` should terminate
- Fix: `FOR READ LINE QUIT:$ZEOF` should terminate at EOF

**Test:** `SET X=0 FOR SET X=X+1 QUIT:X>3 WRITE X,!`

---

## Phase 2: Core Functions (High Priority)

### 2.1 Fix $QUERY Format (#208)
**Priority:** High
**Blocks:** Global traversal
**Effort:** Medium

- $QUERY should return full global reference: `^GLOBAL(sub1,sub2,...)`
- Currently returns same as $ORDER (just subscript)
- Need to track global name and subscripts

**Test:** `SET ^A(1)=1,^A(2)=2 WRITE $QUERY(^A(1))` → `^A(2)`

### 2.2 Implement $TEXT (#209)
**Priority:** High
**Blocks:** Debugging tools
**Effort:** Medium

- $TEXT should return source line from loaded routine
- Parse `label+offset^routine` format
- Return actual source line

**Test:** `WRITE $TEXT(LABEL+1)` → source line

### 2.3 Implement Missing Functions (#210)
**Priority:** High
**Blocks:** Advanced M programming
**Effort:** Medium

- $NAME: Returns canonical name of variable
- $QLENGTH: Returns length of qualified name
- $QSUBSCRIPT: Returns subscript of qualified name

**Test:** `WRITE $NAME(X(1))` → `X(1)`

### 2.4 Implement Missing Special Variables (#212)
**Priority:** High
**Blocks:** Error handling, version info
**Effort:** Medium

- $ZVERSION: Version information
- $ZERROR: Error message
- $ZSTATUS: Status
- $ZTRAP: Trap handler

**Test:** `WRITE $ZVERSION` → version string

---

## Phase 3: Indirection (High Priority)

### 3.1 Implement Name Indirection (#206)
**Priority:** High
**Blocks:** Dynamic variable access
**Effort:** Large

- Parse @expr in SET, WRITE, etc.
- Evaluate @expr to get variable name
- Execute indirection

**Test:** `SET X="Y" SET @X=5 WRITE Y` → 5

### 3.2 Implement Naked References (#207)
**Priority:** High
**Blocks:** Efficient global traversal
**Effort:** Large

- Track last global reference
- Implement `^(sub1,sub2)` syntax
- Append subscripts to last global

**Test:** `SET ^A(1,2)=1 SET ^(3,4)=2 WRITE ^A(1,2,3,4)` → 2

---

## Phase 4: RSM Extensions (Medium Priority)

### 4.1 Implement Missing RSM Functions (#211)
**Priority:** Medium
**Blocks:** RSM conformance
**Effort:** Medium

- $ZDATETIME: Date/time formatting
- $ZSTRIP: Strip characters
- $ZSUBSTR: Extract substring
- $ZPIECE: Returns piece of string
- $ZORDER: Returns next global
- $ZPREVIOUS: Returns previous subscript

### 4.2 Implement Missing Commands (#202)
**Priority:** Medium
**Blocks:** Full M conformance
**Effort:** Small

- JOB: Fork new process
- VIEW: View/modify system parameters
- ZALLOCATE: Allocate global storage
- ZDEALLOCATE: Deallocate global storage
- ZEDIT: Edit routine
- ZLINK: Link routine

### 4.3 Implement LOCK, MERGE, ZGOTO, ZQUIT (#197)
**Priority:** Medium
**Blocks:** Full M conformance
**Effort:** Medium

- LOCK: Resource locking
- MERGE: Tree copy
- ZGOTO: Z-version of GOTO
- ZQUIT: Z-version of QUIT

---

## Phase 5: ERIC Data Loader (Low Priority)

### 5.1 Complete ERIC Loader (#199)
**Priority:** Low
**Blocks:** Data loading
**Effort:** Small

- Use channel-based I/O (#201)
- Use argumentless FOR+QUIT (#196)
- Replace chunked routine workaround

---

## Summary

| Phase | Priority | Issues | Effort | Blocks |
|-------|----------|--------|--------|--------|
| 1. I/O Foundation | Critical | #201, #196 | Large | 6 issues |
| 2. Core Functions | High | #208, #209, #210, #212 | Medium | 4 issues |
| 3. Indirection | High | #206, #207 | Large | 2 issues |
| 4. RSM Extensions | Medium | #211, #202, #197 | Medium | 3 issues |
| 5. ERIC Loader | Low | #199 | Small | 1 issue |

**Total:** 16 open issues, 5 phases

---

## Current Status

| Phase | Status | Notes |
|-------|--------|-------|
| 1. I/O Foundation | Not started | Critical path |
| 2. Core Functions | Not started | High priority |
| 3. Indirection | Not started | High priority |
| 4. RSM Extensions | Not started | Medium priority |
| 5. ERIC Loader | Partial | Chunked routine workaround |

---

## Recommendation

**Start with Phase 1.1 (#201)** — Redesign I/O model to use channel numbers. This is the foundation for all I/O conformance and blocks 6 other issues.

**Next: Phase 1.2 (#196)** — Fix argumentless FOR+QUIT. This blocks file I/O loading and the ERIC loader.

**Then: Phase 2** — Implement core functions and special variables for proper M conformance.
