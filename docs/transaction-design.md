# Transaction Processing Design — TSTART/TCOMMIT/TROLLBACK

## ISO/IEC 11756:1999 §11 Reference

### Commands
- **TSTART** — Begin a transaction; increments $TLEVEL
- **TCOMMIT** — Commit current transaction level; decrements $TLEVEL. At level 0, persists all buffered writes to the store.
- **TROLLBACK** — Discard all writes at current transaction level; decrements $TLEVEL

### Special Variables
- **$TLEVEL** — Current transaction nesting level (0 = no transaction)
- **$TRESTART** — Number of times the current transaction has been restarted (§11.5)

### Semantics
1. TSTART pushes a new transaction level; $TLEVEL increments
2. Writes (SET, MERGE, KILL, etc.) during a transaction are buffered in the current level
3. Reads see writes from the current transaction (read-your-own-writes)
4. TCOMMIT at level > 0 merges buffer into parent level
5. TCOMMIT at level 0 persists all buffered writes to the underlying store
6. TROLLBACK discards the current level's buffer; $TLEVEL decrements
7. Inner TROLLBACK only undoes writes at that level; outer writes survive
8. Error inside transaction → implicit rollback of current level (§11.4)
9. Process exit with open transaction → implicit rollback

## Architecture

### Transaction Stack
```
type TransactionLevel = object
  writes: Table[string, string]    # key → value ("" = killed)
  kills: HashSet[string]           # keys explicitly killed

type TransactionState = object
  levels: seq[TransactionLevel]    # stack of active levels
  trestart: int                    # $TRESTART counter
```

### Key Format
Keys encode the full global reference: `^GLOBAL(sub1,sub2,...)` using the same
encoding as memGlobals (makeKey). This allows the transaction buffer to overlay
both in-memory and LMDB stores transparently.

### Read Path (with transaction overlay)
```
proc getWithOverlay(key): string =
  # Check transaction buffers from innermost to outermost
  for level in levels.reversed:
    if key in level.writes: return level.writes[key]
    if key in level.kills: return ""
  # Fall through to underlying store
  return store.get(key)
```

### Write Path (with transaction buffering)
```
proc setWithOverlay(key, value): void =
  if levels.len > 0:
    levels[^1].writes[key] = value
    levels[^1].kills.excl(key)
  else:
    store.set(key, value)
```

### Kill Path
```
proc killWithOverlay(key): void =
  if levels.len > 0:
    levels[^1].writes.del(key)
    levels[^1].kills.incl(key)
  else:
    store.kill(key)
```

## Implementation Plan

### Phase 1: Core Commands + In-Memory Overlay
1. Add cTstart, cTcommit, cTrollback to CmdKind enum
2. Add TSTART/TCOMMIT/TROLLBACK to parser command recognition
3. Add TransactionState to Engine (or Globals)
4. Implement overlay read/write/kill in globals.nim
5. Wire $TLEVEL/$TRESTART to TransactionState
6. Add implicit rollback on error

### Phase 2: LMDB Integration
7. Apply overlay to LMDB on TCOMMIT at level 0
8. Ensure LMDB reads check overlay first

### Phase 3: Concurrency + Crash Recovery
9. $TRESTART / TRESTART semantics (§11.5)
10. Implicit rollback on process exit/crash

## Test Cases
- Basic: TSTART SET ^A(1)="x" TCOMMIT → ^A(1) persists
- Rollback: TSTART SET ^A(1)="x" TROLLBACK → ^A(1) undefined
- Nested: TSTART TSTART SET ^A=1 TROLLBACK TCOMMIT → ^A undefined
- Read-your-writes: TSTART SET ^A=1 WRITE ^A → 1
- $TLEVEL: TSTART WRITE $TLEVEL → 1; TCOMMIT WRITE $TLEVEL → 0
- Implicit rollback: TSTART SET ^A=1 (error) → ^A undefined
