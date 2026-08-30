// formal/for_loop_bisim.dfy
//
// FOR-loop bisimulation: the compiled FOR bytecode (with a body and a step)
// produces the same final loop variable and environment as the AST loop.
// The loop variable is tracked separately (an int); the body is a single
// assignment to another variable in an imap. Step > 0.
//
// Verify with:  dafny verify formal/for_loop_bisim.dfy

module ForLoopBisim {

  type Env = imap<string, int>

  datatype Stmt = SAssign(y: string, v: int) | SSkip

  function ExecStmt(s: Stmt, env: Env): Env
  {
    match s
    case SAssign(y, v) => env[y := v]
    case SSkip => env
  }

  function BodyLen(s: Stmt): nat
  {
    match s
    case SAssign(y, v) => 2
    case SSkip => 0
  }

  // Final value of the loop variable (recursive; step > 0).
  function FinalVar(current: int, limit: int, step: int): int
    requires step > 0
    decreases limit - current + step
  {
    if current > limit then current else FinalVar(current + step, limit, step)
  }

  // Final environment after the loop (recursive).
  function ExecFor(current: int, limit: int, step: int, body: Stmt, env: Env): Env
    requires step > 0
    decreases limit - current + step
  {
    if current > limit then env else ExecFor(current + step, limit, step, body, ExecStmt(body, env))
  }

  // Fuel needed to run the loop from the head (pc = 2), recursively.
  function LoopFuel(current: int, limit: int, step: int, body: Stmt): nat
    requires step > 0
    decreases limit - current + step
  {
    if current > limit then 4 else LoopFuel(current + step, limit, step, body) + 9 + BodyLen(body)
  }

  // --- bytecode ---
  datatype Instr =
    | PushConst(v: int)
    | PushVar
    | SetVar
    | SetVarY(y: string)
    | Add
    | CmpGt
    | Jump(t: int)
    | JumpIfTrue(t: int)

  type Prog = seq<Instr>

  function Step(prog: Prog, pc: int, stack: seq<int>, current: int, env: Env): (int, seq<int>, int, Env)
    requires 0 <= pc < |prog|
  {
    match prog[pc]
    case PushConst(v) => (pc + 1, stack + [v], current, env)
    case PushVar => (pc + 1, stack + [current], current, env)
    case SetVar =>
      if |stack| >= 1 then (pc + 1, stack[..|stack| - 1], stack[|stack| - 1], env)
      else (pc + 1, stack, current, env)
    case SetVarY(y) =>
      if |stack| >= 1 then (pc + 1, stack[..|stack| - 1], current, env[y := stack[|stack| - 1]])
      else (pc + 1, stack, current, env)
    case Add =>
      if |stack| >= 2 then (pc + 1, stack[..|stack| - 2] + [stack[|stack| - 2] + stack[|stack| - 1]], current, env)
      else (pc + 1, stack, current, env)
    case CmpGt =>
      if |stack| >= 2 then
        (pc + 1, stack[..|stack| - 2] + [if stack[|stack| - 2] > stack[|stack| - 1] then 1 else 0], current, env)
      else (pc + 1, stack, current, env)
    case Jump(t) => (t, stack, current, env)
    case JumpIfTrue(t) =>
      if |stack| >= 1 then
        (if stack[|stack| - 1] == 1 then t else pc + 1, stack[..|stack| - 1], current, env)
      else (pc + 1, stack, current, env)
  }

  function Run(prog: Prog, pc: int, stack: seq<int>, current: int, env: Env, fuel: nat): (int, seq<int>, int, Env)
    decreases fuel
  {
    if fuel == 0 || pc < 0 || pc >= |prog| then (pc, stack, current, env)
    else
      var (pc', st', cur', en') := Step(prog, pc, stack, current, env);
      Run(prog, pc', st', cur', en', fuel - 1)
  }

  function CompileBody(s: Stmt): Prog
  {
    match s
    case SAssign(y, v) => [PushConst(v), SetVarY(y)]
    case SSkip => []
  }

  function CompileFor(init: int, limit: int, step: int, body: Stmt): Prog
  {
    var bodyCode := CompileBody(body);
    var exit := 11 + |bodyCode|;
    [PushConst(init), SetVar,
     PushVar, PushConst(limit), CmpGt, JumpIfTrue(exit)] + bodyCode +
    [PushVar, PushConst(step), Add, SetVar, Jump(2)]
  }

  // Unfold Run by one step.
  lemma RunStep(prog: Prog, pc: int, stack: seq<int>, current: int, env: Env, fuel: nat)
    requires fuel > 0 && 0 <= pc < |prog|
    ensures Run(prog, pc, stack, current, env, fuel) ==
            var (pc', st', cur', en') := Step(prog, pc, stack, current, env);
            Run(prog, pc', st', cur', en', fuel - 1)
  {
  }

  // Running the body (at pc = 6) updates env to ExecStmt(body, env).
  lemma RunBody(init: int, limit: int, step: int, body: Stmt, current: int, env: Env, fuel: nat)
    requires fuel >= BodyLen(body) + 1
    ensures Run(CompileFor(init, limit, step, body), 6, [], current, env, fuel) ==
            Run(CompileFor(init, limit, step, body), 6 + BodyLen(body), [], current, ExecStmt(body, env), fuel - BodyLen(body))
  {
    var prog := CompileFor(init, limit, step, body);
    match body
    case SAssign(y, v) => {
      assert prog[6] == PushConst(v);
      RunStep(prog, 6, [], current, env, fuel);
      assert prog[7] == SetVarY(y);
      RunStep(prog, 7, [v], current, env, fuel - 1);
    }
    case SSkip => {
    }
  }

  // The loop invariant: from the loop head (pc = 2) with the loop variable
  // = current, the loop terminates with FinalVar and the final environment.
  lemma LoopFrom(init: int, limit: int, step: int, body: Stmt, current: int, env: Env, fuel: nat)
    requires step > 0
    requires fuel >= LoopFuel(current, limit, step, body)
    ensures Run(CompileFor(init, limit, step, body), 2, [], current, env, fuel) ==
            (11 + BodyLen(body), [], FinalVar(current, limit, step), ExecFor(current, limit, step, body, env))
    decreases limit - current + step
  {
    var prog := CompileFor(init, limit, step, body);
    var exit := 11 + BodyLen(body);
    RunStep(prog, 2, [], current, env, fuel);
    RunStep(prog, 3, [current], current, env, fuel - 1);
    RunStep(prog, 4, [current, limit], current, env, fuel - 2);
    RunStep(prog, 5, [if current > limit then 1 else 0], current, env, fuel - 3);
    if current > limit {
      assert FinalVar(current, limit, step) == current;
      assert ExecFor(current, limit, step, body, env) == env;
      calc {
        Run(prog, 2, [], current, env, fuel);
      == { }
        Run(prog, 5, [1], current, env, fuel - 3);
      == { }
        (exit, [], current, env);
      }
    } else {
      var env1 := ExecStmt(body, env);
      var afterBody := 6 + BodyLen(body);
      RunBody(init, limit, step, body, current, env, fuel - 4);
      RunStep(prog, afterBody, [], current, env1, fuel - 4 - BodyLen(body));
      RunStep(prog, afterBody + 1, [current], current, env1, fuel - 5 - BodyLen(body));
      RunStep(prog, afterBody + 2, [current, step], current, env1, fuel - 6 - BodyLen(body));
      RunStep(prog, afterBody + 3, [current + step], current, env1, fuel - 7 - BodyLen(body));
      RunStep(prog, afterBody + 4, [], current + step, env1, fuel - 8 - BodyLen(body));
      LoopFrom(init, limit, step, body, current + step, env1, fuel - 9 - BodyLen(body));
      assert FinalVar(current, limit, step) == FinalVar(current + step, limit, step);
      assert ExecFor(current, limit, step, body, env) == ExecFor(current + step, limit, step, body, env1);
      calc {
        Run(prog, 2, [], current, env, fuel);
      == { }
        Run(prog, afterBody, [], current, env1, fuel - 4 - BodyLen(body));
      == { }
        Run(prog, afterBody + 4, [], current + step, env1, fuel - 8 - BodyLen(body));
      == { }
        Run(prog, 2, [], current + step, env1, fuel - 9 - BodyLen(body));
      == { }
        (exit, [], FinalVar(current, limit, step), ExecFor(current, limit, step, body, env));
      }
    }
  }

  // The bisimulation theorem.
  lemma ForBisim(init: int, limit: int, step: int, body: Stmt, env: Env)
    requires step > 0
    ensures Run(CompileFor(init, limit, step, body), 0, [], init, env, LoopFuel(init, limit, step, body) + 2).3 ==
            ExecFor(init, limit, step, body, env)
  {
    var prog := CompileFor(init, limit, step, body);
    var fuel := LoopFuel(init, limit, step, body) + 2;
    RunStep(prog, 0, [], init, env, fuel);
    RunStep(prog, 1, [init], init, env, fuel - 1);
    LoopFrom(init, limit, step, body, init, env, fuel - 2);
    assert Run(prog, 0, [], init, env, fuel).3 == ExecFor(init, limit, step, body, env);
  }

}
