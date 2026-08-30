// formal/control_flow_bisim.dfy
//
// Control-flow bisimulation: the compiled IF/ELSE bytecode (with jump
// instructions) produces the same environment as the AST interpretation.
// Complements bytecode_bisim.dfy (linear core) with a pc-based VM.
//
// Verify with:  dafny verify formal/control_flow_bisim.dfy

module ControlFlowBisim {

  type Env = string -> int

  function SetEnv(env: Env, x: string, v: int): Env
  {
    (y: string) => if y == x then v else env(y)
  }

  datatype Cond = CInt(n: int) | CVar(x: string)
  datatype Stmt = SAssign(x: string, c: Cond) | SSkip

  function EvalCond(c: Cond, env: Env): int
  {
    match c
    case CInt(n) => n
    case CVar(x) => env(x)
  }

  function ExecStmt(s: Stmt, env: Env): Env
  {
    match s
    case SAssign(x, c) => SetEnv(env, x, EvalCond(c, env))
    case SSkip => env
  }

  function ExecStmts(ss: seq<Stmt>, env: Env): Env
  {
    if |ss| == 0 then env else ExecStmts(ss[1..], ExecStmt(ss[0], env))
  }

  // --- Flat instruction set (with jumps) ---
  datatype Instr =
    | PushConst(n: int)
    | PushVar(x: string)
    | SetVar(x: string)
    | Jump(t: int)
    | JumpIfFalse(t: int)

  type Prog = seq<Instr>

  function CompileCond(c: Cond): Prog
  {
    match c
    case CInt(n) => [PushConst(n)]
    case CVar(x) => [PushVar(x)]
  }

  function CompileStmt(s: Stmt): Prog
  {
    match s
    case SAssign(x, c) => CompileCond(c) + [SetVar(x)]
    case SSkip => []
  }

  function CompileStmts(ss: seq<Stmt>): Prog
  {
    if |ss| == 0 then [] else CompileStmt(ss[0]) + CompileStmts(ss[1..])
  }

  // --- pc-based VM ---
  function Step(prog: Prog, pc: int, stack: seq<int>, env: Env): (int, seq<int>, Env)
    requires 0 <= pc < |prog|
  {
    match prog[pc]
    case PushConst(n) => (pc + 1, stack + [n], env)
    case PushVar(x) => (pc + 1, stack + [env(x)], env)
    case SetVar(x) =>
      if |stack| >= 1 then (pc + 1, stack[..|stack| - 1], SetEnv(env, x, stack[|stack| - 1]))
      else (pc + 1, stack, env)
    case Jump(t) => (t, stack, env)
    case JumpIfFalse(t) =>
      if |stack| >= 1 then
        (if stack[|stack| - 1] == 0 then t else pc + 1, stack[..|stack| - 1], env)
      else
        (pc + 1, stack, env)
  }

  function Run(prog: Prog, pc: int, stack: seq<int>, env: Env, fuel: nat): (int, seq<int>, Env)
    decreases fuel
  {
    if fuel == 0 || pc < 0 || pc >= |prog| then (pc, stack, env)
    else
      var (pc', st', en') := Step(prog, pc, stack, env);
      Run(prog, pc', st', en', fuel - 1)
  }

  // --- IF/ELSE ---
  function CompileIf(c: Cond, t: seq<Stmt>, e: seq<Stmt>): Prog
  {
    var condCode := CompileCond(c);
    var thenCode := CompileStmts(t);
    var elseCode := CompileStmts(e);
    var elseStart := |condCode| + 1 + |thenCode| + 1;
    var endIdx := elseStart + |elseCode|;
    condCode + [JumpIfFalse(elseStart)] + thenCode + [Jump(endIdx)] + elseCode
  }

  function ExecIf(c: Cond, t: seq<Stmt>, e: seq<Stmt>, env: Env): Env
  {
    if EvalCond(c, env) == 0 then ExecStmts(e, env) else ExecStmts(t, env)
  }

  // Unfold Run by one step.
  lemma RunStep(prog: Prog, pc: int, stack: seq<int>, env: Env, fuel: nat)
    requires fuel > 0 && 0 <= pc < |prog|
    ensures Run(prog, pc, stack, env, fuel) ==
            var (pc', st', en') := Step(prog, pc, stack, env);
            Run(prog, pc', st', en', fuel - 1)
  {
  }

  // Running a statement body located at prog[pc .. pc + len) advances pc by len
  // and updates the environment to the AST result (net-0).
  lemma RunStmts(ss: seq<Stmt>, prog: Prog, pc: int, stack: seq<int>, env: Env, fuel: nat)
    requires 0 <= pc
    requires pc + |CompileStmts(ss)| <= |prog|
    requires prog[pc .. pc + |CompileStmts(ss)|] == CompileStmts(ss)
    requires fuel >= |CompileStmts(ss)|
    ensures Run(prog, pc, stack, env, fuel) ==
            Run(prog, pc + |CompileStmts(ss)|, stack, ExecStmts(ss, env), fuel - |CompileStmts(ss)|)
    decreases |ss|
  {
    if |ss| == 0 {
      assert CompileStmts(ss) == [];
    } else {
      match ss[0]
      case SAssign(x, c) => {
        var tail := CompileStmts(ss[1..]);
        assert CompileStmts(ss) == CompileCond(c) + [SetVar(x)] + tail;
        assert |CompileStmts(ss)| == 2 + |tail|;
        assert prog[pc] == CompileCond(c)[0];
        RunStep(prog, pc, stack, env, fuel);
        assert prog[pc + 1] == SetVar(x);
        RunStep(prog, pc + 1, stack + [EvalCond(c, env)], env, fuel - 1);
        assert prog[pc + 2 .. pc + 2 + |tail|] == tail;
        RunStmts(ss[1..], prog, pc + 2, stack, SetEnv(env, x, EvalCond(c, env)), fuel - 2);
        assert ExecStmts(ss, env) == ExecStmts(ss[1..], SetEnv(env, x, EvalCond(c, env)));
      }
      case SSkip => {
        assert CompileStmts(ss) == CompileStmts(ss[1..]);
        RunStmts(ss[1..], prog, pc, stack, env, fuel);
        assert ExecStmts(ss, env) == ExecStmts(ss[1..], env);
      }
    }
  }

  // The IF/ELSE bisimulation theorem.
  lemma IfBisim(c: Cond, t: seq<Stmt>, e: seq<Stmt>, env: Env)
    ensures Run(CompileIf(c, t, e), 0, [], env, |CompileIf(c, t, e)| + 2).2 ==
            ExecIf(c, t, e, env)
  {
    var condCode := CompileCond(c);
    var thenCode := CompileStmts(t);
    var elseCode := CompileStmts(e);
    var prog := CompileIf(c, t, e);
    var elseStart := |condCode| + 1 + |thenCode| + 1;
    var endIdx := elseStart + |elseCode|;
    assert |condCode| == 1;
    assert prog == condCode + [JumpIfFalse(elseStart)] + thenCode + [Jump(endIdx)] + elseCode;

    // Step 1: condition (single push at pc = 0).
    assert prog[0] == condCode[0];
    RunStep(prog, 0, [], env, |prog| + 2);
    var condVal := EvalCond(c, env);
    // Step 2: JumpIfFalse at pc = 1.
    assert prog[1] == JumpIfFalse(elseStart);
    RunStep(prog, 1, [condVal], env, |prog| + 1);
    if condVal == 0 {
      // Jumped to elseStart; run the else body there.
      assert prog[elseStart .. elseStart + |elseCode|] == elseCode;
      RunStmts(e, prog, elseStart, [], env, |prog|);
      assert Run(prog, 0, [], env, |prog| + 2) ==
             Run(prog, endIdx, [], ExecStmts(e, env), |prog| - |elseCode|);
      assert Run(prog, endIdx, [], ExecStmts(e, env), |prog| - |elseCode|).2 == ExecStmts(e, env);
    } else {
      // Fell through to thenCode (pc = 2); then Jump to endIdx.
      assert prog[2 .. 2 + |thenCode|] == thenCode;
      RunStmts(t, prog, 2, [], env, |prog|);
      assert prog[2 + |thenCode|] == Jump(endIdx);
      RunStep(prog, 2 + |thenCode|, [], ExecStmts(t, env), |prog| - |thenCode|);
      assert Run(prog, 0, [], env, |prog| + 2) ==
             Run(prog, endIdx, [], ExecStmts(t, env), |prog| - |thenCode| - 1);
      assert Run(prog, endIdx, [], ExecStmts(t, env), |prog| - |thenCode| - 1).2 == ExecStmts(t, env);
    }
  }

}
