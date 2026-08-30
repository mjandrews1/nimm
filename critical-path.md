# nimm Critical Path

**Canonical critical path:** GitHub issue [#450](https://github.com/mjandrews1/nimm/issues/450)
("Critical path: NimM remaining formalization + correctness gaps").
This file is a pointer; the issue tracker is authoritative.

**Remotes:** GitHub (`origin`) and Utility-01 (`/home/mark/nimm`, synced via
pull). GitLab is deprecated.

**Current state (2026-08-30):**
- Formal verification: 27 Dafny model sets, 281 lemmas, `make verify` green.
- Test suite: 66 tests passing.
- All prior phases (globals, evaluator, engine, storage, REPL, batch, error
  handling, tests) are complete and closed in the tracker.

## Standing policies
- **RSM source is frozen** — no development changes; the sole reference engine.
- **RFC deprecated** — RSM is the reference engine.
- **Utility-02 deprecated** — all roles on Utility-01.
- **nimm v0.1.0 frozen** (tag `v0.1.0`); development continues on v0.1.x.
