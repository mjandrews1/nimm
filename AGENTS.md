# AGENTS.md — nimm development conventions

## Build & test

- Build: `nim c -d:release -o:bin/nimm main.nim`
- Unit tests (one file each): `nim c -r tests/test_<name>.nim`
- Shell integration tests: `bash tests/test_<name>.sh`
- Master runner (FST/storage suites): `bash tests/run_all.sh [data_dir]`

## Code conventions

### RULE: Unambiguous separators in data-structure encodings

Every serialized encoding — LMDB global keys, in-memory store keys, wire or
line formats, on-disk formats, and any stored data structure — must use
framing in which each byte/character value has exactly one role. Never
overload one value as both a separator and a data-type marker, or as both a
terminator and an empty-value marker.

Correct framing (a decoder always knows what the next token is):

- **Type-byte framing**: each field is `typeByte + data`, where the type byte
  fixes the data length (fixed-width, e.g. `\x01` + 19 bytes; or
  self-terminating, e.g. `\x02` + bytes + `\x00`).
- **Length-prefix framing**: `len + data`.

Anti-pattern (this caused the #356 nested-`$ORDER` corruption): using `\x00`
for separator + empty-string type + string terminator + trailing marker in a
single format. The decoder could not tell a separator from an empty
subscript, so multi-subscript keys decoded with spurious `""` entries.

Apply this to every new encoding, and audit existing ones for the same
overload before extending them.

### Routine files

- M routine names must be UPPERCASE, and the file must declare a matching
  header label (e.g. `DETECT ;`). Lowercase routine filenames fail to load.

### Executing M snippets

- `-x` treats its argument as a single line; a `FOR` loop consumes the rest of
  the line, so multi-line code with nested `FOR`/`DO` bodies must use `-e`
  (newlines) or `-r <routine.m>` instead of `-x`.
- In a `FOR` body, write one value per line with `w !,x` (not `w x,!`) so
  `tail -1` yields the last value, not an empty line.

### LMDB $DATA semantics

- `$DATA` on a global returns `10` when it has children (subscripts), `1` for
  a leaf value, `0` when undefined.

## Git / issues

- Remotes: **GitHub** (`origin`) and **Utility-01** (`/home/mark/nimm`, synced
  via pull). **GitLab is deprecated** — do not add or push to it.
- Manage issues with `gh issue create/edit/close`; keep #450 (critical path)
  current when phase status changes.
- Commit only intended files; never commit `bin/` or scratch artifacts.
