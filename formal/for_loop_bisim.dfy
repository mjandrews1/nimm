// formal/for_loop_bisim.dfy
//
// FOR-loop bisimulation: the compiled FOR bytecode (with its back-edge opJump)
// produces the same final loop variable as the AST loop. Modeled for step 1
// with an empty body — the loop-structure + exit condition of the compiler's
// cFor emission (compiler.nim:169-208). The loop variable is the only state.
//
// Verify with:  dafny verify formal/for_loop_bisim.dfy

module ForLoopBisim {

  datatype Instr =
    | PushConst(v: int)
    | PushVar
    | SetVar
    | Add
    | CmpGt
    | Jump(t: int)
    | JumpIfTrue(t: int)

  type Prog = seq<Instr>

  // `current` is the loop variable's value (the only state).
  function Step(prog: Prog, pc: int, stack: seq<int>, current: int): (int, seq<int>, int)
    requires 0 <= pc < |prog|
  {
    match prog[pc]
    case PushConst(v) => (pc + 1, stack + [v], current)
    case PushVar => (pc + 1, stack + [current], current)
    case SetVar =>
      if |stack| >= 1 then (pc + 1, stack[..|stack| - 1], stack[|stack| - 1])
      else (pc + 1, stack, current)
    case Add =>
      if |stack| >= 2 then (pc + 1, stack[..|stack| - 2] + [stack[|stack| - 2] + stack[|stack| - 1]], current)
      else (pc + 1, stack, current)
    case CmpGt =>
      if |stack| >= 2 then
        (pc + 1, stack[..|stack| - 2] + [if stack[|stack| - 2] > stack[|stack| - 1] then 1 else 0], current)
      else (pc + 1, stack, current)
    case Jump(t) => (t, stack, current)
    case JumpIfTrue(t) =>
      if |stack| >= 1 then
        (if stack[|stack| - 1] == 1 then t else pc + 1, stack[..|stack| - 1], current)
      else (pc + 1, stack, current)
  }

  function Run(prog: Prog, pc: int, stack: seq<int>, current: int, fuel: nat): (int, seq<int>, int)
    decreases fuel
  {
    if fuel == 0 || pc < 0 || pc >= |prog| then (pc, stack, current)
    else
      var (pc', st', cur') := Step(prog, pc, stack, current);
      Run(prog, pc', st', cur', fuel - 1)
  }

  // Compile FOR var=init:1:limit (empty body):
  //   0: PushConst(init)  1: SetVar  2: PushVar  3: PushConst(limit)
  //   4: CmpGt            5: JumpIfTrue(11)
  //   6: PushVar          7: PushConst(1)  8: Add  9: SetVar
  //   10: Jump(2)
  //   (11 = end)
  function CompileFor(init: int, limit: int): Prog
  {
    [PushConst(init), SetVar,
     PushVar, PushConst(limit), CmpGt, JumpIfTrue(11),
     PushVar, PushConst(1), Add, SetVar, Jump(2)]
  }

  // AST loop: final value of the loop variable (empty body, step 1).
  function ExecFor(init: int, limit: int): int
  {
    if init > limit then init else limit + 1
  }

  // Unfold Run by one step.
  lemma RunStep(prog: Prog, pc: int, stack: seq<int>, current: int, fuel: nat)
    requires fuel > 0 && 0 <= pc < |prog|
    ensures Run(prog, pc, stack, current, fuel) ==
            var (pc', st', cur') := Step(prog, pc, stack, current);
            Run(prog, pc', st', cur', fuel - 1)
  {
  }

  // The loop invariant: from the loop head (pc = 2) with the loop variable
  // = current, the loop terminates with it = current (if current > limit) or
  // limit+1.
  lemma LoopFrom(init: int, limit: int, current: int, fuel: nat)
    requires fuel >= 9 * (if current > limit then 0 else limit - current + 1) + 4
    ensures Run(CompileFor(init, limit), 2, [], current, fuel).2 ==
            (if current > limit then current else limit + 1)
    decreases limit - current + 1
  {
    var prog := CompileFor(init, limit);
    RunStep(prog, 2, [], current, fuel);
    RunStep(prog, 3, [current], current, fuel - 1);
    RunStep(prog, 4, [current, limit], current, fuel - 2);
    RunStep(prog, 5, [if current > limit then 1 else 0], current, fuel - 3);
    if current > limit {
      assert Run(prog, 2, [], current, fuel).2 == current;
    } else {
      RunStep(prog, 6, [], current, fuel - 4);
      RunStep(prog, 7, [current], current, fuel - 5);
      RunStep(prog, 8, [current, 1], current, fuel - 6);
      RunStep(prog, 9, [current + 1], current, fuel - 7);
      RunStep(prog, 10, [], current + 1, fuel - 8);
      LoopFrom(init, limit, current + 1, fuel - 9);
      assert Run(prog, 2, [], current, fuel).2 == limit + 1;
    }
  }

  // The bisimulation theorem.
  lemma ForBisim(init: int, limit: int)
    ensures Run(CompileFor(init, limit), 0, [], 0,
                9 * (if init > limit then 0 else limit - init + 1) + 6).2 ==
            ExecFor(init, limit)
  {
    var prog := CompileFor(init, limit);
    var fuel := 9 * (if init > limit then 0 else limit - init + 1) + 6;
    RunStep(prog, 0, [], 0, fuel);
    RunStep(prog, 1, [init], 0, fuel - 1);
    LoopFrom(init, limit, init, fuel - 2);
    assert Run(prog, 0, [], 0, fuel).2 == ExecFor(init, limit);
  }

}
