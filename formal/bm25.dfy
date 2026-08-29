// formal/bm25.dfy
//
// Formal model of Okapi BM25 (future_search_tool/src/bm25.nim).
//
// score = idf * tfNorm, where
//   idf    = log((N - df + 0.5) / (df + 0.5) + 1.0)      (N = doc count)
//   tfNorm = tf * (k1 + 1) / (tf + k1 * (1 - b + b * dl / avgdl))
//
// Proved here (the parts that are pure arithmetic, i.e. where rounding,
// division-by-zero and saturation bugs live):
//   1. idf >= 0  (a term in df of N docs never gets negative weight)
//   2. tfNorm >= 0  (no negative scores)
//   3. tfNorm is monotone non-decreasing in tf (more occurrences of a query
//      term in a document never lowers its score)
//
// Verify with:  dafny verify formal/bm25.dfy

module BM25 {

  // Arithmetic helpers (Dafny needs these facts stated explicitly to combine
  // them inside larger expressions).
  lemma MulPos(x: real, y: real)
    requires x > 0.0 && y > 0.0
    ensures x * y > 0.0
  { }

  lemma MulNonNeg(x: real, y: real)
    requires x >= 0.0 && y > 0.0
    ensures x * y >= 0.0
  { }

  lemma MulPosNonNeg(x: real, y: real)
    requires x > 0.0 && y >= 0.0
    ensures x * y >= 0.0
  { }

  lemma MulNonNegNonNeg(x: real, y: real)
    requires x >= 0.0 && y >= 0.0
    ensures x * y >= 0.0
  { }

  lemma DivNonNeg(x: real, y: real)
    requires x >= 0.0 && y > 0.0
    ensures x / y >= 0.0
  { }

  lemma DivPos(x: real, y: real)
    requires x > 0.0 && y > 0.0
    ensures x / y > 0.0
  { }

  // Natural logarithm — opaque primitive (Dafny has no built-in real log).
  function Log(x: real): real

  lemma {:axiom} LogNonNeg(x: real)
    requires x >= 1.0
    ensures Log(x) >= 0.0

  // IDF factor. Requires a valid df (a term cannot appear in more documents
  // than there are documents).
  function Idf(n: int, df: int): real
    requires 0 <= df <= n
  {
    Log((n as real - df as real + 0.5) / (df as real + 0.5) + 1.0)
  }

  // idf is non-negative.
  lemma IdfNonNeg(n: int, df: int)
    requires 0 <= df <= n
    ensures Idf(n, df) >= 0.0
  {
    LogNonNeg((n as real - df as real + 0.5) / (df as real + 0.5) + 1.0);
  }

  // Length-normalization factor 1 - b + b*dl/avgdl.
  function LengthFactor(b: real, docLen: real, avgDocLen: real): real
    requires avgDocLen > 0.0
  {
    1.0 - b + b * docLen / avgDocLen
  }

  // The length factor is strictly positive whenever the document has positive
  // length.
  lemma LengthFactorPositive(b: real, docLen: real, avgDocLen: real)
    requires 0.0 <= b <= 1.0 && docLen > 0.0 && avgDocLen > 0.0
    ensures LengthFactor(b, docLen, avgDocLen) > 0.0
  {
    if b == 1.0 {
      DivPos(docLen, avgDocLen);
      assert 1.0 - b == 0.0;
      assert b * docLen == docLen;
      assert b * docLen / avgDocLen == docLen / avgDocLen;
      assert LengthFactor(b, docLen, avgDocLen) == docLen / avgDocLen;
      assert LengthFactor(b, docLen, avgDocLen) > 0.0;
    } else {
      assert 1.0 - b > 0.0;
      assert b >= 0.0;
      MulNonNeg(b, docLen);
      assert b * docLen >= 0.0;
      DivNonNeg(b * docLen, avgDocLen);
      assert b * docLen / avgDocLen >= 0.0;
      assert LengthFactor(b, docLen, avgDocLen) > 0.0;
    }
  }

  // The tfNorm denominator is positive.
  lemma DenomPositive(tf: int, k1: real, b: real, docLen: real, avgDocLen: real)
    requires k1 > 0.0 && 0.0 <= b <= 1.0 && tf >= 0
    requires docLen > 0.0 && avgDocLen > 0.0
    ensures tf as real + k1 * LengthFactor(b, docLen, avgDocLen) > 0.0
  {
    LengthFactorPositive(b, docLen, avgDocLen);
    MulPos(k1, LengthFactor(b, docLen, avgDocLen));
    assert k1 * LengthFactor(b, docLen, avgDocLen) > 0.0;
  }

  // Well-formedness of the tfNorm parameters: k1/b sane, positive document
  // length, positive length factor, positive denominator.
  predicate ValidParams(tf: int, k1: real, b: real, docLen: real, avgDocLen: real)
  {
    k1 > 0.0 && 0.0 <= b <= 1.0 && tf >= 0 && docLen > 0.0 && avgDocLen > 0.0 &&
    LengthFactor(b, docLen, avgDocLen) > 0.0 &&
    tf as real + k1 * LengthFactor(b, docLen, avgDocLen) > 0.0
  }

  // The natural assumptions (k1/b sane, positive doc/avg length, tf >= 0)
  // imply ValidParams.
  lemma ValidParamsEstablished(tf: int, k1: real, b: real, docLen: real, avgDocLen: real)
    requires k1 > 0.0 && 0.0 <= b <= 1.0 && tf >= 0
    requires docLen > 0.0 && avgDocLen > 0.0
    ensures ValidParams(tf, k1, b, docLen, avgDocLen)
  {
    LengthFactorPositive(b, docLen, avgDocLen);
    DenomPositive(tf, k1, b, docLen, avgDocLen);
  }

  // TF normalization factor.
  function TfNorm(tf: int, k1: real, b: real, docLen: real, avgDocLen: real): real
    requires ValidParams(tf, k1, b, docLen, avgDocLen)
  {
    (tf as real * (k1 + 1.0)) / (tf as real + k1 * LengthFactor(b, docLen, avgDocLen))
  }

  // tfNorm is non-negative.
  lemma TfNormNonNeg(tf: int, k1: real, b: real, docLen: real, avgDocLen: real)
    requires ValidParams(tf, k1, b, docLen, avgDocLen)
    ensures TfNorm(tf, k1, b, docLen, avgDocLen) >= 0.0
  {
    assert tf as real >= 0.0;
    assert k1 + 1.0 > 0.0;
    MulNonNeg(tf as real, k1 + 1.0);
    assert tf as real * (k1 + 1.0) >= 0.0;
    DivNonNeg(tf as real * (k1 + 1.0), tf as real + k1 * LengthFactor(b, docLen, avgDocLen));
  }

  // tfNorm is monotone non-decreasing in tf: a document with more occurrences
  // of a term scores at least as high, all else equal.
  //
  // f(t) = t*A/(t+C) with A = k1+1 > 0, C = k1*LengthFactor > 0, so
  // f(t2) - f(t1) = A*C*(t2-t1) / ((t2+C)(t1+C)) >= 0 for t2 >= t1.
  lemma TfNormMonotone(t1: int, t2: int, k1: real, b: real, docLen: real, avgDocLen: real)
    requires 0 <= t1 <= t2
    requires ValidParams(t1, k1, b, docLen, avgDocLen)
    requires ValidParams(t2, k1, b, docLen, avgDocLen)
    ensures TfNorm(t1, k1, b, docLen, avgDocLen) <= TfNorm(t2, k1, b, docLen, avgDocLen)
  {
    var A := k1 + 1.0;
    var C := k1 * LengthFactor(b, docLen, avgDocLen);
    MulPos(k1, LengthFactor(b, docLen, avgDocLen));
    assert C > 0.0;
    assert A > 0.0;
    assert t1 as real + C > 0.0;
    assert t2 as real + C > 0.0;
    assert t2 as real - t1 as real >= 0.0;
    MulPos(A, C);
    assert A * C > 0.0;
    MulPosNonNeg(A * C, t2 as real - t1 as real);
    assert A * C * (t2 as real - t1 as real) >= 0.0;
    MulPos(t2 as real + C, t1 as real + C);
    assert (t2 as real + C) * (t1 as real + C) > 0.0;
    assert TfNorm(t2, k1, b, docLen, avgDocLen) - TfNorm(t1, k1, b, docLen, avgDocLen)
           == A * C * (t2 as real - t1 as real) / ((t2 as real + C) * (t1 as real + C));
    DivNonNeg(A * C * (t2 as real - t1 as real), (t2 as real + C) * (t1 as real + C));
  }

  // Per-term contribution idf * tfNorm is non-negative.
  lemma TermScoreNonNeg(n: int, df: int, tf: int, k1: real, b: real, docLen: real, avgDocLen: real)
    requires 0 <= df <= n
    requires ValidParams(tf, k1, b, docLen, avgDocLen)
    ensures Idf(n, df) * TfNorm(tf, k1, b, docLen, avgDocLen) >= 0.0
  {
    IdfNonNeg(n, df);
    TfNormNonNeg(tf, k1, b, docLen, avgDocLen);
    MulNonNegNonNeg(Idf(n, df), TfNorm(tf, k1, b, docLen, avgDocLen));
  }

}
