#!/bin/bash
# test_batch.sh — Test batch mode with multiple routines

echo "=== Batch Mode Test ==="

# Test 1: Run routine
echo "Test 1: Run routine"
DYLD_LIBRARY_PATH=/usr/local/lib ./main -r tests/test_batch.m -x 'DO ENTRY'
echo "Exit code: $?"

# Test 2: Run code directly
echo ""
echo "Test 2: Run code directly"
DYLD_LIBRARY_PATH=/usr/local/lib ./main -x 'WRITE "Hello from batch",!'
echo "Exit code: $?"

# Test 3: Error handling
echo ""
echo "Test 3: Error handling"
DYLD_LIBRARY_PATH=/usr/local/lib ./main -x 'WRITE 1/0' 2>&1
echo "Exit code: $?"

echo ""
echo "=== Done ==="
