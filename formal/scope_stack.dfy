// formal/scope_stack.dfy
//
// Formal model of NEW/QUIT local-variable scoping (globals.nim pushScope /
// markNewed / popScope, #383 class).
//
// Two orthogonal properties:
//  1. Stack discipline — push/pop are balanced and never pop the base frame
//     (depth >= 1), and the four parallel arrays (scopes, scopeShared,
//     scopeNewedVars, scopeWrittenVars) stay in sync.
//  2. Value semantics — on QUIT, a NEW'd variable is restored to its parent
//     value, a written non-NEW'd variable propagates to the parent, and an
//     unwritten variable is unchanged.
//
// Verify with:  dafny verify formal/scope_stack.dfy

module ScopeStack {

  // Scope depth (shared by all four parallel arrays).
  function Push(d: int): int
    requires d >= 1
  {
    d + 1
  }

  function Pop(d: int): int
    requires d >= 1
  {
    if d == 1 then 1 else d - 1
  }

  // Push then pop returns to the original depth.
  lemma PopPush(d: int)
    requires d >= 1
    ensures Pop(Push(d)) == d
  {
  }

  // Pop never drops below the base frame.
  lemma PopUnderflow(d: int)
    requires d >= 1
    ensures Pop(d) >= 1
  {
  }

  // Push grows depth by exactly one.
  lemma PushDepth(d: int)
    requires d >= 1
    ensures Push(d) == d + 1
  {
  }

  // Four-array sync: scopes, scopeShared, scopeNewedVars and scopeWrittenVars
  // always have the same length. pushScope extends all four; popScope shrinks
  // all four.
  predicate Synced(scopesLen: int, sharedLen: int, newedLen: int, writtenLen: int)
  {
    scopesLen == sharedLen && sharedLen == newedLen && newedLen == writtenLen
  }

  lemma PushKeepsSynced(scopesLen: int, sharedLen: int, newedLen: int, writtenLen: int)
    requires Synced(scopesLen, sharedLen, newedLen, writtenLen)
    ensures Synced(scopesLen + 1, sharedLen + 1, newedLen + 1, writtenLen + 1)
  {
  }

  lemma PopKeepsSynced(scopesLen: int, sharedLen: int, newedLen: int, writtenLen: int)
    requires Synced(scopesLen, sharedLen, newedLen, writtenLen) && scopesLen >= 2
    ensures Synced(scopesLen - 1, sharedLen - 1, newedLen - 1, writtenLen - 1)
  {
  }

  // Variable environments are total functions name -> value.
  type Env = string -> string

  // Value of a variable after QUIT, given the parent's and the (top) child's
  // environments and the child's NEW'd/written sets.
  function AfterQuit(parentVars: Env, childVars: Env,
                     newed: set<string>, written: set<string>, x: string): string
  {
    if x in newed then parentVars(x)
    else if x in written then childVars(x)
    else parentVars(x)
  }

  // NEW'd variable: restored to the parent value (its writes are discarded).
  lemma NewedRestored(parentVars: Env, childVars: Env,
                      newed: set<string>, written: set<string>, x: string)
    requires x in newed
    ensures AfterQuit(parentVars, childVars, newed, written, x) == parentVars(x)
  {
  }

  // Written, non-NEW'd variable: propagated to the parent (its write survives).
  lemma WrittenPropagated(parentVars: Env, childVars: Env,
                          newed: set<string>, written: set<string>, x: string)
    requires x in written && x !in newed
    ensures AfterQuit(parentVars, childVars, newed, written, x) == childVars(x)
  {
  }

  // Unwritten variable: unchanged (the parent's COW copy is already correct).
  lemma UnwrittenUnchanged(parentVars: Env, childVars: Env,
                           newed: set<string>, written: set<string>, x: string)
    requires x !in newed && x !in written
    ensures AfterQuit(parentVars, childVars, newed, written, x) == parentVars(x)
  {
  }

  // --- Multi-level: a scope frame + the write-propagation chain (#415) ---

  // A frame records which vars are NEW'd and written at that level.
  datatype Frame = Frame(newed: set<string>, written: set<string>)

  // One QUIT: restore NEW'd vars, propagate written non-NEW'd vars upward, and
  // mark those propagated vars written in the parent — so an outer QUIT
  // propagates them again (the `scopeWrittenVars[^2].incl(name)` in popScope).
  function PopFrame(parent: Env, parentF: Frame, child: Env, childF: Frame): (Env, Frame)
  {
    ( (x: string) => if x in childF.newed then parent(x)
                     else if x in childF.written then child(x)
                     else parent(x),
      Frame(parentF.newed, parentF.written + (childF.written - childF.newed)) )
  }

  // A NEW'd var is restored to the parent value.
  lemma NewedRestores(parent: Env, parentF: Frame, child: Env, childF: Frame, x: string)
    requires x in childF.newed
    ensures (PopFrame(parent, parentF, child, childF).0)(x) == parent(x)
  {
  }

  // A written non-NEW'd var propagates, and is marked written in the parent.
  lemma WritePropagates(parent: Env, parentF: Frame, child: Env, childF: Frame, x: string)
    requires x in childF.written && x !in childF.newed
    ensures (PopFrame(parent, parentF, child, childF).0)(x) == child(x)
    ensures x in PopFrame(parent, parentF, child, childF).1.written
  {
  }

  // A write at the top propagates all the way to the base through a chain of
  // non-NEW'd intermediate scopes (the write is re-propagated by each QUIT).
  lemma TwoLevelPropagate(base: Env, baseF: Frame, mid: Env, midF: Frame,
                          top: Env, topF: Frame, x: string)
    requires x in topF.written && x !in topF.newed
    requires x !in midF.newed
    ensures
      var (mEnv, mF) := PopFrame(mid, midF, top, topF);
      (PopFrame(base, baseF, mEnv, mF).0)(x) == top(x)
  {
    WritePropagates(mid, midF, top, topF, x);
  }

  // A write at the top is discarded when an outer scope NEW'd the var: it
  // propagates only up to the NEW boundary, then restores to the base value.
  lemma TwoLevelRestore(base: Env, baseF: Frame, mid: Env, midF: Frame,
                        top: Env, topF: Frame, x: string)
    requires x in topF.written && x !in topF.newed
    requires x in midF.newed
    ensures
      var (mEnv, mF) := PopFrame(mid, midF, top, topF);
      (PopFrame(base, baseF, mEnv, mF).0)(x) == base(x)
  {
    WritePropagates(mid, midF, top, topF, x);
    var (mEnv, mF) := PopFrame(mid, midF, top, topF);
    NewedRestores(base, baseF, mEnv, mF, x);
  }

}
