# Quality Criteria — Correctness, Clarity, Hardening

Living criteria for **NimM** (the M/MUMPS interpreter) and the **FST** (future
search tool). Each criterion is verifiable — it names the test, lint, or CI
gate that proves it holds. Gaps that become concrete work items are tracked as
issues; the criteria themselves should not drift.

## 1. Correctness — no silent divergence from M/ANSI-ISO or between code paths

**How do we know NimM is performing correctly?** We never assume it — we
establish it, in this order of authority:

1. **Documented sources of truth** — the ANSI/ISO M standards and the best
   available computer-engineering / computer-science literature, peer products
   (GT.M, YottaDB, InterSystems IRIS/Caché), and industry best practice. Where a
   source is ambiguous (e.g. `$ORDER(x(""),-1)`), the conformance suite is the
   recorded decision.
2. **Conformance suites** — `ansi_iso_m_conformance.py` and
   `mumps_extended_conformance.py` are the executable form of the standard; they
   are the authority (C5).
3. **Differential validation** — it is okay (and encouraged) to express NimM's
   data structures and algorithms in another language or tool, as a reference
   implementation or oracle, and diff results against it. This is how subtle
   behavior (collation, key encoding, numeric formatting) earns trust.

Two hard rules:

- **Never adjust a test to accept a possibly-incorrect result.** A failing test
  means the code (or the test's source-of-truth) is wrong — fix the code or file
  an issue; do not weaken the expected value.
- **A divergence from a source of truth is a bug**, not an accepted behavior.

| # | Criterion | Verifier |
|---|---|---|
| C1 | **Store parity** — `memGlobals` and LMDB give identical results for every operation (get/set/kill, `$ORDER`, `$QUERY`, `$DATA`, `listSubs`, `listNodes`, transactions). | Run the same script with and without `-d` and diff output. (Would have caught the `$ORDER` backward-from-null and txn `decodeKey` bugs.) |
| C2 | **Mode parity** — AST interpreter ≡ `--bytecode` output for every compiled command. | `test_bytecode_conformance.sh`, `test_bytecode_control.sh`, `test_bytecode_subscripts.sh`; any new bytecode feature is gated on an AST-vs-bytecode diff. |
| C3 | **Transaction read-your-own-writes** — `$GET`/`$DATA`/`$ORDER`/`$QUERY`/`listSubs`/`listNodes` all see uncommitted writes/kills, including kills-of-descendants. | `test_txn_reads.sh` (#396). |
| C4 | **M-collation** — empty first, numeric-before-string, negative 9's-complement, fractional `.5`, §9.9 backward-from-null — on **both** stores. | `test_key_encoding.sh` + `test_order_lmdb.sh`, extended with a per-store parity case (C1). |
| C5 | **Conformance is the authority** — the ANSI/ISO conformance suites are the spec; they must stay green. | `tests/ansi_iso_m_conformance.py`, `tests/mumps_extended_conformance.py` in CI. |
| C6 | **Determinism** — table-iteration order never leaks into output. | Sort before emitting (as `listLocals`, `ZROUTINES` now do). |
| C7 | **Error correctness** — stable `M<code>`, `$ECODE`/`$ZSTATUS`/`$TEST`/`$ZEOF` per spec, with position + source snippet. | `test_errorloc.sh`. |
| C8 | **No silent failure** — parse errors surface; the compiler's `else` never silently drops a command (now `needsAst`; keep auditing). | A lint that fails on any silent fallback. |
| C9 | **Differential oracle** — for subtle behavior, verify against a reference implementation in another language/tool and keep the golden outputs in the repo. | Reference oracle + golden files checked into `tests/`. |

## 2. Clarity — one source of truth, invariants explicit

| # | Criterion | Verifier |
|---|---|---|
| L1 | **One documented encoding** — type-byte or length-prefix framing only; never overload a byte as separator + type + terminator (the AGENTS.md rule). | Round-trip property tests: `encodeKey`/`decodeKey` and `makeKey`/`decodeMakeKey` are inverses. |
| L2 | **No dead/unwired code** — every field, command, and argument is wired or removed. | Clean `nim c` hints (no `XDeclaredButNotUsed`); continue the #388/#387 sweep. |
| L3 | **Dual-path isolation** — any mem/LMDB divergence lives in a named, co-located pair with a comment pointing at the parity test. | Code review + C1. |
| L4 | **Extensions documented** — every `$NI_*`/`Z*`/`NI*` extension lists its action vocabulary. | README / FUNCTIONS.md. |
| L5 | **Self-describing errors** — code + position + snippet; no bare `Error:`. | `test_errorloc.sh`. |
| L6 | **AGENTS.md is the live convention log** — new gotchas (routine naming, `-x` vs `-e`, `tail -1` in FOR bodies, canonical binary path) are appended when discovered. | Review at each change. |

## 3. Hardening — robust to bad input, concurrency, and hostile use

| # | Criterion | Verifier |
|---|---|---|
| H1 | **Fresh-binary harness** — tests always build and run the canonical `bin/nimm`, never a stale binary. | `run_all.sh` rebuilds before running. (Stale binary masked real regressions.) |
| H2 | **Input robustness** — no crash/panic on malformed M; depth/iteration caps honored. | `tests/m_fuzz.py` run + asserts on `MaxEvalDepth`/`MaxParseIterations`. |
| H3 | **Durability/recovery** — LMDB integrity, stale-lock detection, implicit rollback. | `ZVERIFY` check/repair; a kill-9-mid-transaction reopen test. |
| H4 | **Resource bounds** — bounded history/trace/inspector buffers, LMDB env size caps. | Asserts on `maxHistory`/`traceMaxEntries`. |
| H5 | **MCP security** — auth on every tool, write tools behind `--allow-write`, path allowlists, audit log, no secrets in output. | `test_mcp_introspection.sh` + a negative auth test. |
| H6 | **Error-trap safety** — `$ETRAP`/`$ZTRAP` fire once and cannot recurse infinitely. | An etrap depth cap + test. |

## 4. Dogfooding — test NimM with NimM

| # | Criterion | Verifier |
|---|---|---|
| D1 | **M-first tests** — maximize the use of NimM M code in test items and test scripts in place of other languages (Python, bash, zsh); M-routine fixtures are the default for exercising the interpreter. | Review of test scripts; new tests are written as `.m` routines / M `-x`/`-e` snippets unless another language is justified. |

Exception: it is okay to use any other language or tool if that delivers
correct, clear, or hardened results (e.g. the Python conformance harnesses, or
bash + curl for MCP HTTP round-trips).

## 5. FST-specific

| # | Criterion | Verifier |
|---|---|---|
| F1 | **Index reproducibility** — BM25 + entry-term expansion deterministic; results ordered. | Golden-output test on a fixed corpus. |
| F2 | **Index integrity** — corruption is detected, not returned as empty results. | A `ZVERIFY`-style scan for `fst.lmdb`. |
| F3 | **Endpoint hardening** — auth, param validation, query-result caps, timeouts. | Negative/limit tests on the MCP search endpoint. |
| F4 | **Deployment** — systemd `Restart=always`, Caddy TLS, health endpoint, log rotation. | Verified on Utility-01. |

## Verification matrix

Criterion → where it is (or will be) enforced:

| Criterion | Enforcement |
|---|---|
| C1 | new `tests/test_store_parity.sh` (mem vs LMDB diff) |
| C2 | existing `tests/test_bytecode_*.sh` |
| C3 | existing `tests/test_txn_reads.sh` |
| C4 | existing `tests/test_key_encoding.sh` + `test_order_lmdb.sh` |
| C5 | CI: conformance suites |
| C6 | code review + existing sorted-emit patterns |
| C7 | existing `tests/test_errorloc.sh` |
| C8 | new lint pass |
| C9 | reference oracle + golden files in `tests/` |
| L1 | new `tests/test_encoding_roundtrip.nim` |
| L2 | CI: `nim c` hint-clean gate |
| L3–L5 | code review; L5 via `test_errorloc.sh` |
| L6 | AGENTS.md |
| H1 | `tests/run_all.sh` rebuilds first |
| H2 | `tests/m_fuzz.py` + unit asserts |
| H3 | `ZVERIFY` + new crash-recovery test |
| H4 | unit asserts |
| H5 | `test_mcp_introspection.sh` + new auth test |
| H6 | new etrap-depth test |
| D1 | code review of test scripts; M-routine fixtures are the default |
| F1–F4 | FST test scripts + Utility-01 verification |

## Status / how to use

- Add criteria here when a new class of bug is discovered (e.g. the "two stores
  diverge" class that C1 now pins down).
- When a criterion is fully enforced, mark it done here; when a gap is real
  work, file an issue and reference the criterion id (e.g. "C1 — store parity").
- Do not weaken a criterion to make a test pass; fix the code or file an issue.
