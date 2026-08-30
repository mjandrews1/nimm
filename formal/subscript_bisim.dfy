// formal/subscript_bisim.dfy
//
// Subscripted read/write bisimulation: compiled `X(s1,...,sn)` (opPushVarSub)
// and `S X(s1,...,sn)=v` (opSetVarSub) produce the same result as the AST over
// a subscripted store. Complements bytecode_bisim.dfy (unsubscripted core).
//
// Verify with:  dafny verify formal/subscript_bisim.dfy

module SubscriptBisim {

  type Subs = seq<int>
  type Env = string -> (Subs -> int)

  function GetEnv(env: Env, x: string, subs: Subs): int { env(x)(subs) }

  function SetEnv(env: Env, x: string, subs: Subs, v: int): Env
  {
    (y: string) => if y == x then
                     (t: Subs) => if t == subs then v else env(x)(t)
                   else env(y)
  }

  datatype Expr =
    | Const(n: int)
    | SubVar(x: string, subs: seq<Expr>)

  datatype Stmt =
    | SubAssign(x: string, subs: seq<Expr>, e: Expr)

  datatype Op =
    | PushConst(v: int)
    | PushVarSub(x: string, n: nat)
    | SetVarSub(x: string, n: nat)

  // --- AST semantics ---
  function Nodes(e: Expr): nat
  {
    match e
    case Const(n) => 1
    case SubVar(x, subs) => 1 + NodesOfSubs(subs)
  }

  function NodesOfSubs(subs: seq<Expr>): nat
  {
    if |subs| == 0 then 0 else Nodes(subs[0]) + NodesOfSubs(subs[1..])
  }

  function EvalSubs(subs: seq<Expr>, env: Env): seq<int>
  {
    if |subs| == 0 then [] else [EvalExpr(subs[0], env)] + EvalSubs(subs[1..], env)
  }

  lemma EvalSubsLength(subs: seq<Expr>, env: Env)
    ensures |EvalSubs(subs, env)| == |subs|
  {
    if |subs| > 0 {
      EvalSubsLength(subs[1..], env);
    }
  }

  function EvalExpr(e: Expr, env: Env): int
  {
    match e
    case Const(n) => n
    case SubVar(x, subs) => GetEnv(env, x, EvalSubs(subs, env))
  }

  function ExecStmt(s: Stmt, env: Env): Env
  {
    match s
    case SubAssign(x, subs, e) => SetEnv(env, x, EvalSubs(subs, env), EvalExpr(e, env))
  }

  // --- Compiler ---
  function CompileSubs(subs: seq<Expr>): seq<Op>
  {
    if |subs| == 0 then [] else CompileExpr(subs[0]) + CompileSubs(subs[1..])
  }

  function CompileExpr(e: Expr): seq<Op>
  {
    match e
    case Const(n) => [PushConst(n)]
    case SubVar(x, subs) => CompileSubs(subs) + [PushVarSub(x, |subs|)]
  }

  function CompileStmt(s: Stmt): seq<Op>
  {
    match s
    case SubAssign(x, subs, e) => CompileSubs(subs) + CompileExpr(e) + [SetVarSub(x, |subs|)]
  }

  // --- Stack machine (linear) ---
  function Step(op: Op, stack: seq<int>, env: Env): (seq<int>, Env)
  {
    match op
    case PushConst(v) => (stack + [v], env)
    case PushVarSub(x, n) =>
      if |stack| >= n then
        (stack[..|stack| - n] + [GetEnv(env, x, stack[|stack| - n ..])], env)
      else
        (stack, env)
    case SetVarSub(x, n) =>
      if |stack| >= n + 1 then
        (stack[..|stack| - n - 1], SetEnv(env, x, stack[|stack| - n - 1 .. |stack| - 1], stack[|stack| - 1]))
      else
        (stack, env)
  }

  function ExecCode(code: seq<Op>, stack: seq<int>, env: Env): (seq<int>, Env)
    decreases |code|
  {
    if |code| == 0 then (stack, env)
    else
      var (st, en) := Step(code[0], stack, env);
      ExecCode(code[1..], st, en)
  }

  // --- Sequential composition ---
  lemma ExecCodeConcat(a: seq<Op>, b: seq<Op>, stack: seq<int>, env: Env)
    ensures ExecCode(a + b, stack, env) ==
            ExecCode(b, ExecCode(a, stack, env).0, ExecCode(a, stack, env).1)
    decreases |a|
  {
    if |a| == 0 {
      assert a == [];
      assert a + b == b;
      assert ExecCode(a, stack, env) == (stack, env);
    } else {
      var st := Step(a[0], stack, env).0;
      var en := Step(a[0], stack, env).1;
      ExecCodeConcat(a[1..], b, st, en);
      assert (a + b)[0] == a[0];
      assert (a + b)[1..] == a[1..] + b;
      assert ExecCode(a, stack, env) == ExecCode(a[1..], st, en);
      assert ExecCode(a + b, stack, env) == ExecCode(a[1..] + b, st, en);
    }
  }

  // --- Bisimulation ---

  // Running the sub-expression compilations pushes their values in order.
  lemma SubsBisim(subs: seq<Expr>, env: Env, stack: seq<int>)
    ensures ExecCode(CompileSubs(subs), stack, env) == (stack + EvalSubs(subs, env), env)
    decreases NodesOfSubs(subs), 1
  {
    if |subs| == 0 {
      assert CompileSubs(subs) == [];
      assert EvalSubs(subs, env) == [];
      assert stack + [] == stack;
      assert ExecCode([], stack, env) == (stack, env);
    } else {
      var v0 := EvalExpr(subs[0], env);
      ExprBisim(subs[0], env, stack);
      SubsBisim(subs[1..], env, stack + [v0]);
      ExecCodeConcat(CompileExpr(subs[0]), CompileSubs(subs[1..]), stack, env);
      assert CompileSubs(subs) == CompileExpr(subs[0]) + CompileSubs(subs[1..]);
      assert EvalSubs(subs, env) == [v0] + EvalSubs(subs[1..], env);
      calc {
        ExecCode(CompileSubs(subs), stack, env);
      == { assert CompileSubs(subs) == CompileExpr(subs[0]) + CompileSubs(subs[1..]); }
        ExecCode(CompileExpr(subs[0]) + CompileSubs(subs[1..]), stack, env);
      == { }
        ExecCode(CompileSubs(subs[1..]), stack + [v0], env);
      == { }
        (stack + [v0] + EvalSubs(subs[1..], env), env);
      == { assert EvalSubs(subs, env) == [v0] + EvalSubs(subs[1..], env);
           assert stack + [v0] + EvalSubs(subs[1..], env) == stack + ([v0] + EvalSubs(subs[1..], env)); }
        (stack + EvalSubs(subs, env), env);
      }
    }
  }

  lemma ExprBisim(e: Expr, env: Env, stack: seq<int>)
    ensures ExecCode(CompileExpr(e), stack, env) == (stack + [EvalExpr(e, env)], env)
    decreases Nodes(e), 0
  {
    match e {
      case Const(n) => {
        assert ExecCode([PushConst(n)], stack, env) == (stack + [n], env);
      }
      case SubVar(x, subs) => {
        SubsBisim(subs, env, stack);
        ExecCodeConcat(CompileSubs(subs), [PushVarSub(x, |subs|)], stack, env);
        var sv := EvalSubs(subs, env);
        EvalSubsLength(subs, env);
        assert |sv| == |subs|;
        assert ExecCode(CompileSubs(subs) + [PushVarSub(x, |subs|)], stack, env) ==
               ExecCode([PushVarSub(x, |subs|)], stack + sv, env);
        assert (stack + sv)[..|stack|] == stack;
        assert (stack + sv)[|stack| ..] == sv;
        assert ExecCode([PushVarSub(x, |subs|)], stack + sv, env) ==
               (stack + [GetEnv(env, x, sv)], env);
        assert EvalExpr(e, env) == GetEnv(env, x, sv);
      }
    }
  }

  lemma StmtBisim(s: Stmt, env: Env, stack: seq<int>)
    ensures ExecCode(CompileStmt(s), stack, env) == (stack, ExecStmt(s, env))
  {
    match s {
      case SubAssign(x, subs, e) => {
        SubsBisim(subs, env, stack);
        ExprBisim(e, env, stack + EvalSubs(subs, env));
        ExecCodeConcat(CompileSubs(subs), CompileExpr(e) + [SetVarSub(x, |subs|)], stack, env);
        ExecCodeConcat(CompileExpr(e), [SetVarSub(x, |subs|)], stack + EvalSubs(subs, env), env);
        var sv := EvalSubs(subs, env);
        var ve := EvalExpr(e, env);
        EvalSubsLength(subs, env);
        assert |sv| == |subs|;
        assert CompileSubs(subs) + CompileExpr(e) + [SetVarSub(x, |subs|)] ==
               CompileSubs(subs) + (CompileExpr(e) + [SetVarSub(x, |subs|)]);
        assert ExecCode(CompileSubs(subs) + (CompileExpr(e) + [SetVarSub(x, |subs|)]), stack, env) ==
               ExecCode(CompileExpr(e) + [SetVarSub(x, |subs|)], stack + sv, env);
        assert ExecCode(CompileExpr(e) + [SetVarSub(x, |subs|)], stack + sv, env) ==
               ExecCode([SetVarSub(x, |subs|)], stack + sv + [ve], env);
        assert (stack + sv + [ve])[..|stack|] == stack;
        assert (stack + sv + [ve])[|stack| .. |stack| + |sv|] == sv;
        assert (stack + sv + [ve])[|stack| + |sv|] == ve;
        assert ExecCode([SetVarSub(x, |subs|)], stack + sv + [ve], env) ==
               (stack, SetEnv(env, x, sv, ve));
      }
    }
  }

}
