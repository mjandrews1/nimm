# Package
version       = "0.1.0"
author        = "Mark Andrews"
description   = "M/MUMPS Interpreter"
license       = "AGPL-3.0"
srcDir        = "src"
bin           = @["nimm"]

# Dependencies
requires "nim >= 2.2.0"
requires "lmdb >= 0.1.0"

# Build
binDir = "bin"

# Tasks
task build, "Build nimm":
  exec "nim c -d:release -o:bin/nimm main.nim"

task test, "Run all tests":
  exec "nim c -d:release -r run_all_tests.nim"

task conformance, "Run conformance tests":
  exec "nim c -d:release -r test_conformance.nim"
