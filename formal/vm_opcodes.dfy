// formal/vm_opcodes.dfy
//
// Concrete stack-effect table for the NimM bytecode VM (bytecode.nim Opcode),
// and the compiler's emission invariants for the real instruction set:
// every compiled expression leaves one value and never underflows, every
// compiled statement leaves the stack unchanged and never underflows. Covers
// subscripts (opPushVarSub/opSetVarSub), calls/args (opCall/opWrite), and
// control flow. Complements bytecode_stack.dfy (abstract subset) and
// bytecode_bisim.dfy (core-language compiler correctness).
//
// Verify with:  dafny verify formal/vm_opcodes.dfy

module VMOpcodes {

  datatype Op =
    | PushConst | PushVar | PushGlobal | PushSvar | Dup
    | SetVar | SetGlobal | SetSvar | Pop
    | PushVarSub(n: int) | PushGlobalSub(n: int) | SetVarSub(n: int) | SetGlobalSub(n: int)
    | Binop | Cmp | Concat | Piece | Extract | Length
    | Jump | JumpIfFalse | JumpIfTrue
    | Call(argc: int)
    | Return | Quit
    | Write(argc: int) | WriteNl | WriteFf
    | ForInit | ForNext | NewScope | PopScope
    | LockAcquire | LockRelease | LockReleaseAll
    | Tstart | Tcommit | Trollback
    | Xecute | Zloadxml | Kill | Break | Goto | CallLabel | Merge | Nop

  function Pops(op: Op): int
  {
    match op
    case PushConst => 0
    case PushVar => 0
    case PushGlobal => 0
    case PushSvar => 0
    case Dup => 0
    case SetVar => 1
    case SetGlobal => 1
    case SetSvar => 1
    case Pop => 1
    case PushVarSub(n) => n
    case PushGlobalSub(n) => n
    case SetVarSub(n) => n + 1
    case SetGlobalSub(n) => n + 1
    case Binop => 2
    case Cmp => 2
    case Concat => 2
    case Piece => 4
    case Extract => 3
    case Length => 1
    case Jump => 0
    case JumpIfFalse => 1
    case JumpIfTrue => 1
    case Call(argc) => argc
    case Return => 0
    case Quit => 0
    case Write(argc) => argc
    case WriteNl => 0
    case WriteFf => 0
    case ForInit => 0
    case ForNext => 2
    case NewScope => 0
    case PopScope => 0
    case LockAcquire => 0
    case LockRelease => 0
    case LockReleaseAll => 0
    case Tstart => 0
    case Tcommit => 0
    case Trollback => 0
    case Xecute => 0
    case Zloadxml => 3
    case Kill => 0
    case Break => 0
    case Goto => 0
    case CallLabel => 0
    case Merge => 0
    case Nop => 0
  }

  function Pushes(op: Op): int
  {
    match op
    case PushConst => 1
    case PushVar => 1
    case PushGlobal => 1
    case PushSvar => 1
    case Dup => 1
    case SetVar => 0
    case SetGlobal => 0
    case SetSvar => 0
    case Pop => 0
    case PushVarSub(n) => 1
    case PushGlobalSub(n) => 1
    case SetVarSub(n) => 0
    case SetGlobalSub(n) => 0
    case Binop => 1
    case Cmp => 1
    case Concat => 1
    case Piece => 1
    case Extract => 1
    case Length => 1
    case Jump => 0
    case JumpIfFalse => 0
    case JumpIfTrue => 0
    case Call(argc) => 1
    case Return => 0
    case Quit => 0
    case Write(argc) => 0
    case WriteNl => 0
    case WriteFf => 0
    case ForInit => 2
    case ForNext => 2
    case NewScope => 0
    case PopScope => 0
    case LockAcquire => 0
    case LockRelease => 0
    case LockReleaseAll => 0
    case Tstart => 0
    case Tcommit => 0
    case Trollback => 0
    case Xecute => 1
    case Zloadxml => 1
    case Kill => 0
    case Break => 0
    case Goto => 0
    case CallLabel => 0
    case Merge => 0
    case Nop => 0
  }

  function Delta(op: Op): int { Pushes(op) - Pops(op) }

  function Net(prog: seq<Op>): int
  {
    if |prog| == 0 then 0 else Delta(prog[0]) + Net(prog[1..])
  }

  lemma NetConcat(a: seq<Op>, b: seq<Op>)
    ensures Net(a + b) == Net(a) + Net(b)
    decreases |a|
  {
    if |a| == 0 {
      assert a == [];
      assert a + b == b;
    } else {
      NetConcat(a[1..], b);
      reveal Net;
      assert (a + b)[0] == a[0];
      assert (a + b)[1..] == a[1..] + b;
      assert Net(a + b) == Delta(a[0]) + Net(a[1..] + b);
      assert Net(a) == Delta(a[0]) + Net(a[1..]);
    }
  }

  predicate NoUnderflowFrom(prog: seq<Op>, base: int)
  {
    forall i | 0 <= i < |prog| :: base + Net(prog[..i]) >= Pops(prog[i])
  }

  predicate NoUnderflow(prog: seq<Op>) { NoUnderflowFrom(prog, 0) }

  lemma NoUnderflowFromMonotone(prog: seq<Op>, base: int, extra: int)
    requires extra >= 0 && NoUnderflowFrom(prog, base)
    ensures NoUnderflowFrom(prog, base + extra)
  {
  }

  lemma ConcatNoUnderflow(a: seq<Op>, b: seq<Op>)
    requires NoUnderflow(a)
    requires NoUnderflowFrom(b, Net(a))
    ensures NoUnderflow(a + b)
  {
    NetConcat(a, b);
    forall i | 0 <= i < |a| + |b|
      ensures Net((a + b)[..i]) >= Pops((a + b)[i])
    {
      if i < |a| {
        assert (a + b)[..i] == a[..i];
        assert (a + b)[i] == a[i];
      } else {
        assert (a + b)[..i] == a + b[..i - |a|];
        assert (a + b)[i] == b[i - |a|];
        NetConcat(a, b[..i - |a|]);
      }
    }
  }

  lemma SingleOpSafe(op: Op)
    ensures NoUnderflowFrom([op], Pops(op))
  {
  }

  predicate IsExpr(prog: seq<Op>) { NoUnderflow(prog) && Net(prog) == 1 }
  predicate IsStmt(prog: seq<Op>) { NoUnderflow(prog) && Net(prog) == 0 }

  // --- Compiler emission invariants (the concrete opcode set) ---

  // A literal or variable push.
  lemma PushIsExpr()
    ensures IsExpr([PushConst]) && IsExpr([PushVar])
  {
  }

  // Binary expression: e1 ++ e2 ++ [Binop].
  function CompileBinop(a: seq<Op>, b: seq<Op>): seq<Op> { a + b + [Binop] }

  lemma BinopIsExpr(a: seq<Op>, b: seq<Op>)
    requires IsExpr(a) && IsExpr(b)
    ensures IsExpr(CompileBinop(a, b))
  {
    NetConcat(a, b);
    assert Net(a + b) == 2;
    NoUnderflowFromMonotone(b, 0, Net(a));
    ConcatNoUnderflow(a, b);
    SingleOpSafe(Binop);
    ConcatNoUnderflow(a + b, [Binop]);
    NetConcat(a + b, [Binop]);
  }

  // Subscripted read: n subscript expressions ++ [PushVarSub(n)].
  function CompileSubscriptRead(n: int, subs: seq<Op>): seq<Op> { subs + [PushVarSub(n)] }

  lemma SubscriptReadIsExpr(subs: seq<Op>, n: int)
    requires n >= 0 && Net(subs) == n && NoUnderflow(subs)
    ensures IsExpr(CompileSubscriptRead(n, subs))
  {
    SingleOpSafe(PushVarSub(n));
    ConcatNoUnderflow(subs, [PushVarSub(n)]);
    NetConcat(subs, [PushVarSub(n)]);
  }

  // Assignment: expr ++ [SetVar].
  function CompileSetVar(e: seq<Op>): seq<Op> { e + [SetVar] }

  lemma SetVarIsStmt(e: seq<Op>)
    requires IsExpr(e)
    ensures IsStmt(CompileSetVar(e))
  {
    SingleOpSafe(SetVar);
    ConcatNoUnderflow(e, [SetVar]);
    NetConcat(e, [SetVar]);
  }

  // Subscripted write: n subscript expressions ++ value expr ++ [SetVarSub(n)].
  function CompileSubscriptWrite(n: int, subs: seq<Op>, value: seq<Op>): seq<Op>
  {
    subs + value + [SetVarSub(n)]
  }

  lemma SubscriptWriteIsStmt(subs: seq<Op>, value: seq<Op>, n: int)
    requires n >= 0 && Net(subs) == n && NoUnderflow(subs)
    requires IsExpr(value)
    ensures IsStmt(CompileSubscriptWrite(n, subs, value))
  {
    NetConcat(subs, value);
    assert Net(subs + value) == n + 1;
    NoUnderflowFromMonotone(value, 0, Net(subs));
    ConcatNoUnderflow(subs, value);
    SingleOpSafe(SetVarSub(n));
    ConcatNoUnderflow(subs + value, [SetVarSub(n)]);
    NetConcat(subs + value, [SetVarSub(n)]);
  }

  // Write: argc argument expressions ++ [Write(argc)].
  function CompileWrite(argc: int, args: seq<Op>): seq<Op> { args + [Write(argc)] }

  lemma WriteIsStmt(args: seq<Op>, argc: int)
    requires argc >= 0 && Net(args) == argc && NoUnderflow(args)
    ensures IsStmt(CompileWrite(argc, args))
  {
    SingleOpSafe(Write(argc));
    ConcatNoUnderflow(args, [Write(argc)]);
    NetConcat(args, [Write(argc)]);
  }

  // Function call: argc argument expressions ++ [Call(argc)] leaves the result.
  function CompileCall(argc: int, args: seq<Op>): seq<Op> { args + [Call(argc)] }

  lemma CallIsExpr(args: seq<Op>, argc: int)
    requires argc >= 0 && Net(args) == argc && NoUnderflow(args)
    ensures IsExpr(CompileCall(argc, args))
  {
    SingleOpSafe(Call(argc));
    ConcatNoUnderflow(args, [Call(argc)]);
    NetConcat(args, [Call(argc)]);
  }

  // Sequencing two statements.
  lemma SeqIsStmt(a: seq<Op>, b: seq<Op>)
    requires IsStmt(a) && IsStmt(b)
    ensures IsStmt(a + b)
  {
    NoUnderflowFromMonotone(b, 0, Net(a));
    ConcatNoUnderflow(a, b);
    NetConcat(a, b);
  }

  // Control-flow and scope opcodes are net-0 statements (safe from empty stack).
  lemma NetZeroOpIsStmt(op: Op)
    requires Pops(op) == 0 && Pushes(op) == 0
    ensures IsStmt([op])
  {
  }

}
