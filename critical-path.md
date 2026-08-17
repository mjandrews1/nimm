# nimm Critical Path

**Date:** 2026-08-17
**Status:** Phase 1 complete (globals, evaluator, engine, main), Phase 2-6 outstanding

---

## Current State

**Completed (Phase 1):**
- #14 Global/Local variable storage (globals.nim) ✅
- #15 Expression evaluator (evaluator.nim) ✅
- #16 Command dispatch (engine.nim) ✅
- #17 Main entry point (main.nim) ✅

**Open Issues:** 13

---

## Critical Path (Priority Order)

### Phase 2: Function Integration ✅ COMPLETE
**Goal:** Wire evaluator to call actual functions

1. **#18** Wire intrinsic functions to evaluator ✅
2. **#19** Wire NI functions to evaluator ✅
3. **#20** Wire special variables ✅

### Phase 3: Storage Integration ✅ COMPLETE
**Goal:** Wire LMDB as backing store for globals

4. **#21** LMDB global store integration ✅
   - Global variables (^ prefix) now backed by LMDB
   - Usage: nimm -d /path/to/db.mdb
   - Persistence verified across sessions

5. **#22** Key encoding integration ✅
   - M-collation ordering (numeric before string)
   - $ORDER and $QUERY now handle variable references
   - Shared encodeKey from key_encoding.nim

6. **#23** Data structure integration ✅
   - All 9 data structures accessible via $NI_* functions
   - Array, Object, Stack, Queue, Set, Map, Sorted, Deque, Bag

### Phase 4: Interactive/Batch Modes
**Goal:** Make nimm usable as a tool

7. **#24** Interactive REPL ✅
   - repl.nim — 130 lines
   - Special commands: /quit, /load, /clear, /history, /vars, /globals, /help
   - Error recovery, command history

8. **#25** Batch mode
**Goal:** Make nimm usable as a tool

7. **#24** Interactive REPL
   - Enhance main.nim REPL with history, completion
   - **Blocks:** #28 (integration tests)

8. **#25** Batch mode
   - File execution, error reporting
   - **Blocks:** #28

9. **#26** Error handling integration
   - Wire $ECODE/$ETRAP from error_handling.nim
   - **Blocks:** #29

### Phase 5: Testing
**Goal:** Comprehensive test coverage

10. **#27** Unit tests for all modules
    - **Blocks:** #28

11. **#28** Integration tests
    - **Blocks:** #29

12. **#29** Conformance tests
    - M/MUMPS standard compliance
    - **Blocks:** #30

### Phase 6: Polish
**Goal:** Production readiness

13. **#30** Performance optimization
14. **#31** Documentation
15. **#32** Packaging and distribution

### Stubs (from engine.nim)
**Goal:** Complete M command set

16. **#33** LOCK command
17. **#34** MERGE command
18. **#35** XECUTE command
19. **#36** BREAK command
20. **#37** OPEN/USE/CLOSE commands

---

## Dependencies

```
#18 (intrinsic) ──► #29 (conformance)
#19 (NI funcs)  ──► #23 (data structures)
#20 (specials)  ──► #24 (REPL)
#22 (key enc)   ──► #21 (LMDB) ──► #25 (batch)
#23 (data str)  ──► #29 (conformance)
#24 (REPL)      ──► #28 (integration)
#25 (batch)     ──► #28 (integration)
#26 (error)     ──► #29 (conformance)
#27 (unit)      ──► #28 (integration)
#28 (integ)     ──► #29 (conformance)
#29 (conform)   ──► #30 (perf)
#33-37 (stubs)  ──► #29 (conformance)
```

---

## Next Steps

1. **Immediate:** #18 (wire intrinsic functions) — unblocks conformance testing
2. **Next:** #20 (wire special variables) — unblocks REPL
3. **Then:** #21 (LMDB integration) — unblocks batch mode

---

## Notes

- Phase 1 is complete — nimm can execute basic M code
- REPL works but lacks history/completion
- Engine has stubs for LOCK, MERGE, XECUTE, BREAK, OPEN/USE/CLOSE
- LMDB storage exists but isn't wired to globals yet
- No test coverage beyond manual testing
