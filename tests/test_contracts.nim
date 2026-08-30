# test_contracts.nim — Phase 4 contracts drill.
#
# Exercises the debug-only `assert` contracts mirrored from the Dafny models
# (active when NOT compiled with -d:release). Each section names the model it
# mirrors. Compile/run:  nim c -r tests/test_contracts.nim
#
# Contracts exercised here live in:
#   value.nim    formatNumber canonical form   (formal/value_format.dfy)
#   globals.nim  pushScope/popScope sync       (formal/scope_stack.dfy)
#   globals.nim  $DATA tri-state               (formal/data_tristate.dfy)
#   key_encoding.nim / globals.nim key round-trip  (formal/key_encoding.dfy)

import strutils
import ../globals
import ../storage/key_encoding
import ../value

var seed = 0x1234567890ABCDEF'u64
proc rng(): uint32 =
  seed = seed * 6364136223846793005'u64 + 1442695040888963407'u64
  result = uint32(seed shr 32)

proc randInt(lo, hi: int): int =
  lo + int(rng() mod uint32(hi - lo + 1))

proc main() =
  echo "Contracts drill (debug assertions active)..."

  # --- formatNumber canonical form (formal/value_format.dfy) ---
  for _ in 1 .. 20000:
    discard formatNumber(float(randInt(-999999, 999999)) / float(randInt(1, 100000)))
    discard formatNumber(float(randInt(-9000000, 9000000)))
  echo "  formatNumber canonical form: ok"

  # --- pushScope/popScope sync (formal/scope_stack.dfy) ---
  var g = newGlobals()
  for _ in 1 .. 5000:
    g.pushScope()
    g.popScope()
  echo "  pushScope/popScope sync: ok"

  # NEW/QUIT restore vs propagate semantics
  var g2 = newGlobals()
  g2.setLocalDirect("X", "parent")
  g2.pushScope()
  g2.markNewed("X")
  g2.setLocalDirect("X", "newed-write")   # NEW'd -> discarded on QUIT
  g2.setLocalDirect("Y", "plain-write")   # not NEW'd -> propagates on QUIT
  assert g2.getLocalDirect("X") == "newed-write"
  g2.popScope()
  assert g2.getLocalDirect("X") == "parent", "NEW'd var should restore"
  assert g2.getLocalDirect("Y") == "plain-write", "written non-NEW'd var should propagate"
  echo "  NEW/QUIT restore/propagate: ok"

  # NEW/QUIT multi-level propagation (formal/scope_stack.dfy, #415)
  var gN = newGlobals()
  gN.setLocalDirect("A", "base")
  gN.pushScope()                       # depth 1
  gN.pushScope()                       # depth 2
  gN.setLocalDirect("A", "deep-write") # write at depth 2, not NEW'd
  gN.popScope()
  gN.popScope()
  assert gN.getLocalDirect("A") == "deep-write", "write should propagate to base"
  echo "  NEW/QUIT nested propagation: ok"

  var gR = newGlobals()
  gR.setLocalDirect("B", "base")
  gR.pushScope()                       # depth 1
  gR.markNewed("B")                    # NEW at depth 1
  gR.pushScope()                       # depth 2
  gR.setLocalDirect("B", "deep-write")
  gR.popScope()
  gR.popScope()
  assert gR.getLocalDirect("B") == "base", "write should be discarded at NEW boundary"
  echo "  NEW/QUIT nested restore: ok"

  # --- $DATA tri-state (formal/data_tristate.dfy) ---
  var g3 = newGlobals()
  assert g3.data("A") == 0                    # undefined
  g3.setLocalDirect("A", "v")
  assert g3.data("A") == 1                    # leaf value
  g3.setLocal("A", @["x"], "child")
  assert g3.data("A") == 11                   # value + child
  assert g3.data("A", @["y"]) == 0            # absent child
  echo "  $DATA tri-state: ok"

  # --- key round-trip (formal/key_encoding.dfy) ---
  for _ in 1 .. 5000:
    var subs: seq[string] = @[]
    for _ in 0 ..< randInt(0, 4):
      var s = ""
      for _ in 0 ..< randInt(0, 4):
        s.add(chr(randInt(32, 126)))
      subs.add(s)
    let (n2, s2) = decodeMakeKey(makeKey("^G", subs))
    assert n2 == "^G" and s2 == subs
  echo "  key round-trip: ok"

  echo ""
  echo "All contracts exercised!"

main()
