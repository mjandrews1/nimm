// formal/bytecode_bisim.dfy
//
// Compiler correctness (bisimulation) for the NimM bytecode compiler over a
// core language: compiled bytecode, run on the abstract stack machine,
// produces the same result as evaluating the AST directly.
//
// Core language:
//   Expr ::= Const(n) | Var(x) | Bin(op, e1, e2)
//   Stmt ::= Assign(x, e) | Seq(s1, s2) | Skip
//
// Theorems:
//   ExprBisim  ExecCode(CompileExpr(e), stack, env) == (stack ++ [Eval(e)], env)
//   StmtBisim  ExecCode(CompileStmt(s), stack, env) == (stack, Exec(s, env))
//
// (This is the Phase 2 "C2 mode-parity" property, complementing
// bytecode_stack.dfy which proves the operand-stack discipline.)
//
// Verify with:  dafny verify formal/bytecode_bisim.dfy

module BytecodeBisim {

  datatype BinOp = Add | Sub | Mul

  function ApplyBin(op: BinOp, a: int, b: int): int
  {
    match op
    case Add => a + b
    case Sub => a - b
    case Mul => a * b
  }

  datatype Op =
    | PushConst(n: int)
    | PushVar(x: string)
    | BinopOp(op: BinOp)
    | SetVar(x: string)

  datatype Expr =
    | Const(n: int)
    | Var(x: string)
    | Bin(op: BinOp, a: Expr, b: Expr)

  datatype Stmt =
    | Assign(x: string, e: Expr)
    | Seq(a: Stmt, b: Stmt)
    | Skip

  type Env = string -> int

  // Function update for the total environment.
  function SetEnv(env: Env, x: string, v: int): Env
  {
    (y: string) => if y == x then v else env(y)
  }

  // --- AST semantics (big-step) ---
  function EvalExpr(e: Expr, env: Env): int
  {
    match e
    case Const(n) => n
    case Var(x) => env(x)
    case Bin(op, a, b) => ApplyBin(op, EvalExpr(a, env), EvalExpr(b, env))
  }

  function ExecStmt(s: Stmt, env: Env): Env
  {
    match s
    case Assign(x, e) => SetEnv(env, x, EvalExpr(e, env))
    case Seq(a, b) => ExecStmt(b, ExecStmt(a, env))
    case Skip => env
  }

  // --- Compiler ---
  function CompileExpr(e: Expr): seq<Op>
  {
    match e
    case Const(n) => [PushConst(n)]
    case Var(x) => [PushVar(x)]
    case Bin(op, a, b) => CompileExpr(a) + CompileExpr(b) + [BinopOp(op)]
  }

  function CompileStmt(s: Stmt): seq<Op>
  {
    match s
    case Assign(x, e) => CompileExpr(e) + [SetVar(x)]
    case Seq(a, b) => CompileStmt(a) + CompileStmt(b)
    case Skip => []
  }

  // --- Stack machine ---
  function Step(op: Op, stack: seq<int>, env: Env): (seq<int>, Env)
  {
    match op
    case PushConst(n) => (stack + [n], env)
    case PushVar(x) => (stack + [env(x)], env)
    case BinopOp(o) =>
      if |stack| >= 2 then
        (stack[..|stack| - 2] + [ApplyBin(o, stack[|stack| - 2], stack[|stack| - 1])], env)
      else
        (stack, env)
    case SetVar(x) =>
      if |stack| >= 1 then
        (stack[..|stack| - 1], SetEnv(env, x, stack[|stack| - 1]))
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

  // --- Sequential composition of the stack machine ---
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

  // --- Bisimulation: compiled expressions ---
  lemma ExprBisim(e: Expr, env: Env, stack: seq<int>)
    ensures ExecCode(CompileExpr(e), stack, env) == (stack + [EvalExpr(e, env)], env)
  {
    match e {
      case Const(n) => {
        assert ExecCode([PushConst(n)], stack, env) == (stack + [n], env);
      }
      case Var(x) => {
        assert ExecCode([PushVar(x)], stack, env) == (stack + [env(x)], env);
      }
      case Bin(op, a, b) => {
        var va := EvalExpr(a, env);
        var vb := EvalExpr(b, env);
        ExprBisim(a, env, stack);
        ExprBisim(b, env, stack + [va]);
        ExecCodeConcat(CompileExpr(a), CompileExpr(b) + [BinopOp(op)], stack, env);
        ExecCodeConcat(CompileExpr(b), [BinopOp(op)], stack + [va], env);
        assert CompileExpr(a) + CompileExpr(b) + [BinopOp(op)] ==
               CompileExpr(a) + (CompileExpr(b) + [BinopOp(op)]);
        assert ExecCode(CompileExpr(a) + CompileExpr(b) + [BinopOp(op)], stack, env) ==
               ExecCode(CompileExpr(b) + [BinopOp(op)], stack + [va], env);
        assert ExecCode(CompileExpr(b) + [BinopOp(op)], stack + [va], env) ==
               ExecCode([BinopOp(op)], stack + [va] + [vb], env);
        assert (stack + [va] + [vb])[..|stack|] == stack;
        assert (stack + [va] + [vb])[|stack|] == va;
        assert (stack + [va] + [vb])[|stack| + 1] == vb;
        assert ExecCode([BinopOp(op)], stack + [va] + [vb], env) ==
               (stack + [ApplyBin(op, va, vb)], env);
      }
    }
  }

  // --- Bisimulation: compiled statements ---
  lemma StmtBisim(s: Stmt, env: Env, stack: seq<int>)
    ensures ExecCode(CompileStmt(s), stack, env) == (stack, ExecStmt(s, env))
  {
    match s {
      case Assign(x, e) => {
        var ve := EvalExpr(e, env);
        ExprBisim(e, env, stack);
        ExecCodeConcat(CompileExpr(e), [SetVar(x)], stack, env);
        assert ExecCode(CompileExpr(e) + [SetVar(x)], stack, env) ==
               ExecCode([SetVar(x)], stack + [ve], env);
        assert (stack + [ve])[..|stack|] == stack;
        assert (stack + [ve])[|stack|] == ve;
        assert ExecCode([SetVar(x)], stack + [ve], env) ==
               (stack, SetEnv(env, x, ve));
      }
      case Seq(a, b) => {
        StmtBisim(a, env, stack);
        StmtBisim(b, ExecStmt(a, env), stack);
        ExecCodeConcat(CompileStmt(a), CompileStmt(b), stack, env);
        assert ExecCode(CompileStmt(a) + CompileStmt(b), stack, env) ==
               ExecCode(CompileStmt(b), ExecCode(CompileStmt(a), stack, env).0,
                        ExecCode(CompileStmt(a), stack, env).1);
        assert ExecCode(CompileStmt(a), stack, env) == (stack, ExecStmt(a, env));
        assert ExecCode(CompileStmt(b), stack, ExecStmt(a, env)) ==
               (stack, ExecStmt(b, ExecStmt(a, env)));
      }
      case Skip => {
      }
    }
  }

}
