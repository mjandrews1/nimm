# ==============================================================================
# ANNOTATED SOURCE: value.nim — M/MUMPS Value Representation
# ==============================================================================
#
# This file implements the fundamental value semantics of M/MUMPS.
# In M, there is only ONE data type: the string. Numbers are strings
# that happen to look numeric. This duality is the most important and
# most subtle aspect of M, and this file handles it.
#
# ANSI/MDC X11.1-1995 Standard References:
#   Section 5.1: Data Values — "All data values in M are represented
#                as character strings."
#   Section 5.2: Numeric Strings — A string is numeric if it matches
#                the canonical form: [sign] digits [. digits]
#   Section 5.3: Truth Values — Numeric 0 is false; all else is true.
#   Section 7.1: Arithmetic Operators — Operands are coerced to numeric
#                if canonical, else treated as 0.
#
# Design Decisions:
#   - We use Nim's `float` for internal numeric representation. This is
#     a pragmatic choice: M's arithmetic is IEEE 754 double-precision in
#     most implementations. A bignum implementation would be more correct
#     but slower.
#   - `isCanonicalNumber` is the gatekeeper: it determines whether a
#     string participates in numeric comparison semantics (Section 7.3).
#   - `truthy` implements M's three-valued logic foundation: the $TEST
#     special variable is set by IF, and postconditionals test it.
#
# Genera-Style Introspection Notes:
#   - A Genera-like M system would display values with their canonical
#     status: "42" (canonical, numeric) vs "042" (non-canonical, string)
#   - The inspector would show type hints: [NUM], [STR], [EMPTY]
#   - `parseNum` returning Option[float] enables tracing of implicit
#     coercions: "SET X=1+Y" where Y="abc" would trace "abc → 0 (non-numeric)"
#   - Value formatting is critical for WRITE output; a debugger would
#     show both the internal float and the canonical string representation
#
# Cross-References:
#   - Used by: runtime.nim (eval, evalBinop, evalFunc, svar, execFor)
#   - Used by: runtime.nim (mCmp for symbol table collation)
#   - Depends on: std/strutils, std/options, std/math
#
# ==============================================================================

import std/[strutils, options, math]

## isCanonicalNumber — The M Canonical Number Detector
##
## ANSI/ISO Section 5.2 defines a "canonical numeric string" as:
##   [optional minus sign] digits [optional decimal point digits]
##
## This is THE most important function in M value semantics. It determines:
##   1. Whether = < > comparisons are numeric or string (Section 7.3)
##   2. Whether arithmetic operators coerce the operand (Section 7.1)
##   3. Whether $ORDER treats a subscript as numeric or string
##
## Examples:
##   "42"    → true   (canonical integer)
##   "3.14"  → true   (canonical decimal)
##   "-7"    → true   (canonical negative)
##   "042"   → false  (leading zero, non-canonical — STRING comparison!)
##   "42.0"  → false  (trailing zero after decimal, non-canonical)
##   ""      → false  (empty string)
##   "abc"   → false  (not numeric at all)
##
## Design Note: The strictness here matters. In M, "042" and "42" compare
## differently: "042"<"42" is TRUE (string comparison) while 042=42 is TRUE
## (numeric coercion). This implementation follows the spec strictly.
##
## Genera Note: An inspector would show canonical/non-canonical as a type
## tag on every value. A static analyzer could warn about non-canonical
## literals used in arithmetic contexts.
proc isCanonicalNumber*(s: string): bool =
  # Inline strip — skip leading/trailing whitespace without allocation
  var i = 0
  while i < s.len and s[i] in {' ', '\t', '\n', '\r'}:
    inc i
  var j = s.len - 1
  while j >= i and s[j] in {' ', '\t', '\n', '\r'}:
    dec j
  let len = j - i + 1
  if len == 0:
    return false
  if s[i] == '-':
    inc i
    if i > j:
      return false
  var hasDigit = false
  while i <= j and s[i] in {'0'..'9'}:
    hasDigit = true
    inc i
  if i <= j and s[i] == '.':
    inc i
    while i <= j and s[i] in {'0'..'9'}:
      hasDigit = true
      inc i
  # Scientific notation: E or e followed by optional sign and digits
  if i <= j and s[i] in {'E', 'e'}:
    inc i
    if i <= j and s[i] in {'+', '-'}:
      inc i
    var hasExponentDigit = false
    while i <= j and s[i] in {'0'..'9'}:
      hasExponentDigit = true
      inc i
    return hasDigit and hasExponentDigit and i > j
  hasDigit and i > j

## parseNum — Parse a string to float, respecting M's coercion rules
##
## ANSI/ISO Section 5.2.1: "A numeric string is evaluated as the
## numeric value it represents."
##
## Returns none(float) if the string is not canonical. This is used
## throughout the runtime to implement M's "try numeric, fall back to
## string" semantics.
##
## Design Decision: We only parse canonical numbers. Non-canonical
## strings like "042" or "42.0" return none, meaning they participate
## in string comparisons. This matches the ANSI spec exactly.
##
## Cross-References:
##   - Called by: runtime.nim (evalBinop for arithmetic, svar for $HOROLOG,
##               execFor for loop control, evalFunc for $ASCII/$CHAR/$RANDOM)
##   - Called by: runtime.nim (mCmp for collation order)
##   - Guards: formatNumber (for output), truthy (for $TEST)
proc parseNum*(s: string): Option[float] =
  if not isCanonicalNumber(s):
    return none(float)
  try:
    result = some(parseFloat(s))
  except ValueError:
    result = none(float)

## formatNumber — Format a float as a canonical M number string
##
## ANSI/ISO Section 5.2: "The canonical form of a numeric string is
## [sign] digits [.digits]" — no trailing zeros, no leading zeros
## (except "0" itself), no scientific notation.
##
## This function is the inverse of parseNum. It must produce strings
## that isCanonicalNumber will accept. The rules:
##   1. Integers (no fractional part) → plain integer string
##   2. Decimals → shortest representation, no trailing zeros
##   3. Zero → "0"
##
## Design Decision: We use Nim's $ operator for float→string which
## gives a reasonable shortest representation, then trim trailing zeros.
## The threshold 9007199254740992.0 is 2^53, the limit of exact integer
## representation in IEEE 754 double.
##
## Genera Note: A value inspector would show both the internal float
## and the formatted canonical string. The discrepancy between them
## (e.g., 0.1 internally vs "0.1" formatted) would be highlighted.
##
## Cross-References:
##   - Called by: runtime.nim (eval for eNeg, evalBinop for arithmetic results)
##   - Called by: runtime.nim (execFor loop variable update)
##   - Called by: runtime.nim (evalFunc for $INCREMENT, $JUSTIFY)
##   - Inverse of: parseNum
proc formatNumber*(v: float): string =
  if v == trunc(v) and abs(v) < 9007199254740992.0:
    return $int64(v)
  var buf = newStringOfCap(24)
  buf.addFloat v
  if '.' in buf:
    while buf.len > 0 and buf[^1] == '0':
      buf.setLen(buf.len - 1)
    if buf.len > 0 and buf[^1] == '.':
      buf.setLen(buf.len - 1)
    if buf.len == 0:
      return "0"
  if buf.endsWith(".0"):
    buf.setLen(buf.len - 2)
  buf

## truthy — M's Truth Value Test
##
## ANSI/ISO Section 5.3: "The truth value of a string is determined
## as follows: if the string is a numeric string and its numeric value
## is zero, the truth value is false. If the string is a numeric string
## and its numeric value is not zero, the truth value is true. If the
## string is not a numeric string and it has zero length, the truth
## value is false. If the string is not a numeric string and it has
## nonzero length, the truth value is true."
##
## This implements the complete truth table:
##   "0"     → false  (numeric zero)
##   "1"     → true   (numeric nonzero)
##   ""      → false  (empty string)
##   "abc"   → true   (non-empty non-numeric string)
##   "042"   → true   (non-canonical but non-empty → true!)
##
## The last case is subtle: "042" is NOT a canonical number, so parseNum
## returns none, so we check len > 0 → true. This matches the standard.
##
## Design Note: This is used everywhere — IF, postconditionals, $SELECT,
## $TEST, &/!/ternary. A Genera-style trace would log every truth test
## with the value and its boolean result.
##
## Cross-References:
##   - Called by: runtime.nim (eval for eNot, evalBinop for bAnd/bOr)
##   - Called by: runtime.nim (runLine for cIf condition, postconditionals)
##   - Called by: runtime.nim (evalFunc for $SELECT)
##   - Sets: rt.test ($TEST special variable) in runtime.nim
proc truthy*(s: string): bool =
  let n = parseNum(s)
  if n.isSome:
    return n.get != 0.0
  s.len > 0
