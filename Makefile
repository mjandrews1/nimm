# Makefile — build, test, and formal-verification targets for nimm.

.PHONY: build test formal verify fst-build

build:
	nim c -d:release -o:bin/nimm main.nim

# FST helper binaries (also written to bin/, never elsewhere).
fst-build:
	nim c -d:release -o:bin/build_bm25 future_search_tool/src/build_bm25.nim
	nim c -d:release --path:. -o:bin/fst_load_nim future_search_tool/src/fst_load_nim.nim
	nim c -d:release --path:. -o:bin/build_serial_link future_search_tool/src/build_serial_link.nim
	nim c -d:release --path:. -o:bin/build_reporter_link future_search_tool/src/build_reporter_link.nim
	nim c -d:release --path:. -o:bin/build_orangebook future_search_tool/src/build_orangebook.nim
	nim c -d:release --path:. -o:bin/build_clinicaltrials future_search_tool/src/build_clinicaltrials.nim
	nim c -d:release --path:. -o:bin/build_medicare future_search_tool/src/build_medicare.nim
	nim c -d:release --path:. -o:bin/build_cdc future_search_tool/src/build_cdc.nim
	nim c -d:release --path:. -o:bin/build_faers future_search_tool/src/build_faers.nim

# Full fast test suite (rebuilds the binary, then runs all shell + .nim tests).
test: build
	bash tests/run_all.sh

# Formal verification (Dafny models) + contract-checklist enforcement.
formal:
	./formal/verify.sh
	./formal/check_contracts.sh

# Everything: tests + formal verification.
verify: test formal
