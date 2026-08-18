# ==============================================================================
# ANNOTATED SOURCE: lexer.nim — M/MUMPS Tokenizer
# ==============================================================================
#
# This file implements the M/MUMPS lexer (tokenizer). The lexer converts
# raw M source text into a stream of tokens for the parser.
#
# M/MUMPS Lexical Overview:
#   M has a distinctive lexical structure:
#   - Commands are identified by whitespace before them (command boundaries)
#   - Many operators are single characters that are also valid in other contexts
#   - The apostrophe (') is the NOT operator, which combines with other operators
#   - Names can start with % (percent variables)
#   - There are no keywords in the traditional sense — commands are recognized
#     by position (after whitespace), not by reserved word status
#
# ANSI/MDC X11.1-1995 Standard References:
#   Section 3: Lexical Elements
#     3.1: Character Set — ASCII printable + control chars
#     3.2: Names — letters, digits, %; 1-32 chars (RSM extends to 32+)
#     3.3: Numeric Literals — digits [.digits]
#     3.4: String Literals — "text" with "" for embedded quotes
#     3.5: Operators — single and multi-character
#     3.6: Delimiters — ( ) , : .
#
# Design Decisions:
#   - We skip whitespace at the start of nextToken(). This is critical
#     because M uses whitespace as a command boundary indicator.
#   - The lexer doesn't distinguish commands from variables — that's the
#     parser's job. Both are tokWord tokens.
#   - Multi-character operators ('=, '<, '>, '[, '], '?) are handled
#     by lookahead after seeing the apostrophe.
#   - The @ (indirection) operator is a single token.
#   - Numbers are lexed as complete tokens (integer or decimal). The parser
#     handles the case where a number is followed by .digits.
#
# Genera-Style Introspection Notes:
#   - A Genera lexer would produce tokens with source locations (line, col)
#   - Token stream visualization would show each token with its kind and text
#   - Lexer errors would include source context for debugging
#   - A syntax-directed editor would use the lexer for incremental re-lexing
#   - Token coloring/syntax highlighting would use the token kinds
#   - A Genera trace of the lexer would log each token as it's produced,
#     showing the character that triggered it and the resulting token
#
# Cross-References:
#   - Consumed by: parser.nim (nextToken is called repeatedly)
#   - Uses: ast.nim (BinOp enum for tokToBinop mapping)
#   - Produces: Token objects consumed by the parser
#
# ==============================================================================

import std/options

import ast

## TokKind — Token Types
##
## M tokens fall into these categories:
##   1. Words (identifiers/commands): tokWord
##   2. Literals: tokNumber, tokStr
##   3. Operators: tokPlus through tokOr, including multi-char
##   4. Delimiters: tokLParen, tokRParen, tokComma, tokColon, tokDot
##   5. Special: tokDollar ($), tokCaret (^), tokAt (@), tokQuestion (?)
##   6. EOF: tokEof
##
## The NOT combinations ('=, '<, '>, '[, '], '?) are separate tokens
## because they have distinct semantic meaning and precedence.
type
  TokKind* = enum
    tokWord,          # alphabetic runs (var names, commands, pattern codes)
    tokNumber,        # numeric literal (digits only)
    tokStr,           # quoted string literal ("" unescaped)
    tokAt,            # @
    tokCaret,         # ^
    tokDollar,        # $
    tokLParen,        # (
    tokRParen,        # )
    tokComma,         # ,
    tokColon,         # :
    tokDot,           # .
    tokPlus,          # +
    tokMinus,         # -
    tokStar,          # *
    tokStarStar,      # **
    tokSlash,         # /
    tokBackslash,     # \
    tokHash,          # #
    tokConcat,        # _
    tokEq,            # =
    tokLt,            # <
    tokGt,            # >
    tokNot,           # ' (logical NOT or negation prefix)
    tokNe,            # '=
    tokNlt,           # '<  (not less)
    tokNgt,           # '>  (not greater)
    tokFollows,       # ]
    tokSortAfter,     # (reserved; ] is "follows", [ is "contains")
    tokContains,      # [
    tokNotFollows,    # ']
    tokNotContains,   # '[
    tokAnd,           # &
    tokOr,            # !
    tokQuestion,      # ?
    tokNotQuestion,   # '?
    tokEof

  ## Token — A Single Lexical Token
  ##
  ## Each token has:
  ##   kind:  The token type
  ##   text:  The source text (for words, numbers, strings)
  ##   start: The character position in the source (for error reporting)
  ##
  ## Design Decision: We store the start position rather than line/column
  ## because it's simpler and sufficient for our purposes. A production
  ## implementation would compute line/column for error messages.
  ##
  ## Genera Note: A Genera token would also carry the source document
  ## pointer and buffer position for cross-referencing.
  Token* = object
    kind*: TokKind
    text*: string
    start*: int

  ## Lexer — The Lexical Analyzer State
  ##
  ## The lexer maintains:
  ##   src: The complete source text
  ##   pos: Current position in the source
  ##
  ## Design Decision: The lexer is a simple forward-scanning state machine.
  ## It doesn't use a character stream abstraction — we index directly into
  ## the string. This is efficient for Nim's string representation.
  ##
  ## Genera Note: A Genera lexer would be a presentation-based parser that
  ## understands the syntax table and handles incremental updates.
  Lexer* = object
    src*: string
    pos*: int

## newLexer — Create a New Lexer
proc newLexer*(src: string): Lexer =
  Lexer(src: src, pos: 0)

## peekAt — Look Ahead Without Consuming
##
## Returns the character at offset `off` from current position,
## or '\0' if past end of source. This is the fundamental
## lookahead primitive.
proc peekAt(lex: Lexer, off: int): char =
  let i = lex.pos + off
  if i < lex.src.len:
    lex.src[i]
  else:
    '\0'

## isNameChar — Test if Character Can Appear in a Name
##
## ANSI/ISO Section 3.2: Names consist of letters, digits, and
## the percent sign (%). The first character must be a letter or %.
## We don't enforce the first-character rule here — that's the
## caller's responsibility.
##
## Design Decision: We accept both upper and lowercase letters.
## M is case-insensitive for commands but case-SENSITIVE for variable
## names in many implementations. We preserve case and let the
## comparison functions handle case sensitivity.
proc isNameChar(c: char): bool =
  c in {'0'..'9', 'A'..'Z', 'a'..'z'} or c == '%'

## nextToken — Lex the Next Token
##
## This is the main lexer entry point. It:
##   1. Skips whitespace (tabs, spaces, newlines, carriage returns)
##   2. Identifies the token type based on the next character(s)
##   3. Consumes the appropriate number of characters
##   4. Returns the token
##
## Token Recognition Strategy:
##   - '"' → string literal (scan to closing ", handle "" escape)
##   - '0'..'9' → number (scan digits, optionally .digits)
##   - 'A'..'Z', 'a'..'z', '%' → word (scan name chars)
##   - Single/multi-char operators → operator token
##
## The apostrophe (') handling is notable:
##   ' alone → tokNot (logical NOT prefix)
##   '= → tokNe (not equal)
##   '< → tokNlt (not less than)
##   '> → tokNgt (not greater than)
##   '[ → tokNotContains
##   '] → tokNotFollows
##   '? → tokNotQuestion
##
## This is M's "prefix negation" pattern — the apostrophe modifies
## the following operator. It's unique to M and confuses many newcomers.
##
## Design Decision: We handle ** (exponentiation) as a special case
## of the * token, using one character of lookahead.
##
## Genera Note: A Genera lexer trace would show:
##   [LEX] pos=0 char='"' → scanning string literal
##   [LEX] pos=6 char='"' → end of string, tokStr text="hello"
##   [LEX] pos=7 char=' ' → skipping whitespace
##   [LEX] pos=8 char='W' → scanning word
##   [LEX] pos=13 → tokWord text="WRITE"
proc nextToken*(lex: var Lexer): Token =
  while lex.peekAt(0) in {' ', '\t', '\r', '\n'}:
    inc lex.pos
  let start = lex.pos
  let c = lex.peekAt(0)
  if c == '\0':
    return Token(kind: tokEof, start: start)

  # String literal
  # ANSI/ISO Section 3.4: String literals are delimited by double-quotes.
  # Embedded double-quotes are represented by doubling: "hello""world"
  # contains the string hello"world.
  if c == '"':
    inc lex.pos
    var s = ""
    while true:
      let ch = lex.peekAt(0)
      if ch == '\0':
        break
      if ch == '"':
        if lex.peekAt(1) == '"':
          s.add '"'
          lex.pos += 2
        else:
          inc lex.pos
          break
      else:
        s.add ch
        inc lex.pos
    return Token(kind: tokStr, text: s, start: start)

  # Number (integer, decimal, or scientific notation)
  # ANSI/ISO Section 3.3: Numeric literals are digits optionally followed
  # by a decimal point and more digits. Scientific notation uses E or e.
  # No leading sign — that's a unary operator in M.
  if c in {'0'..'9'}:
    var n = ""
    while lex.peekAt(0) in {'0'..'9'}:
      n.add lex.peekAt(0)
      inc lex.pos
    if lex.peekAt(0) == '.' and lex.peekAt(1) in {'0'..'9'}:
      n.add '.'
      inc lex.pos
      while lex.peekAt(0) in {'0'..'9'}:
        n.add lex.peekAt(0)
        inc lex.pos
    # Scientific notation: E or e followed by optional sign and digits
    if lex.peekAt(0) in {'E', 'e'}:
      n.add lex.peekAt(0)
      inc lex.pos
      if lex.peekAt(0) in {'+', '-'}:
        n.add lex.peekAt(0)
        inc lex.pos
      while lex.peekAt(0) in {'0'..'9'}:
        n.add lex.peekAt(0)
        inc lex.pos
    return Token(kind: tokNumber, text: n, start: start)

  # Name / word (letters, %, digits after first)
  # ANSI/ISO Section 3.2: Names start with a letter or % and continue
  # with letters, digits, or %. Maximum 32 characters in the standard.
  # RSM extends this to longer names.
  if c in {'A'..'Z', 'a'..'z'} or c == '%':
    var w = ""
    while isNameChar(lex.peekAt(0)):
      w.add lex.peekAt(0)
      inc lex.pos
    return Token(kind: tokWord, text: w, start: start)

  # Operators and delimiters
  # Each case handles a single character or a multi-character sequence.
  var kind: TokKind
  case c
  of '*':
    if lex.peekAt(1) == '*':
      lex.pos += 2
      kind = tokStarStar
    else:
      inc lex.pos
      kind = tokStar
  of '\'':
    # Apostrophe: NOT prefix — combines with following operator
    inc lex.pos
    case lex.peekAt(0)
    of '=':
      inc lex.pos
      kind = tokNe
    of '<':
      inc lex.pos
      kind = tokNlt
    of '>':
      inc lex.pos
      kind = tokNgt
    of '[':
      inc lex.pos
      kind = tokNotContains
    of ']':
      inc lex.pos
      kind = tokNotFollows
    of '?':
      inc lex.pos
      kind = tokNotQuestion
    else:
      kind = tokNot
  of '<':
    inc lex.pos
    kind = tokLt
  of '>':
    inc lex.pos
    kind = tokGt
  of '[':
    inc lex.pos
    kind = tokContains
  of ']':
    inc lex.pos
    kind = tokFollows
  of '+':
    inc lex.pos
    kind = tokPlus
  of '-':
    inc lex.pos
    kind = tokMinus
  of '/':
    inc lex.pos
    kind = tokSlash
  of '\\':
    inc lex.pos
    kind = tokBackslash
  of '#':
    inc lex.pos
    kind = tokHash
  of '_':
    inc lex.pos
    kind = tokConcat
  of '=':
    inc lex.pos
    kind = tokEq
  of '(':
    inc lex.pos
    kind = tokLParen
  of ')':
    inc lex.pos
    kind = tokRParen
  of ',':
    inc lex.pos
    kind = tokComma
  of ':':
    inc lex.pos
    kind = tokColon
  of '.':
    inc lex.pos
    kind = tokDot
  of '^':
    inc lex.pos
    kind = tokCaret
  of '$':
    inc lex.pos
    kind = tokDollar
  of '@':
    inc lex.pos
    kind = tokAt
  of '&':
    inc lex.pos
    kind = tokAnd
  of '!':
    inc lex.pos
    kind = tokOr
  of '?':
    inc lex.pos
    kind = tokQuestion
  else:
    # Unknown character — treat as a word (graceful degradation)
    inc lex.pos
    return Token(kind: tokWord, text: $c, start: start)
  Token(kind: kind, start: start)

## tokToBinop — Map Token Kind to Binary Operator
##
## This function maps lexer tokens to AST binary operators.
## Not all tokens map to operators (e.g., tokLParen doesn't).
## Returns none for non-operator tokens.
##
## Design Decision: This is a separate function (rather than inline in
## the parser) because it documents the complete mapping between tokens
## and operators, serving as a reference for the operator precedence table.
##
## M Operator Precedence (highest to lowest):
##   1. Unary: - (negation), ' (NOT)
##   2. Arithmetic: ** (power)
##   3. Arithmetic: * / \ # (multiply, divide, int-div, mod)
##   4. Arithmetic: + - (add, subtract)
##   5. Concatenation: _ (underscore)
##   6. Comparison: = '= < > '< '> ] '] [ '[
##   7. Pattern: ? '?
##   8. Logical: & (AND)
##   9. Logical: ! (OR)
##
## Note: The parser handles precedence by recursive descent, not by
## a precedence table. This function is used to identify binary operators.
proc tokToBinop*(t: TokKind): Option[BinOp] =
  case t
  of tokPlus: some(bAdd)
  of tokMinus: some(bSub)
  of tokStar: some(bMul)
  of tokSlash: some(bDiv)
  of tokBackslash: some(bIntDiv)
  of tokHash: some(bMod)
  of tokStarStar: some(bPow)
  of tokConcat: some(bConcat)
  of tokEq: some(bEql)
  of tokNe: some(bNeql)
  of tokLt: some(bLt)
  of tokGt: some(bGt)
  of tokNlt: some(bNlt)
  of tokNgt: some(bNgt)
  of tokFollows: some(bFollows)
  of tokSortAfter: some(bSortAfter)
  of tokContains: some(bContains)
  of tokNotFollows: some(bNotFollows)
  of tokNotContains: some(bNotContains)
  of tokAnd: some(bAnd)
  of tokOr: some(bOr)
  else: none(BinOp)

## isBinop — Test if a Token is a Binary Operator
##
## Convenience function used by the parser to decide whether to
## continue parsing a binary expression.
proc isBinop*(t: TokKind): bool =
  tokToBinop(t).isSome
