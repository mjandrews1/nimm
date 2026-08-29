// formal/bytecode_stack.dfy
//
// Formal model of the NimM bytecode VM's operand-stack discipline
// (bytecode.nim / vm.nim). Each opcode has a stack effect (Pops/Pushes); a
// program is safe iff the VM never pops below the stack bottom.
//
// The compiler is modeled by its compositional invariants: every compiled
// *expression* leaves exactly one value and never underflows; every compiled
// *statement* leaves the stack unchanged and never underflows. These
// compose (concatenation, binary ops, subscripts, sequencing), so a whole
// program never underflows.
//
// Verify with:  dafny verify formal/bytecode_stack.dfy

module BytecodeStack {

  datatype Op =
    | Push            // net +1
    | SetVar          // pop 1 (net -1)
    | Binop           // pop 2, push 1 (net -1)
    | PushVarSub(n: int)   // pop n subscripts, push 1 (net 1-n)
    | SetVarSub(n: int)    // pop value + n subscripts (net -(n+1))
    | Write(argc: int)     // pop argc values (net -argc)
    | Jump            // net 0

  function Pops(op: Op): int
  {
    match op
    case Push => 0
    case SetVar => 1
    case Binop => 2
    case PushVarSub(n) => n
    case SetVarSub(n) => n + 1
    case Write(argc) => argc
    case Jump => 0
  }

  function Pushes(op: Op): int
  {
    match op
    case Push => 1
    case SetVar => 0
    case Binop => 1
    case PushVarSub(n) => 1
    case SetVarSub(n) => 0
    case Write(argc) => 0
    case Jump => 0
  }

  function Delta(op: Op): int { Pushes(op) - Pops(op) }

  // Net effect of a program.
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
      assert Net(a[1..] + b) == Net(a[1..]) + Net(b);
      assert Net(a) == Delta(a[0]) + Net(a[1..]);
    }
  }

  // No underflow, starting from a stack of depth `base`.
  predicate NoUnderflowFrom(prog: seq<Op>, base: int)
  {
    forall i | 0 <= i < |prog| :: base + Net(prog[..i]) >= Pops(prog[i])
  }

  predicate NoUnderflow(prog: seq<Op>) { NoUnderflowFrom(prog, 0) }

  // More base slack only helps.
  lemma NoUnderflowFromMonotone(prog: seq<Op>, base: int, extra: int)
    requires extra >= 0 && NoUnderflowFrom(prog, base)
    ensures NoUnderflowFrom(prog, base + extra)
  {
  }

  // Composition: safe a, then b safe from a's net, is safe overall.
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

  // A single op is safe from a base that covers its pops.
  lemma SingleOpSafe(op: Op)
    ensures NoUnderflowFrom([op], Pops(op))
  {
  }

  // --- Compiler invariants -----------------------------------------------

  predicate IsExpr(prog: seq<Op>) { NoUnderflow(prog) && Net(prog) == 1 }
  predicate IsStmt(prog: seq<Op>) { NoUnderflow(prog) && Net(prog) == 0 }

  // A literal compiles to a single Push.
  lemma PushIsExpr()
    ensures IsExpr([Push])
  {
  }

  // Binary op: compile(left) ++ compile(right) ++ [Binop].
  function CompileBinop(a: seq<Op>, b: seq<Op>): seq<Op> { a + b + [Binop] }

  lemma BinopIsExpr(a: seq<Op>, b: seq<Op>)
    requires IsExpr(a) && IsExpr(b)
    ensures IsExpr(CompileBinop(a, b))
  {
    // Net(a+b) = 1 + 1 = 2.
    NetConcat(a, b);
    assert Net(a + b) == 2;
    // a safe from 0; b safe from 1 (b is IsExpr, so safe from 0, hence from 1).
    NoUnderflowFromMonotone(b, 0, Net(a));
    ConcatNoUnderflow(a, b);
    // [Binop] pops 2, safe from depth 2.
    SingleOpSafe(Binop);
    ConcatNoUnderflow(a + b, [Binop]);
    // Net(a + b + [Binop]) = 2 + (-1) = 1.
    NetConcat(a + b, [Binop]);
  }

  // Assignment: compile(expr) ++ [SetVar].
  function CompileSetVar(e: seq<Op>): seq<Op> { e + [SetVar] }

  lemma SetVarIsStmt(e: seq<Op>)
    requires IsExpr(e)
    ensures IsStmt(CompileSetVar(e))
  {
    SingleOpSafe(SetVar);
    ConcatNoUnderflow(e, [SetVar]);
    NetConcat(e, [SetVar]);
  }

  // Subscripted read: n subscript expressions ++ [PushVarSub(n)].
  function CompileSubscriptRead(n: int, subs: seq<Op>): seq<Op>
  {
    subs + [PushVarSub(n)]
  }

  lemma SubscriptReadIsExpr(subs: seq<Op>, n: int)
    requires |subs| == n && Net(subs) == n && NoUnderflow(subs)
    ensures IsExpr(CompileSubscriptRead(n, subs))
  {
    SingleOpSafe(PushVarSub(n));
    ConcatNoUnderflow(subs, [PushVarSub(n)]);
    NetConcat(subs, [PushVarSub(n)]);
  }

  // Sequencing: two statements.
  lemma SeqIsStmt(a: seq<Op>, b: seq<Op>)
    requires IsStmt(a) && IsStmt(b)
    ensures IsStmt(a + b)
  {
    NoUnderflowFromMonotone(b, 0, Net(a));
    ConcatNoUnderflow(a, b);
    NetConcat(a, b);
  }

}
