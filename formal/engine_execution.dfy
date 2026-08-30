// formal/engine_execution.dfy
//
// Engine execution model: (1) the DO/QUIT call-stack discipline (routine-name
// frames, never underflow, balanced runs restore the stack), (2) error handling
// ($ETRAP recursion cap, $ECODE/$ZERROR set on error), and (3) deterministic
// label dispatch (a label resolves to a single entry line; DO ^routine resolves
// to the first label in line order).
//
// Verify with:  dafny verify formal/engine_execution.dfy

module EngineExecution {

  // ============ 1. Call stack: DO/QUIT discipline ============
  // DO pushes the callee's routine name onto the call stack; QUIT (or a
  // subroutine return) pops it. The stack never underflows, and a balanced
  // DO/QUIT restores it exactly.
  type Stack = seq<string>

  function Do(stack: Stack, name: string): Stack
  {
    stack + [name]
  }

  function Quit(stack: Stack): Stack
  {
    if |stack| == 0 then stack else stack[..|stack| - 1]
  }

  lemma DoQuitBalanced(stack: Stack, name: string)
    ensures Quit(Do(stack, name)) == stack
  {
  }

  lemma QuitNoUnderflow(stack: Stack)
    ensures |Quit(stack)| <= |stack|
  {
  }

  lemma DoIncrementsDepth(stack: Stack, name: string)
    ensures |Do(stack, name)| == |stack| + 1
  {
  }

  lemma QuitDecrementsDepth(stack: Stack)
    requires |stack| > 0
    ensures |Quit(stack)| == |stack| - 1
  {
  }

  // ============ 2. Error handling: $ETRAP cap, $ECODE/$ZERROR ============
  const MaxEtrapDepth: int := 10

  // Entering the trap increments the depth, but never past the cap.
  function TrapEnter(depth: int): int
  {
    if depth < MaxEtrapDepth then depth + 1 else MaxEtrapDepth
  }

  lemma TrapEnterBounded(depth: int)
    requires 0 <= depth <= MaxEtrapDepth
    ensures 0 <= TrapEnter(depth) <= MaxEtrapDepth
  {
  }

  // Repeated trap re-entry stays bounded (a self-trapping $ETRAP terminates).
  function TrapN(depth: int, k: nat): int
  {
    if k == 0 then depth else TrapEnter(TrapN(depth, k - 1))
  }

  lemma TrapNBounded(depth: int, k: nat)
    requires 0 <= depth <= MaxEtrapDepth
    ensures TrapN(depth, k) <= MaxEtrapDepth
  {
    if k == 0 {
    } else {
      TrapNBounded(depth, k - 1);
    }
  }

  // On error, $ECODE is set to a non-empty code and $ZERROR to the message.
  function ErrorCode(msg: string): string
  {
    "M9999:" + msg
  }

  lemma EcodeNonEmpty(msg: string)
    ensures ErrorCode(msg) != ""
  {
  }

  // ============ 3. Label dispatch: deterministic entry point ============
  // A routine's label table maps a label to a line index. Dispatch is a pure
  // function: the same label always yields the same entry line.
  type Labels = string -> int

  function Dispatch(labels: Labels, lbl: string): int
  {
    labels(lbl)
  }

  // A valid label table maps every label to a line index within the routine.
  lemma DispatchInBounds(labels: Labels, lbl: string, numLines: int)
    requires numLines > 0
    requires forall l :: 0 <= labels(l) < numLines
    ensures 0 <= Dispatch(labels, lbl) < numLines
  {
  }

  // DO ^routine with no label resolves to the first label (smallest line
  // index). For labels listed in ascending line order, the first is minimal.
  datatype LabelEntry = Entry(line: int, name: string)

  function FirstLine(entries: seq<LabelEntry>): int
    requires |entries| > 0
  {
    entries[0].line
  }

  // Adjacent sortedness implies the first entry is <= every entry.
  lemma SortedLe(entries: seq<LabelEntry>, i: nat)
    requires i < |entries|
    requires forall j | 0 <= j < |entries| - 1 :: entries[j].line <= entries[j + 1].line
    ensures entries[0].line <= entries[i].line
    decreases i
  {
    if i == 0 {
    } else {
      SortedLe(entries, i - 1);
      assert entries[i - 1].line <= entries[i].line;
    }
  }

  lemma FirstIsMinimal(entries: seq<LabelEntry>)
    requires |entries| > 0
    requires forall i | 0 <= i < |entries| - 1 :: entries[i].line <= entries[i + 1].line
    ensures forall i | 0 <= i < |entries| :: FirstLine(entries) <= entries[i].line
  {
    forall i | 0 <= i < |entries| {
      SortedLe(entries, i);
    }
  }

}
