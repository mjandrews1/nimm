# Makefile — build, test, and formal-verification targets for nimm.

.PHONY: build test formal verify

build:
	nim c -d:release -o:bin/nimm main.nim

# Full fast test suite (rebuilds the binary, then runs all shell + .nim tests).
test: build
	bash tests/run_all.sh

# Formal verification (Dafny models).
formal:
	./formal/verify.sh

# Everything: tests + formal verification.
verify: test formal
