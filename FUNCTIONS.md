# nimm Function Reference

**Version:** 0.1.1
**Date:** 2026-08-19

## ANSI/ISO Standard Functions

### Arithmetic Operators
| Operator | Description | Example | Result |
|----------|-------------|---------|--------|
| `+` | Addition | `WRITE 1+2` | 3 |
| `-` | Subtraction | `WRITE 5-3` | 2 |
| `*` | Multiplication | `WRITE 2*3` | 6 |
| `/` | Division | `WRITE 10/2` | 5 |
| `#` | Modulus | `WRITE 10#3` | 1 |
| `**` | Power | `WRITE 2**3` | 8 |
| `-` (unary) | Negation | `WRITE -5` | -5 |
| `_` | Concatenation | `WRITE "hello"_"world"` | helloworld |

### Comparison Operators
| Operator | Description | Example | Result |
|----------|-------------|---------|--------|
| `=` | Equal | `WRITE 1=1` | 1 |
| `'=` | Not equal | `WRITE 1'=2` | 1 |
| `<` | Less than | `WRITE 1<2` | 1 |
| `>` | Greater than | `WRITE 2>1` | 1 |

### Intrinsic Functions
| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `$ASCII(expr)` | Returns ASCII code | `WRITE $ASCII("A")` | 65 |
| `$CHAR(code)` | Returns character | `WRITE $CHAR(65)` | A |
| `$DATA(var)` | Returns variable status | `WRITE $DATA(X)` | 0 or 1 |
| `$EXTRACT(expr,from,to)` | Extracts substring | `WRITE $EXTRACT("hello",2,4)` | ell |
| `$FIND(expr,target,start)` | Finds substring | `WRITE $FIND("hello","l")` | 4 |
| `$GET(var,default)` | Returns variable value | `WRITE $GET(X)` | value |
| `$INCREMENT(var,amount)` | Increments variable | `WRITE $INCREMENT(X)` | value |
| `$JUSTIFY(expr,width,dec)` | Justifies value | `WRITE $JUSTIFY(42,10)` | "        42" |
| `$LENGTH(expr,delimiter)` | Returns length | `WRITE $LENGTH("hello")` | 5 |
| `$ORDER(subscript,dir)` | Returns next subscript | `WRITE $ORDER(^X(1))` | 2 |
| `$PIECE(expr,delim,from,to)` | Returns piece | `WRITE $PIECE("a,b,c",",",2)` | b |
| `$QUERY(subscript,dir)` | Returns next global | `WRITE $QUERY(^X)` | ^X(1) |
| `$RANDOM(limit)` | Returns random number | `WRITE $RANDOM(10)` | 0-9 |
| `$REVERSE(expr)` | Reverses string | `WRITE $REVERSE("hello")` | olleh |
| `$SELECT(expr:expr,...)` | Selects value | `WRITE $SELECT(1:"yes",0:"no")` | yes |
| `$STACK(level,expr)` | Returns stack info | `WRITE $STACK(0)` | level |
| `$TEXT(label+offset^routine)` | Returns text | `WRITE $TEXT(LABEL+1)` | line |
| `$TRANSLATE(expr,from,to)` | Translates chars | `WRITE $TRANSLATE("hello","el","EL")` | hELLo |

### Special Variables
| Variable | Description |
|----------|-------------|
| `$DEVICE` | Device status |
| `$ECODE` | Error code |
| `$ETRAP` | Error trap |
| `$HOROLOG` | Date/time |
| `$IO` | Current device |
| `$JOB` | Job ID |
| `$KEY` | Last read |
| `$PRINCIPAL` | Principal device |
| `$QUIT` | Quit status |
| `$REFERENCE` | Last global |
| `$STORAGE` | Available storage |
| `$STACK` | Stack level |
| `$SYSTEM` | System info |
| `$TEST` | Last test result |
| `$X` | Cursor X position |
| `$Y` | Cursor Y position |

## RSM Extensions

### Math Functions
| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `$ZABS(expr)` | Absolute value | `WRITE $ZABS(-5)` | 5 |
| `$ZSQRT(expr)` | Square root | `WRITE $ZSQRT(16)` | 4 |
| `$ZSIN(expr)` | Sine | `WRITE $ZSIN(0)` | 0 |
| `$ZCOS(expr)` | Cosine | `WRITE $ZCOS(0)` | 1 |
| `$ZEXP(expr)` | Exponential | `WRITE $ZEXP(0)` | 1 |
| `$ZLN(expr)` | Natural log | `WRITE $ZLN(1)` | 0 |
| `$ZPOWER(base,exp)` | Power | `WRITE $ZPOWER(2,3)` | 8 |
| `$ZTAN(expr)` | Tangent | `WRITE $ZTAN(0)` | 0 |
| `$ZARCSIN(expr)` | Arc sine | `WRITE $ZARCSIN(0)` | 0 |
| `$ZARCCOS(expr)` | Arc cosine | `WRITE $ZARCCOS(1)` | 0 |
| `$ZARCTAN(expr)` | Arc tangent | `WRITE $ZARCTAN(0)` | 0 |

### Date/Time Functions
| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `$ZHOROLOG` | Returns date/time | `WRITE $ZHOROLOG` | days,seconds |

### String Functions
| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `$ZCONVERT(expr,type)` | Converts case | `WRITE $ZCONVERT("hello","U")` | HELLO |
| `$ZWIDTH(expr)` | Returns width | `WRITE $ZWIDTH("hello")` | 5 |

### Commands
| Command | Description | Example |
|---------|-------------|---------|
| `ZSYSTEM expr` | Executes system command | `ZSYSTEM "echo test"` |

## nimm Extensions

### Data Structure Functions
| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `$NI_ARRAY(op,name,...)` | Array operations | `WRITE $NI_ARRAY("create","arr1")` | arr1 |
| `$NI_OBJECT(op,name,...)` | Object operations | `WRITE $NI_OBJECT("create","obj1")` | obj1 |
| `$NI_STACK(op,name,...)` | Stack operations | `WRITE $NI_STACK("create","stk1")` | stk1 |
| `$NI_QUEUE(op,name,...)` | Queue operations | `WRITE $NI_QUEUE("create","que1")` | que1 |
| `$NI_SET(op,name,...)` | Set operations | `WRITE $NI_SET("create","set1")` | set1 |
| `$NI_MAP(op,name,...)` | Map operations | `WRITE $NI_MAP("create","map1")` | map1 |
| `$NI_SORTED(op,name,...)` | Sorted operations | `WRITE $NI_SORTED("create","srt1")` | srt1 |
| `$NI_DEQUE(op,name,...)` | Deque operations | `WRITE $NI_DEQUE("create","deq1")` | deq1 |
| `$NI_BAG(op,name,...)` | Bag operations | `WRITE $NI_BAG("create","bag1")` | bag1 |

### Network Functions
| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `$NI_UUID` | Generates UUID v4 | `WRITE $NI_UUID` | 550e8400-e29b-41d4-a716-446655440000 |
| `$NI_HTTP(method,url,body)` | HTTP request | `WRITE $NI_HTTP("GET","https://example.com")` | response |
| `$NI_JSON(op,data)` | JSON operations | `WRITE $NI_JSON("encode",data)` | json |

### Special Variables
| Variable | Description |
|----------|-------------|
| `$SYSTEM` | System info |
| `$IO` | Current device |
| `$PRINCIPAL` | Principal device |

## Performance Characteristics

### Execution Time (nimm 0.1.1)

**Per-call performance (steady state):**
- All functions: ~3ms per call
- No variation by function type (arithmetic, comparison, intrinsic, RSM, nimm)
- Consistent across 10000 iterations

**Process startup overhead:**
- ~17ms overhead per `nimm -x` invocation
- 10 iterations: ~20ms/call (startup dominates)
- 10000 iterations: ~3ms/call (execution dominates)

**Server comparison:**
| Iterations | Utility-01 | Utility-02 |
|------------|------------|------------|
| 100 | 20.1 sec (3.9ms/call) | 28.9 sec (5.3ms/call) |
| 1000 | 173.6 sec (3.4ms/call) | 213.8 sec (4.0ms/call) |
| 10000 | 1,686 sec (3.3ms/call) | 1,629 sec (3.1ms/call) |

**Reliability:**
- 8400 randomized tests (100 runs × 84 tests): 100% pass rate
- No memory leaks or degradation
- Deterministic behavior

### Conformance
- **RSM mode:** 100% (29/29 tests)
- **RFC mode:** 100% (39/39 tests)
- **nimm mode:** 100% (51/51 tests)
