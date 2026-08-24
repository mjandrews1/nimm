#!/usr/bin/env bash
# bench_bytecode.sh — Benchmark bytecode VM vs AST interpreter
set -euo pipefail

NIMM="${NIMM_BIN:-./nimm}"

echo "=== Bytecode VM vs AST Interpreter Benchmark ==="
echo ""

bench() {
  local desc="$1" code="$2" iterations="${3:-1000}"
  local ast_time bc_time
  
  # AST timing
  ast_time=$(python3 -c "
import subprocess, time
start = time.time()
for _ in range($iterations):
    subprocess.run(['$NIMM', '-x', '$code'], capture_output=True)
elapsed = time.time() - start
print(f'{elapsed:.3f}')
")
  
  # Bytecode timing
  bc_time=$(python3 -c "
import subprocess, time
start = time.time()
for _ in range($iterations):
    subprocess.run(['$NIMM', '--bytecode', '-x', '$code'], capture_output=True)
elapsed = time.time() - start
print(f'{elapsed:.3f}')
")
  
  local speedup=$(python3 -c "print(f'{$ast_time / $bc_time:.1f}x')" 2>/dev/null || echo "N/A")
  printf "  %-25s AST: %ss  BC: %ss  Speedup: %s\n" "$desc" "$ast_time" "$bc_time" "$speedup"
}

bench "WRITE 1+2" "W 1+2" 100
bench "WRITE constant" "W 42" 100
bench "SET+WRITE" "SET X=1 W X" 100
bench "FOR 1:1:10" "F I=1:1:10 W I" 50
bench "String concat" 'W "hello"_"world"' 100
bench "\$LENGTH" 'W $L("hello")' 100

echo ""
echo "Note: Startup overhead dominates per-invocation benchmarks."
echo "For accurate VM-only benchmarks, use the in-process bench/bench.nim."
