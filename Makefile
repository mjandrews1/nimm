# Makefile — build, test, and formal-verification targets for nimm.

.PHONY: build test formal verify fst-build

build:
	nim c -d:release -o:bin/nimm main.nim

# FST helper binaries (also written to bin/, never elsewhere).
fst-build:
	nim c -d:release -o:bin/build_bm25 future_search_tool/src/build_bm25.nim
	nim c -d:release --path:. -o:bin/fst_load_nim future_search_tool/src/fst_load_nim.nim

# Full fast test suite (rebuilds the binary, then runs all shell + .nim tests).
test: build
	bash tests/run_all.sh

# Formal verification (Dafny models) + contract-checklist enforcement.
formal:
	./formal/verify.sh
	./formal/check_contracts.sh

# Everything: tests + formal verification.
verify: test formal
