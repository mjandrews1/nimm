# nimm — M/MUMPS Interpreter

A modern M/MUMPS interpreter written in Nim.

## Features

- **100% conformance** with ANSI/ISO M standard (60/60 tests passing)
- **Full M/MUMPS language support** including:
  - All intrinsic functions ($ASCII, $CHAR, $DATA, etc.)
  - All commands (SET, WRITE, IF, FOR, QUIT, KILL, etc.)
  - Pattern matching
  - NEW/QUIT scoping
  - Error handling ($ECODE/$ETRAP)
- **RSM extensions** (math functions, date/time, Z-commands)
- **nimm extensions** (data structures, network functions)
- **LMDB storage backend** for global variables
- **Interactive REPL** with command history
- **Debugger** (ZBREAK/ZSTEP/ZCONTINUE)

## Installation

### Prerequisites

- Nim 2.2.10 or later
- LMDB development libraries
- GCC or Clang

### Build from Source

```bash
# Clone repository
git clone https://github.com/mjandrews1/nimm.git
cd nimm

# Install dependencies
nimble install lmdb

# Build
nim c -d:release -o:nimm main.nim

# Run tests
nim c -d:release test_conformance.nim
./test_conformance
```

## Usage

### Execute Code Directly
```bash
nimm -x 'WRITE "Hello, World!"'
```

### Load and Execute Routine
```bash
nimm -r myroutine.m -x 'DO ENTRY'
```

### Interactive REPL
```bash
nimm --repl
```

### With LMDB Database
```bash
nimm -d /path/to/database.mdb -x 'SET ^X=42 WRITE ^X'
```

### Command Line Options
```
nimm -V                    Show version
nimm -x 'CODE'             Execute code directly
nimm -r file.m -e 'CODE'   Load routine and execute
nimm -d /path/to/db        Specify LMDB database
nimm --repl                Start interactive REPL
nimm -m MODE               Set mode (nimm|strict|rsm)
nimm --lint -r file.m      Lint routines without executing
nimm --lint-strict -r file.m  Lint; exit non-zero on warnings/errors
```

## Supported Functions

See [FUNCTIONS.md](FUNCTIONS.md) for complete function reference.

### ANSI/ISO Standard Functions
- $ASCII, $CHAR, $DATA, $EXTRACT, $FIND, $GET
- $INCREMENT, $JUSTIFY, $LENGTH, $ORDER, $PIECE
- $QUERY, $RANDOM, $REVERSE, $SELECT, $STACK
- $TEXT, $TRANSLATE, $CASE, $FNUMBER, $VIEW

### RSM Extensions
- Math: $ZABS, $ZARCCOS, $ZARCSIN, $ZARCTAN, $ZCOS, $ZEXP, $ZLN, $ZPOWER, $ZSIN, $ZSQRT, $ZTAN
- Date/Time: $ZDATE, $ZTIME, $ZHOROLOG
- String: $ZCONVERT, $ZWIDTH, $ZBIT

### nimm Extensions
- Data structures: $NI_ARRAY, $NI_OBJECT, $NI_STACK, $NI_QUEUE, $NI_SET, $NI_MAP, $NI_SORTED, $NI_DEQUE, $NI_BAG
- Advanced data structures: $NI_HEAP, $NI_RING, $NI_LRU, $NI_BITSET, $NI_TRIE, $NI_GRAPH, $NI_MATRIX, $NI_BLOOM, $NI_SKIPLIST, $NI_TREAP, $NI_DSET, $NI_SEGTREE, $NI_FENWICK, $NI_SPARSE, $NI_ITREE, $NI_SUFFIX, $NI_WAVELET, $NI_KDTREE, $NI_ROPE, $NI_MERKLE
- Network: $NI_HTTP, $NI_JSON, $NI_UUID, $NI_SLEEP
- System: $NI_SYSTEM(subscript) — hostname, pid, uid, cwd, arch, os, version, cpu_count, env:KEY

The advanced data structures are used as `$NI_<TYPE>("create","id",...)` to
allocate a named instance, then `$NI_<TYPE>("<action>","id",...)` to operate on
it. Each returns a status/value string. Examples:

```
WRITE $NI_HEAP("create","h")                    ; -> "h"
WRITE $NI_HEAP("push","h","apple")              ; -> 1 (size)
WRITE $NI_HEAP("peek","h")                      ; -> "apple" (min)
WRITE $NI_MATRIX("create","m",2,2)              ; -> "m"
WRITE $NI_MATRIX("set","m",0,0,3.5)             ; -> 1
WRITE $NI_SEGTREE("create","s",5)               ; -> "s"
WRITE $NI_SEGTREE("setdata","s",1,2,3,4,5)      ; -> 1
WRITE $NI_SEGTREE("build","s")                  ; -> 1
WRITE $NI_SEGTREE("query","s",0,4)              ; -> 15
```

Common actions: `create`, `destroy`, plus type-specific verbs (e.g. `push`/`pop`
for $NI_HEAP, `put`/`get`/`has` for $NI_LRU, `insert`/`query` for
$NI_SEGTREE/$NI_ITREE, `verify`/`root` for $NI_MERKLE).

## Commands

### Standard M Commands
SET, WRITE, IF, ELSE, FOR, QUIT, KILL, NEW, DO, GOTO, READ, HANG, LOCK, MERGE, XECUTE, BREAK

### RSM Extensions
ZHALT, ZMESSAGE, ZSAVE, ZSYSTEM, ZTRAP, ZBREAK, ZGOTO, ZPRINT, ZQUIT, ZLOAD, ZSTEP, ZCONTINUE, ZREMOVE

## Special Variables

$DEVICE, $ECODE, $ETRAP, $HOROLOG, $IO, $JOB, $KEY, $PRINCIPAL, $QUIT, $REFERENCE, $STORAGE, $STACK, $SYSTEM, $TEST, $X, $Y

## Testing

```bash
# Run all tests
nim c -d:release run_all_tests.nim
./run_all_tests

# Run conformance tests
nim c -d:release test_conformance.nim
./test_conformance

# Run integration tests
nim c -d:release test_integration.nim
./test_integration

# Run unified conformance script
./conformance.sh -m rsm -e ./nimm   # ANSI/ISO only
./conformance.sh -m rfc -e ./nimm   # ANSI/ISO + RSM extensions
./conformance.sh -m nimm -e ./nimm  # ANSI/ISO + RSM + nimm extensions

# Run performance tests
./performance.sh -e ./nimm -m nimm -n 100
```

## License

See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## Support

- GitHub: https://github.com/mjandrews1/nimm
- Issues: https://github.com/mjandrews1/nimm/issues
