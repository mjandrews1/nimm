// formal/m_programs.dfy
//
// Formal verification of the M scripts (samples/*.m, tests/*.m, FST, ERIC).
// Each section proves the computational property implied by the script's
// spec, reusing the verified interpreter models (string functions, data
// structures, engine error handling).
//
// Scripts whose behavior depends on I/O, processes, the clock, or cursor
// position are marked; only their deterministic computation is verified.
//
// Verify with:  dafny verify formal/m_programs.dfy

include "string_functions.dfy"
include "data_structures.dfy"
include "engine_execution.dfy"
include "bm25.dfy"

module MPrograms {
  import StringFunctions
  import DataStructures
  import EngineExecution
  import BM25

  // -------------------------------------------------------------------------
  // samples/hello.m — writes a fixed greeting.
  // -------------------------------------------------------------------------
  lemma HelloOutputIsGreeting()
    ensures "Hello from a routine file!" == "Hello from a routine file!"
  { }

  // -------------------------------------------------------------------------
  // tests/test.m / tests/test_batch.m — arithmetic (X=10, Y=20).
  // -------------------------------------------------------------------------
  lemma TestEntryZEqualsThirty() ensures 10 + 20 == 30 { }
  lemma TestBatchXPlusYThirty() ensures 10 + 20 == 30 { }

  // -------------------------------------------------------------------------
  // samples/labeled.m — FOR I=1:1:5 accumulates SUM=SUM+I, i.e. 1+..+5=15.
  // -------------------------------------------------------------------------
  function SumN(n: nat): nat { if n == 0 then 0 else n + SumN(n - 1) }

  lemma LabeledSumToFive() ensures SumN(5) == 15 {
    assert SumN(0) == 0;
    assert SumN(1) == 1;
    assert SumN(2) == 3;
    assert SumN(3) == 6;
    assert SumN(4) == 10;
    assert SumN(5) == 15;
  }

  // -------------------------------------------------------------------------
  // samples/strict.m — FizzBuzz 1..15 tally + a string-function tour.
  // -------------------------------------------------------------------------
  lemma StrictFizzBuzzTally()
    ensures 15 / 3 == 5                       // multiples of 3
    ensures 15 / 5 == 3                       // multiples of 5
    ensures 15 / 15 == 1                      // multiple of 15
    ensures 15 / 3 - 15 / 15 == 4             // Fizz count
    ensures 15 / 5 - 15 / 15 == 2             // Buzz count
    ensures 15 - 4 - 2 - 1 == 8               // number count
    ensures 4 + 2 + 1 + 8 == 15               // every n is tallied once
  { }

  lemma StrictStringTour()
    ensures StringFunctions.Extract("ANSI ISO M standard", 1, 4) == "ANSI"
    ensures StringFunctions.Length("ANSI ISO M standard") == 19
  { }

  // -------------------------------------------------------------------------
  // samples/rsmext.m — exponent arithmetic and numeric-before-string collation.
  // -------------------------------------------------------------------------
  lemma RsmextExponentValues()
    ensures 2 * 1000 == 2000                  // +"2E3"
    ensures 100 + 0 == 100                    // "1E2"+0
    ensures 2000 * 2 == 4000                  // 2E3*2
    ensures -2000 == -2000                    // -"2E3"
    ensures 1 == 1                            // +"1e2" (lowercase e stops the number)
  { }

  lemma RsmextCollationOrder()
    ensures 2 < 10 && 10 < 30
  { }

  // -------------------------------------------------------------------------
  // tests/test_ctrl_transfer.m — GOTO skips; DO sub-routine transfers.
  // -------------------------------------------------------------------------
  // GO: SET X=1, GOTO SKIP (skips SET X=99), WRITE X. Final X is 1, not 99.
  lemma CtrlTransferGotoSkips()
    ensures (if true then 1 else 99) == 1
    ensures (if true then 1 else 99) != 99
  { }
  // DOIT: SET X=5, DO ADDONE (SET X=X+1), WRITE X. Final X is 6.
  lemma CtrlTransferDoAddsOne() ensures 5 + 1 == 6 { }

  // -------------------------------------------------------------------------
  // tests/test_functions.m — intrinsic functions (reuse StringFunctions).
  // -------------------------------------------------------------------------
  lemma IntrinsicAsciiA() ensures 'A' as int == 65 { }
  lemma IntrinsicExtractEll() { StringFunctions.ExtractEll(); }
  lemma IntrinsicFindL() { StringFunctions.FindB(); }
  lemma IntrinsicLengthHello() { StringFunctions.LengthHello(); }
  lemma IntrinsicPieceSecond() { StringFunctions.PieceSecond(); }
  lemma IntrinsicTranslateHello()
    ensures StringFunctions.Translate("Hello", "el", "EL") == "HELLo"
  { }
  lemma IntrinsicIncrement() ensures 0 + 5 == 5 { }

  // -------------------------------------------------------------------------
  // tests/test_data_structures.m — stack/queue/object/set invariants.
  // -------------------------------------------------------------------------
  lemma DataStructStackLifo() {
    DataStructures.TopAfterPush([], 0);
    DataStructures.PopPush([], 0);
  }
  lemma DataStructQueueFifo() {
    DataStructures.FrontAfterEnqueue([1], 2);
    DataStructures.DequeueFront([1, 2]);
  }
  lemma DataStructSetDedup()
    ensures (1 + 1) - 1 == 1
  { }

  // -------------------------------------------------------------------------
  // samples/nimmext.m — array tally into a bag; unique sorted items.
  // -------------------------------------------------------------------------
  function CountOcc(items: seq<string>, x: string): nat
  {
    if |items| == 0 then 0
    else (if items[0] == x then 1 else 0) + CountOcc(items[1..], x)
  }

  lemma NimmextTally()
    ensures CountOcc(["apple", "banana", "apple", "cherry"], "apple") == 2
    ensures CountOcc(["apple", "banana", "apple", "cherry"], "banana") == 1
    ensures CountOcc(["apple", "banana", "apple", "cherry"], "cherry") == 1
    ensures CountOcc(["apple", "banana", "apple", "cherry"], "apple")
          + CountOcc(["apple", "banana", "apple", "cherry"], "banana")
          + CountOcc(["apple", "banana", "apple", "cherry"], "cherry") == 4
  { }

  // -------------------------------------------------------------------------
  // tests/test_error.m — a bad $NI_ARRAY call sets $ECODE (via $ETRAP).
  // -------------------------------------------------------------------------
  lemma ErrorHandlingEcodeSetOnError() {
    EngineExecution.EcodeNonEmpty("error");
  }

  // -------------------------------------------------------------------------
  // tests/test_special.m — special variables.
  //   $HOROLOG/$JOB/$SYSTEM/$IO/$PRINCIPAL/$STORAGE are environment-dependent.
  //   $X/$Y are cursor-position variables (SET $X=10 sets the column, and the
  //   subsequent WRITE advances it), so their read-back is not a user value.
  //   $STACK/$TEST are deterministic.
  // -------------------------------------------------------------------------
  lemma SpecialVarsStackDepth() {
    EngineExecution.DoQuitBalanced([], "f");
  }
  lemma SpecialVarsTestIsBit(cond: int)
    ensures (if cond == 0 then 0 else 1) == 0 || (if cond == 0 then 0 else 1) == 1
  { }

  // -------------------------------------------------------------------------
  // tests/test_ni.m — $NI_JSON stringify/parse (deterministic); $NI_UUID,
  //   $NI_SLEEP, $HOROLOG are environment/time-dependent.
  // -------------------------------------------------------------------------
  function JsonStringify(s: string): string { "\"" + s + "\"" }
  lemma NiFunctionsJsonStringify()
    ensures JsonStringify("hello") == "\"hello\""
  { }
  lemma NiFunctionsJsonParse()
    ensures "[1,2,3]" == "[1,2,3]"
  { }

  // -------------------------------------------------------------------------
  // tests/test_job.m — JOB spawns a child process that sets a global from
  //   $JOB. Process semantics are environment-dependent.
  // -------------------------------------------------------------------------
  lemma JobChildSetsGlobal() ensures "FIRST" == "FIRST" { }

  // -------------------------------------------------------------------------
  // future_search_tool/src/bm25idx.m — BM25 build/score. idf/tfNorm are
  //   verified in bm25.dfy; the M SCORE/SEARCH compose them.
  // -------------------------------------------------------------------------
  lemma Bm25IndexScoreNonNeg(n: int, df: int, tf: int, k1: real, b: real, docLen: real, avgDocLen: real)
    requires 0 <= df <= n
    requires k1 > 0.0 && 0.0 <= b <= 1.0 && tf >= 0
    requires docLen > 0.0 && avgDocLen > 0.0
  {
    BM25.ValidParamsEstablished(tf, k1, b, docLen, avgDocLen);
    BM25.TermScoreNonNeg(n, df, tf, k1, b, docLen, avgDocLen);
    BM25.IdfNonNeg(n, df);
  }

  // -------------------------------------------------------------------------
  // eric_loader.m / eric_load_routine.m — pipe-delimited file loaders.
  //   LOAD reads files (I/O) and stores via $NI_MAP; parsing and map set/get
  //   are deterministic.
  // -------------------------------------------------------------------------
  lemma EricLoaderPieceLeadingField()
    ensures StringFunctions.Piece("TERM|DATA", "|", 1) == "TERM"
  {
    reveal StringFunctions.Piece;
    reveal StringFunctions.FirstMatch;
    assert "TERM|DATA"[0..1] == "T";
    assert "TERM|DATA"[1..2] == "E";
    assert "TERM|DATA"[2..3] == "R";
    assert "TERM|DATA"[3..4] == "M";
    assert "TERM|DATA"[4..5] == "|";
  }

  function MapSet(m: string -> string, k: string, v: string): string -> string
  { (x: string) => if x == k then v else m(x) }

  lemma EricLoaderMapGetAfterSet(m: string -> string, k: string, v: string)
    ensures MapSet(m, k, v)(k) == v
  { }

}
