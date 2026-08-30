// formal/command_bisim.dfy
//
// Command bisimulation: the compiled bytecode for the store-mutating and
// control-transfer commands (KILL, MERGE, WRITE, QUIT, DO, GOTO) produces the
// same environment/output/control result as the AST interpretation.
// NEW (opNewScope) is modeled separately in scope_stack.dfy.
//
// Verify with:  dafny verify formal/command_bisim.dfy

module CommandBisim {

  type Env = string -> int
  type Out = seq<int>

  datatype Ctrl = Running | Quit | Goto(lab: string, routine: string) | Call(lab: string, routine: string)

  datatype Cmd =
    | CKill(name: string)              // "" = kill all locals
    | CMerge(dst: string, src: string)
    | CWrite(v: int)
    | CQuit
    | CDo(lab: string, routine: string)
    | CGotoCmd(lab: string, routine: string)

  function SetEnv(env: Env, x: string, v: int): Env
  {
    (y: string) => if y == x then v else env(y)
  }

  // Reset every local to its default (0).
  function KillAll(env: Env): Env
  {
    (x: string) => 0
  }

  function Kill(env: Env, name: string): Env
  {
    if name == "" then KillAll(env) else SetEnv(env, name, 0)
  }

  function Merge(env: Env, dst: string, src: string): Env
  {
    SetEnv(env, dst, env(src))
  }

  // AST interpretation of a single command.
  function ExecCmd(c: Cmd, env: Env, out: Out): (Env, Out, Ctrl)
  {
    match c
    case CKill(name) => (Kill(env, name), out, Running)
    case CMerge(dst, src) => (Merge(env, dst, src), out, Running)
    case CWrite(v) => (env, out + [v], Running)
    case CQuit => (env, out, Quit)
    case CDo(lab, routine) => (env, out, Call(lab, routine))
    case CGotoCmd(lab, routine) => (env, out, Goto(lab, routine))
  }

  // --- bytecode ---
  datatype Instr =
    | IKill(name: string)
    | IMerge(dst: string, src: string)
    | IPushConst(v: int)
    | IWrite
    | IQuit
    | ICallLabel(lab: string, routine: string)
    | IGoto(lab: string, routine: string)

  type Prog = seq<Instr>

  function CompileCmd(c: Cmd): Prog
  {
    match c
    case CKill(name) => [IKill(name)]
    case CMerge(dst, src) => [IMerge(dst, src)]
    case CWrite(v) => [IPushConst(v), IWrite]
    case CQuit => [IQuit]
    case CDo(lab, routine) => [ICallLabel(lab, routine)]
    case CGotoCmd(lab, routine) => [IGoto(lab, routine)]
  }

  function Step(prog: Prog, pc: int, stack: seq<int>, env: Env, out: Out, ctrl: Ctrl): (int, seq<int>, Env, Out, Ctrl)
    requires 0 <= pc < |prog|
  {
    match prog[pc]
    case IKill(name) => (pc + 1, stack, Kill(env, name), out, ctrl)
    case IMerge(dst, src) => (pc + 1, stack, Merge(env, dst, src), out, ctrl)
    case IPushConst(v) => (pc + 1, stack + [v], env, out, ctrl)
    case IWrite =>
      if |stack| >= 1 then (pc + 1, stack[..|stack| - 1], env, out + [stack[|stack| - 1]], ctrl)
      else (pc + 1, stack, env, out, ctrl)
    case IQuit => (pc + 1, stack, env, out, Quit)
    case ICallLabel(lab, routine) => (pc + 1, stack, env, out, Call(lab, routine))
    case IGoto(lab, routine) => (pc + 1, stack, env, out, Goto(lab, routine))
  }

  function Run(prog: Prog, pc: int, stack: seq<int>, env: Env, out: Out, ctrl: Ctrl, fuel: nat): (int, seq<int>, Env, Out, Ctrl)
    decreases fuel
  {
    if fuel == 0 || pc < 0 || pc >= |prog| || ctrl != Running then (pc, stack, env, out, ctrl)
    else
      var (pc', st', en', o', c') := Step(prog, pc, stack, env, out, ctrl);
      Run(prog, pc', st', en', o', c', fuel - 1)
  }

  // Unfold Run by one step.
  lemma RunStep(prog: Prog, pc: int, stack: seq<int>, env: Env, out: Out, ctrl: Ctrl, fuel: nat)
    requires fuel > 0 && 0 <= pc < |prog| && ctrl == Running
    ensures Run(prog, pc, stack, env, out, ctrl, fuel) ==
            var (pc', st', en', o', c') := Step(prog, pc, stack, env, out, ctrl);
            Run(prog, pc', st', en', o', c', fuel - 1)
  {
  }

  // KILL name resets only that variable.
  lemma KillReset(env: Env, name: string)
    requires name != ""
    ensures Kill(env, name)(name) == 0
  {
  }

  lemma KillOnlyOther(env: Env, name: string, x: string)
    requires name != "" && x != name
    ensures Kill(env, name)(x) == env(x)
  {
  }

  // MERGE copies src's value into dst, leaving other variables unchanged.
  lemma MergeCopy(env: Env, dst: string, src: string)
    ensures Merge(env, dst, src)(dst) == env(src)
  {
  }

  lemma MergeOther(env: Env, dst: string, src: string, x: string)
    requires x != dst
    ensures Merge(env, dst, src)(x) == env(x)
  {
  }

  // The command bisimulation theorem: compiling a command and running it from
  // pc = 0 (with enough fuel) yields exactly the AST interpretation.
  lemma CommandBisim(c: Cmd, env: Env, out: Out)
    ensures var (e, o, ct) := ExecCmd(c, env, out);
            Run(CompileCmd(c), 0, [], env, out, Running, |CompileCmd(c)|) ==
            (|CompileCmd(c)|, [], e, o, ct)
  {
    var prog := CompileCmd(c);
    match c
    case CKill(name) => {
      RunStep(prog, 0, [], env, out, Running, 1);
    }
    case CMerge(dst, src) => {
      RunStep(prog, 0, [], env, out, Running, 1);
    }
    case CWrite(v) => {
      RunStep(prog, 0, [], env, out, Running, 2);
      RunStep(prog, 1, [v], env, out, Running, 1);
    }
    case CQuit => {
      RunStep(prog, 0, [], env, out, Running, 1);
    }
    case CDo(lab, routine) => {
      RunStep(prog, 0, [], env, out, Running, 1);
    }
    case CGotoCmd(lab, routine) => {
      RunStep(prog, 0, [], env, out, Running, 1);
    }
  }

}
