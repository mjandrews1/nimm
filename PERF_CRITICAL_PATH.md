# nimm Performance Critical Path — Source-Level Trace

This document traces every function call in the hot path through the actual
source code, with file:line references, allocations, and timing data from
the in-process benchmark.

---

## 1. End-to-End Trace: `WRITE 1+2`

### Phase 0: Startup (one-time, ~50ms)

| Step | Call | Location | Cost |
|------|------|----------|------|
| 1 | `main()` | main.nim:116 | Entry |
| 2 | `parseArgs()` | main.nim:117→36 | CLI parse |
| 3 | `newGlobals("")` | main.nim:130→globals.nim:31 | scope stack init, no LMDB |
| 4 | `registerAllSpecialVars()` | main.nim:131→special_vars.nim:230 | 23× hash inserts into specialGetters/specialSetters |
| 5 | `newRuntime(nimm)` | main.nim:132→runtime.nim:71 | Table inits, parseCache = {} |
| 6 | `newEvaluator(g, rt)` | main.nim:133→evaluator.nim:43 | Stores ptr Globals, ptr Runtime |
| 7 | `newEngine(g, ev, rt)` | main.nim:134→engine.nim:39 | Heap: Engine + Debugger + JobTable + 64 DeviceHandles |

### Phase 1: Parse `WRITE 1+2` (~0.7µs)

| Step | Call | Location | Cost |
|------|------|----------|------|
| 8 | `parseLine(code)` | engine.nim:633 | Wrapper, creates Parser |
| 9 | `newParser("WRITE 1+2")` | parser.nim:88 | Lexer primed, first token lexed |
| 10 | `newLexer(src)` | lexer.nim:143 | Value object, copies src string |
| 11 | `lx.nextToken()` | lexer.nim:207 | Lexes "WRITE" char-by-char via isNameChar loop (:269-274) |
| 12 | `p.parseLine()` | parser.nim:669 | Allocates `Line(cmds: @[])` ref |
| 13 | `atCommandPos()` | parser.nim:169 | Triple check: isCommandWord ∧ precededByWs |
| 14 | `isCommandWord(p,"WRITE")` | parser.nim:143 | **toUpperAscii alloc** + case match |
| 15 | `parseCommand(p)` | parser.nim:695 | Dispatches on command word |
| 16 | `p.readWord()` | parser.nim:176 | Consumes "WRITE"; lexes next token "1" |
| 17 | `toUpperAscii("WRITE")` | parser.nim:697 | **string alloc** (case-insensitive dispatch) |
| 18 | `Cmd(kind: cWrite, ...)` | parser.nim:949 | **Heap alloc #1**: Cmd ref |
| 19 | `parseWriteArgs(p)` | parser.nim:1077 | Arg loop |
| 20 | `parseExpr()` | parser.nim:262 | Left-associative binop loop |
| 21 | `parsePrimary()` → tokNumber | parser.nim:336→338 | advance consumes "1" |
| 22 | `Expr(kind: numLit, sval: "1")` | parser.nim:346 | **Heap alloc #2**: Expr ref |
| 23 | `isBinop(peek)` → bAdd | parser.nim:269→lexer.nim:406 | tokPlus → some(bAdd) |
| 24 | `advance()` consumes "+" | parser.nim:271 | Next token = tokNumber("2") |
| 25 | `parsePrimary()` → "2" | parser.nim:336 | Same path |
| 26 | `Expr(kind: numLit, sval: "2")` | parser.nim:346 | **Heap alloc #3**: Expr ref |
| 27 | `Expr(kind: eBinary, op: bAdd, left, right)` | parser.nim:273 | **Heap alloc #4**: binary Expr ref |
| 28 | `CommandNode(postcond: nil, cmd: cmd)` | parser.nim:949 | **Heap alloc #5**: CommandNode ref |
| 29 | `Line` returned | parser.nim:681 | 1 command in line |

**Parse total**: 5 heap allocs, 2 toUpperAscii string allocs, 1 lexer loop.

### Phase 2: Execute `WRITE 1+2` (~0.25µs exec only)

| Step | Call | Location | Cost |
|------|------|----------|------|
| 30 | `eng.execute(line, 0)` | engine.nim:74 | Nil + depth check |
| 31 | `for cmdNode in line.cmds` | engine.nim:82 | 1 iteration |
| 32 | `case cmd.kind` → cWrite | engine.nim:95→166 | Dispatch |
| 33 | `for arg in cmd.writeArgs` | engine.nim:167 | 1 arg |
| 34 | `arg.kind == wrExpr` | engine.nim:168 | True |

### Phase 3: Evaluate `1+2` (~0.25µs)

| Step | Call | Location | Cost |
|------|------|----------|------|
| 35 | `ev.eval(arg.wexpr)` | engine.nim:170→evaluator.nim:51 | Case on expr.kind → eBinary |
| 36 | `ev.eval(expr.left)` | evaluator.nim:191 | numLit arm (:54) |
| 37 | `parseFloat("1")` | evaluator.nim:57 | → 1.0 |
| 38 | `formatNumber(1.0)` | evaluator.nim:58→value.nim:161 | Integer fast path: `$int64(v)` → "1" |
| 39 | **String alloc: "1"** | value.nim:163 | Amortized output |
| 40 | `ev.eval(expr.right)` | evaluator.nim:192 | Same: parseFloat → formatNumber → "2" |
| 41 | **String alloc: "2"** | value.nim:163 | |
| 42 | `case expr.op` → bAdd | evaluator.nim:193→194 | |
| 43 | `parseFloat(left) + parseFloat(right)` | evaluator.nim:195 | 1.0 + 2.0 = 3.0 |
| 44 | `formatNumber(3.0)` | evaluator.nim:195→value.nim:163 | `$int64(3)` → "3" |
| 45 | **String alloc: "3"** | value.nim:163 | Result |

**Eval cost**: 4× parseFloat, 3× formatNumber, ≥3 string allocs.
For a constant expression `1+2`, nothing is folded at parse time.

### Phase 4: Output (~0.05µs)

| Step | Call | Location | Cost |
|------|------|----------|------|
| 46 | `eng.currentChannel == 0` | engine.nim:171 | True (principal) |
| 47 | `eng.write("3")` | engine.nim:172→57 | `eng.output.add(s)` — amortized append |
| 48 | `execute` returns `""` | engine.nim:80 | No QUIT/Error |
| 49 | `eng.getOutput()` | main.nim:165→engine.nim:63 | Returns "3" |
| 50 | `echo output` | main.nim:166 | Writes "3\n" to stdout |

---

## 2. Critical Path by Subsystem

### 2A. Parser Hot Path

```
parseLine(code)                      engine.nim:633
  newParser(code)                    parser.nim:88
    newLexer(src)                    lexer.nim:143
  p.parseLine()                      parser.nim:669
    ├─ atCommandPos()                parser.nim:169
    │   ├─ isCommandWord(p, word)    parser.nim:143  ← toUpperAscii ALLOC
    │   ├─ precededByWs(p, t)        parser.nim:128  ← cheap char check
    │   └─ peek != tokColon          parser.nim:130
    ├─ parseCommand(p)               parser.nim:695
    │   ├─ readWord()                parser.nim:176  ← advance/nextToken
    │   ├─ toUpperAscii(name)        parser.nim:697  ← ALLOC
    │   └─ Cmd ref alloc             parser.nim:949  ← HEAP
    ├─ parseExpr(p)                  parser.nim:262
    │   └─ parsePrimary(p)           parser.nim:336
    │       ├─ Expr ref alloc        parser.nim:346  ← HEAP (per node)
    │       └─ parseSubscripts(p)    parser.nim:427  ← seq alloc
    └─ CommandNode ref alloc         parser.nim:949  ← HEAP
```

**Lexer cost per token** (lexer.nim:207-381):
- Whitespace skip: O(1) (:208-209)
- Number scan: `n.add` per digit (:242-263) — growth reallocs
- Word scan: `w.add` per char (:269-274) — growth reallocs
- String literal: `s.add` per char (:219-236) — growth reallocs

**Parser allocations for `WRITE 1+2`**:
- 5 ref objects (Line, CommandNode, Cmd, WriteArg, 3× Expr = ~8 refs)
- 2 string copies (toUpperAscii ×2)
- 1 seq (writeArgs)

### 2B. Evaluator Hot Path

```
eval(expr)                           evaluator.nim:51
  ├─ numLit (:54-60)
  │   ├─ parseFloat(expr.sval)       strutils.parseFloat
  │   └─ formatNumber(v)             value.nim:161
  │       ├─ int fast path: $int64   value.nim:163  ← 1 ALLOC
  │       └─ float path: $v + trim   value.nim:164-170
  │
  ├─ eVar (:63-75)
  │   ├─ subs = @[]                  evaluator.nim:64  ← seq ALLOC (always!)
  │   ├─ eval(sub) per subscript     evaluator.nim:65-66
  │   └─ globals.get(vname, subs)    globals.nim:156
  │       ├─ getLocal                globals.nim:48   ← makeKey ALLOC + 2 hash lookups/scope
  │       └─ getGlobal               globals.nim:136  ← LMDB txn per read
  │
  ├─ eFunc (:76-173)
  │   ├─ Special cases (incr/get/data/order)  evaluator.nim:78-169
  │   └─ Generic path:
  │       ├─ args = newSeq(fargs.len) evaluator.nim:170  ← seq ALLOC
  │       ├─ eval(arg) per arg        evaluator.nim:171-172
  │       └─ callFunction(name, args) evaluator.nim:173
  │           └─ case name of ...     evaluator.nim:308-1211
  │
  ├─ eSvar (:174-178)
  │   ├─ "$" & expr.sname            evaluator.nim:175  ← CONCAT ALLOC
  │   ├─ getSpecialVar(name)         globals.nim:264   ← 2 hash lookups + closure
  │   └─ fallback: callFunction      evaluator.nim:178
  │
  ├─ eBinary (:190-291)
  │   ├─ eval(left)                  evaluator.nim:191  ← recursive
  │   ├─ eval(right)                 evaluator.nim:192  ← recursive
  │   ├─ case op:
  │   │   ├─ arithmetic (bAdd-etc)   evaluator.nim:194-224
  │   │   │   └─ formatNumber(parseFloat(L) + parseFloat(R))
  │   │   │       ← 2× parseFloat + 1× formatNumber per binop
  │   │   ├─ comparisons             evaluator.nim:227-268
  │   │   │   └─ try parseFloat compare, fallback to string cmp
  │   │   └─ concat                  evaluator.nim:225-226
  │   │       └─ left & right        ← 1 ALLOC
  │   └─ (no short-circuit for &/!)  evaluator.nim:281-288
  │
  └─ eNeg (:179-184)
      └─ formatNumber(-parseFloat(val))  ← 1 parseFloat + 1 formatNumber
```

### 2C. Storage Hot Path (Globals)

```
globals.get(name, subs)              globals.nim:156
  ├─ name[0] == '^'?                 globals.nim:158  ← char test
  │
  ├─ LOCAL: getLocal(name, subs)     globals.nim:48
  │   ├─ makeKey(name, subs)         globals.nim:24   ← STRING ALLOC
  │   │   └─ result = name & '\0' & sub1 & '\0' & sub2...
  │   │       ← growth reallocs per subscript
  │   └─ countdown scopes:           globals.nim:51-54
  │       ├─ key in scopes[i]        ← HASH LOOKUP #1
  │       └─ scopes[i][key]          ← HASH LOOKUP #2
  │       ← Double lookup per scope level
  │
  └─ GLOBAL: getGlobal(name, subs)   globals.nim:136
      └─ lmdb_store.get(name, subs)  lmdb_store.nim:63
          ├─ encodeKey(name, subs)   key_encoding.nim:7  ← STRING ALLOC
          ├─ txnBegin(RDONLY)        lmdb_store.nim:68   ← NEW READ TXN
          │   ← Fresh transaction per single read!
          ├─ mdb_get(B-tree)         lmdb_store.nim:77
          ├─ abort(txn)              lmdb_store.nim:78
          └─ newString(size)+copyMem lmdb_store.nim:83-85  ← COPY ALLOC

globals.set(name, subs, value)       globals.nim:163
  ├─ LOCAL: setLocal                 globals.nim:56
  │   ├─ makeKey(name, subs)         ← STRING ALLOC
  │   └─ scopes[^1][key] = value     ← 1 HASH INSERT
  │
  └─ GLOBAL: setGlobal               globals.nim:141
      └─ lmdb_store.put(name, subs)  lmdb_store.nim:89
          ├─ encodeKey               ← STRING ALLOC
          ├─ txnBegin (writable)     lmdb_store.nim:94   ← NEW WRITE TXN
          ├─ mdb_put                 lmdb_store.nim:108
          ├─ txnCommit               lmdb_store.nim:113  ← COMMIT PER WRITE
          └─ nakedGlobal = name      lmdb_store.nim (globals.nim:145)
              nakedSubs = subs       ← SEQ COPY per global write
```

### 2D. FOR Loop Hot Path

```
cFor arm                             engine.nim:208
  ├─ parseFloat(eval(initE))         engine.nim:217  ← loop bound parsed once
  ├─ parseFloat(eval(stepE))         engine.nim:218-220
  ├─ parseFloat(eval(limitE))        engine.nim:221-223
  └─ while loop:                     engine.nim:226
      ├─ globals.set(varName, @[], $current)  engine.nim:227
      │   ├─ @[] alloc               ← EMPTY SEQ ALLOC per iteration
      │   ├─ $current (Nim float $)  ← ALLOC (uses "1.0" not "1"!)
      │   └─ makeKey + hash insert   ← STRING ALLOC + HASH
      └─ eng.execute(forBody, depth+1)  engine.nim:229
```

**FOR loop bug**: `$current` produces `"1.0"` instead of canonical `"1"`.
Should use `formatNumber(current)` for M conformance.

### 2E. Special Variable Hot Path

```
eSvar handler                        evaluator.nim:174
  ├─ "$" & expr.sname               evaluator.nim:175  ← CONCAT ALLOC
  └─ getSpecialVar(name)            globals.nim:264
      ├─ name in specialGetters     globals.nim:265   ← HASH LOOKUP
      ├─ specialGetters[name]()     globals.nim:266   ← HASH LOOKUP + CLOSURE
      └─ dispatch to getter proc:
          ├─ $HOROLOG               special_vars.nim:53-87
          │   ├─ cache hit?         special_vars.nim:56-59  ← toUnix compare
          │   └─ cache miss: times.now() + year loop (1840→now, ~186 iters)
          │       ← 186 iterations to compute days since 1840
          ├─ $IO/$TEST/$JOB/etc    → plain var return (cheap)
          ├─ $STORAGE               special_vars.nim:140-157
          │   └─ spawns subprocess: "sysctl -n hw.memsize" (macOS)
          │   ← SUBPROCESS SPAWN per call!
          └─ $ZHOROLOG              evaluator.nim:649-669
              └─ Same 1840-year loop as $HOROLOG, NO cache
```

---

## 3. Allocation Map

### Per `WRITE 1+2` invocation (parse+eval+output)

| Category | Count | What | Where |
|----------|-------|------|-------|
| AST nodes | 5 | Line, CommandNode, Cmd, WriteArg, eBinary | parser.nim:949, :949, :949, :1102, :273 |
| Expr leaves | 2 | numLit "1", numLit "2" | parser.nim:346 |
| String copies | 2 | toUpperAscii ×2 | parser.nim:144, :697 |
| Format results | 3 | "1", "2", "3" | value.nim:163 |
| Output buffer | 1 | "3" added to eng.output | engine.nim:57 |
| **Total** | **13** | | |

### Per `SET X=1` invocation (parse+eval+output)

| Category | Count | What | Where |
|----------|-------|------|-------|
| AST nodes | ~6 | Line, CommandNode, Cmd, SetItem, 2× Expr | parser.nim |
| String copies | 3 | toUpperAscii ×2, "SET" | parser.nim |
| makeKey | 1 | "X\0" | globals.nim:24 |
| Hash insert | 1 | scopes[^1][key] = "1" | globals.nim:58 |
| Format results | 1 | "1" | value.nim:163 |
| **Total** | **~12** | | |

### Per `FOR I=1:1:1000 SET X=I` (total)

| Category | Count | What |
|----------|-------|------|
| Parse | ~8 | AST nodes (one-time) |
| Loop body ×1000: | | |
| - $current alloc | 1000 | "1.0" string (should be "1") |
| - @[] alloc | 1000 | Empty seq for setLocal |
| - makeKey | 1000 | "I\0" string |
| - Hash insert | 1000 | scopes[^1][key] = value |
| - execute body | 1000 | SET command dispatch |
| **Total allocs** | **~4008** | 1000 × 4 allocs per iteration |

### Per `FOR I=1:1:1000` after optimization

| Category | Count | What |
|----------|-------|------|
| Parse | ~8 | AST nodes (one-time) |
| Loop body ×1000: | | |
| - formatNumber | 1000 | "1" (canonical, not "1.0") |
| - makeKey | 1000 | "I\0" string |
| - Hash insert | 1000 | scopes[^1][key] = value |
| **Total allocs** | **~3008** | 1000 × 3 (eliminated @[] alloc) |

---

## 4. Hot Spot Ranking (by impact)

### Tier 1: Dominant costs (70-80% of total time)

| # | Hot Spot | Location | Cost | Fix |
|---|----------|----------|------|-----|
| 1 | **Parser AST allocation** | parser.nim:273,346,949 | 5-8 ref allocs per line | Arena allocator, or AST pool |
| 2 | **numLit re-evaluation** | evaluator.nim:54-60 | parseFloat+formatNumber per eval | Pre-compute at parse time, store as float |
| 3 | **formatNumber string alloc** | value.nim:161-170 | 1 string alloc per numeric result | Reuse output buffer, or int-to-str without alloc |
| 4 | **Lexer string building** | lexer.nim:242-274 | `add` per char → growth reallocs | Pre-size buffer from source length |

### Tier 2: Significant costs (10-20% each)

| # | Hot Spot | Location | Cost | Fix |
|---|----------|----------|------|-----|
| 5 | **toUpperAscii per command** | parser.nim:144,697 | 1 string alloc per command boundary | Case-insensitive compare without alloc |
| 6 | **makeKey string building** | globals.nim:24-29 | 1 string alloc per variable access | Fixed buffer, or inline key encoding |
| 7 | **Double hash lookup** | globals.nim:52-53 | 2 lookups per scope level | Use `getOrDefault` or raw Table entry |
| 8 | **eVar subs seq alloc** | evaluator.nim:64 | 1 seq alloc per variable (even bare!) | Special-case empty subscripts |
| 9 | **eSvar "$" concat** | evaluator.nim:175 | 1 string alloc per special var | Pre-register with "$" prefix, or intern |

### Tier 3: Occasional costs (1-5% each)

| # | Hot Spot | Location | Cost | Fix |
|---|----------|----------|------|-----|
| 10 | **LMDB per-op transactions** | lmdb_store.nim:68,94 | 1 txn begin+commit per read/write | Batch reads in single txn |
| 11 | **pushScope full copy** | globals.nim:245-247 | O(n) table copy per NEW | Copy-on-write, or hash-map scope chain |
| 12 | **$STORAGE subprocess** | special_vars.nim:152 | spawns `sysctl` per call | Cache, or read /proc directly |
| 13 | **$ZHOROLOG uncached** | evaluator.nim:649-669 | Year loop ~186 iterations | Apply same TTL cache as $HOROLOG |
| 14 | **PIECE char-loop split** | evaluator.nim:394-402 | Manual split with per-piece alloc | Use strutils.splitLines or find-based |
| 15 | **eBinary no short-circuit** | evaluator.nim:281-288 | Both operands always evaluated | Lazy eval for & and ! |

### Tier 4: Micro costs (<1%)

| # | Hot Spot | Location | Cost | Fix |
|---|----------|----------|------|-----|
| 16 | **$ZDATETIME format tokens** | evaluator.nim:704-739 | String comparisons per char | Special-case common formats |
| 17 | **callFunction string dispatch** | evaluator.nim:308-1211 | Giant case-of on string | Hash-based dispatch, or enum tag |
| 18 | **try/except in comparisons** | evaluator.nim:227-268 | Exception for non-numeric compare | Check isCanonicalNumber first |
| 19 | **key_encoding decodeKey** | key_encoding.nim:16-38 | Per-char append in loop | Pre-compute splits |
| 20 | **mCollationCmp parseFloat** | key_encoding.nim:53-61 | parseFloat in exception path | Check digit prefix first |

---

## 5. Benchmark Baseline (post-optimization)

Measured with `bench/bench.nim --iterations=100000`:

| Operation | µs/call | ops/sec | Category |
|-----------|---------|---------|----------|
| WRITE 1+2 | 0.90 | 1.11M | Full pipeline |
| Execute-only (pre-parsed) | 0.25 | 4.01M | No parse |
| SET X=1 | 0.77 | 1.30M | Variable write |
| SET X=1 WRITE X | 1.40 | 717K | Read+write |
| $ASCII("A") | 1.05 | 952K | Intrinsic fn |
| $LENGTH("hello") | 1.17 | 856K | Intrinsic fn |
| $PIECE("a^b^c","^",2) | 1.86 | 537K | Complex fn |
| $HOROLOG | 0.92 | 1.09M | **Cached** |
| $NI_UUID | 1.01 | 988K | **Optimized** |
| $ZDATETIME($HOROLOG,...) | 4.71 | 212K | **Cached** |
| $ZHOROLOG | 4.28 | 234K | Uncached |
| FOR 1000 × SET X=I | 347 | 2.88K | Loop |

### Time breakdown for `WRITE 1+2` (0.90µs total)

| Phase | µs | % |
|-------|-----|---|
| Parse (AST build) | 0.65 | 72% |
| Eval (1+2 = 3) | 0.20 | 22% |
| Output (buffer add) | 0.05 | 6% |
| **Total** | **0.90** | 100% |

### Time breakdown for `SET X=1 WRITE X` (1.40µs total)

| Phase | µs | % |
|-------|-----|---|
| Parse (2 commands) | 0.75 | 54% |
| Eval (1 = "1") | 0.15 | 11% |
| Storage (set + get) | 0.35 | 25% |
| Output | 0.15 | 10% |
| **Total** | **1.40** | 100% |

---

## 6. Optimization Roadmap (prioritized)

### Immediate (done)
- [x] Parser AST cache for DO/XECUTE (#227)
- [x] $HOROLOG 1s TTL cache (#228) — 3.9x
- [x] $NI_UUID persistent fd (#229) — 410x
- [x] Seq pre-allocation in eval() (#230)
- [x] $ZDATETIME component cache — 2.2x
- [x] isCanonicalNumber inline strip

### High-value (next)

| # | Target | Expected | Effort | Files |
|---|--------|----------|--------|-------|
| 1 | numLit pre-computed float | 15-25% on arithmetic | Medium | evaluator.nim, ast.nim, parser.nim |
| 2 | formatNumber reuse buffer | 5-10% overall | Low | value.nim |
| 3 | toUpperAscii → case-insensitive cmp | 5-10% on parse | Low | parser.nim |
| 4 | eVar empty-subscript fast path | 5-10% on reads | Low | evaluator.nim |
| 5 | Double lookup → getOrDefault | 5-10% on storage | Low | globals.nim |
| 6 | makeKey reuse buffer | 5-10% on storage | Low | globals.nim |
| 7 | $ZHOROLOG caching | 3.9x on $ZHOROLOG | Low | evaluator.nim |
| 8 | Lexer buffer pre-size | 5-10% on parse | Low | lexer.nim |

### Medium-term

| # | Target | Expected | Effort | Files |
|---|--------|----------|--------|-------|
| 9 | LMDB read txn batching | 2-3x on globals | Medium | lmdb_store.nim |
| 10 | Arena allocator for AST | 10-30% GC reduction | High | ast.nim, parser.nim |
| 11 | String interning | 5-10% memory + GC | Medium | globals.nim |
| 12 | eBinary short-circuit &/! | 5-15% on conditionals | Low | evaluator.nim |
| 13 | pushScope copy-on-write | O(1) per NEW | High | globals.nim |
| 14 | callFunction hash dispatch | 5-10% on functions | Medium | evaluator.nim |

### Long-term (architectural)

| # | Target | Expected | Effort |
|---|--------|----------|--------|
| 15 | Bytecode VM | 5-20x overall | Very High |
| 16 | JIT compilation | 10-100x on hot loops | Very High |
| 17 | Incremental parser | Amortized O(1) per edit | Very High |

---

## 7. Key Insight

The critical path through nimm is:

```
Source string
  → Lexer (char-by-char, growth reallocs)
    → Parser (ref objects, toUpperAscii per command)
      → AST (5-8 ref objects per line)
        → Evaluator (recursive, re-parses numLits, allocs per result)
          → Storage (makeKey alloc, double hash lookup, LMDB txn)
            → Output (amortized buffer append)
```

**72% of time is in parsing/AST allocation**. The evaluator is only 22%.
This means the highest-impact optimization is reducing parser allocations,
not speeding up evaluation.

The `numLit` re-evaluation (evaluator.nim:54-60) is the single most
wasteful pattern: every numeric literal is `parseFloat`+`formatNumber`ed
on every evaluation, even though the value never changes. Pre-computing
the canonical form at parse time would eliminate this entirely.

---

## 8. Critical Path for Remaining Issues

### Dependency Graph

```
#232 (numLit pre-compute)  ←── no deps, highest impact
#233 (toUpperAscii)        ←── no deps, parse layer
#237 ($ZHOROLOG cache)     ←── no deps, easy win
#241 (short-circuit &/!)   ←── no deps, eval layer
#239 (lexer buffer)        ←── no deps, parse layer

#238 (formatNumber buf)    ←── no deps, but interacts with #232

#234 (bare var fast path)  ←── requires #236 (getOrDefault) first
#236 (double hash lookup)  ←── no deps, but #234 builds on it
#240 (makeKey buffer)      ←── can combine with #236 in one globals.nim pass

#242 (LMDB batch reads)    ←── no deps, independent module
#245 (callFunction hash)   ←── no deps, independent module
#243 (arena allocator)     ←── no deps, but high risk (changes AST lifetime)
#244 (pushScope COW)       ←── no deps, but high risk (changes scope model)
```

### Optimal Implementation Order

#### Phase 1: Independent Quick Wins (parallel, 1-2 hours each)

These have no dependencies and can be done in any order:

| Order | Issue | Change | Risk | Expected |
|-------|-------|--------|------|----------|
| 1a | #237 | $ZHOROLOG: copy $HOROLOG cache pattern | Very Low | 4.28→0.92µs (4.7x) |
| 1b | #233 | parser.nim: toUpperAscii → equiWord compare | Low | 5-10% parse |
| 1c | #239 | lexer.nim: pre-size token buffers | Low | 5-10% parse |
| 1d | #241 | evaluator.nim: short-circuit bAnd/bOr | Low | 5-15% conditionals |

**Cumulative impact**: ~15-25% on mixed workload. Zero risk of regression.

#### Phase 2: Evaluator Core (sequential, 2-4 hours each)

| Order | Issue | Change | Risk | Expected |
|-------|-------|--------|------|----------|
| 2a | #232 | ast.nim + parser.nim + evaluator.nim: numLit cachedFloat | Medium | 15-25% arithmetic |
| 2b | #238 | value.nim: formatNumber buffer variant | Medium | 5-10% overall |

**Note**: #232 and #238 interact — both touch formatNumber. Do #232 first,
then #238 can use the pre-computed float to skip formatNumber entirely
for numLit nodes.

**Cumulative impact**: +20-35% on arithmetic-heavy code.

#### Phase 3: Storage Layer (sequential, 1-2 hours each)

| Order | Issue | Change | Risk | Expected |
|-------|-------|--------|------|----------|
| 3a | #236 | globals.nim: getOrDefault in getLocal/getSpecialVar | Low | 5-10% storage |
| 3b | #240 | globals.nim: reusable key buffer in makeKey | Low | 5-10% storage |
| 3c | #234 | evaluator.nim: bare-var fast path (uses #236) | Low | 5-10% reads |

**Note**: #236, #240, #234 all touch globals.nim. Do them in one pass.

**Cumulative impact**: +15-25% on variable-heavy code.

#### Phase 4: Independent Modules (parallel, 2-4 hours each)

| Order | Issue | Change | Risk | Expected |
|-------|-------|--------|------|----------|
| 4a | #242 | lmdb_store.nim: cached read transaction | Medium | 10-20% globals |
| 4b | #245 | evaluator.nim: Table dispatch for callFunction | Medium | 5-10% functions |

**Cumulative impact**: +15-25% on function-heavy code.

#### Phase 5: High-Risk Structural (sequential, 1-2 days each)

| Order | Issue | Change | Risk | Expected |
|-------|-------|--------|------|----------|
| 5a | #243 | ast.nim + parser.nim: arena allocator | High | 10-30% GC |
| 5b | #244 | globals.nim: layered scope with COW | High | O(1) NEW |

**These change fundamental data structures.** Test extensively after each.

### Expected Cumulative Impact

| Scenario | Before | After All | Speedup |
|----------|--------|-----------|---------|
| `WRITE 1+2` | 0.90 µs | ~0.55 µs | 1.6x |
| `SET X=1 WRITE X` | 1.40 µs | ~0.85 µs | 1.6x |
| `FOR 1000 × SET X=I` | 347 µs | ~200 µs | 1.7x |
| `$PIECE("a^b^c","^",2)` | 1.86 µs | ~1.2 µs | 1.6x |
| `$ZHOROLOG` | 4.28 µs | ~0.92 µs | 4.7x |
| Mixed workload | 1.0 µs | ~0.6 µs | 1.7x |

### Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|------------|
| Phase 1 | Very Low | Simple caches, case-insensitive compare |
| Phase 2 | Medium | AST node shape change (#232), formatNumber contract |
| Phase 3 | Low | Table lookup optimization, buffer reuse |
| Phase 4 | Medium | LMDB transaction model, dispatch table |
| Phase 5 | High | Fundamental data structure changes |

**Recommendation**: Implement Phases 1-4 first. Phase 5 only after
thorough testing of Phases 1-4 and establishing a comprehensive
test suite for scope/AST behavior.

### Testing Strategy

After each phase:
1. Run `nim c -d:release -r tests/test_engine.nim`
2. Run `nim c -d:release -r tests/test_evaluator.nim`
3. Run `nim c -d:release -r tests/test_globals.nim`
4. Run `nim c -d:release -r test_conformance.nim` (60 tests)
5. Run `nim c -d:release -r bench/bench.nim --iterations=100000`
6. Verify `./nimm -x 'FOR I=1:1:3 WRITE I'` outputs `1,2,3,`
