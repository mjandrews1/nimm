// formal/special_vars.dfy
//
// Formal model of the special variables in special_vars.nim: $STACK/$ZLEVEL
// (call/DO depth, never underflows) and $TEST (the last truth-test result, a
// 0/1 bit that ELSE relies on).
//
// Verify with:  dafny verify formal/special_vars.dfy

module SpecialVars {

  // $STACK / $ZLEVEL: depth counters. push increments, pop decrements (a no-op
  // at 0 — never underflows), reset zeroes.
  function Push(d: int): int { d + 1 }

  function Pop(d: int): int
  {
    if d > 0 then d - 1 else 0
  }

  function Reset(): int { 0 }

  lemma PopPush(d: int) requires d >= 0 ensures Pop(Push(d)) == d { }
  lemma PopUnderflow(d: int) requires d >= 0 ensures Pop(d) >= 0 { }
  lemma PushIncreases(d: int) ensures Push(d) == d + 1 { }
  lemma ResetZero() ensures Reset() == 0 { }

  // $TEST: set to the truth value (0 or 1) of the last condition.
  function TruthFlag(cond: int): int
  {
    if cond == 0 then 0 else 1
  }

  lemma TruthFlagIsBit(cond: int) ensures TruthFlag(cond) == 0 || TruthFlag(cond) == 1 { }
  lemma TruthFlagZero(cond: int) ensures cond == 0 <==> TruthFlag(cond) == 0 { }
  lemma TruthFlagOne(cond: int) ensures cond != 0 <==> TruthFlag(cond) == 1 { }

}
