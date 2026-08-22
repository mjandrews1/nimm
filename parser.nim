# ==============================================================================
# ANNOTATED SOURCE: parser.nim — M/MUMPS Line Parser
# ==============================================================================
#
# This file implements the M/MUMPS parser. It converts a stream of tokens
# from the lexer into an AST (Abstract Syntax Tree) defined in ast.nim.
#
# M/MUMPS Parsing Challenges:
#   1. Command boundaries are whitespace-dependent: "SET A=1WRITE" is one
#      word, but "SET A=1 WRITE" has SET and WRITE as separate commands.

const MaxParseIterations = 10000  # Prevent livelock on malformed input

## blockSep — merged-block boundary marker (#282)
##
## The routine loader (runtime.nim mergeDotContinuations) joins dot-
## continuation lines into one logical line. Without a boundary marker, a
## mid-block IF/FOR swallows its trailing siblings as part of its own body
## (M scopes IF/FOR to end-of-line). After each true block-opener's subtree,
## the loader emits this control character; body parsers consume exactly one
## to close their scope. It cannot collide with user code: \x01 is not
## valid in M source and lexes as a single-character word token.
const blockSep* = "\x01"

#   2. The parser must distinguish commands from variable names by context.
#   3. M has no explicit statement terminator — commands end at the next
#      command (identified by whitespace + known command word).
#   4. IF and FOR scope to the rest of the line, not to a block.
#   5. The $ prefix introduces functions and special variables — the parser
#      must determine which based on whether parentheses follow.
#
# ANSI/MDC X11.1-1995 Standard References:
#   Section 4: Expressions — expr atoms, binary ops, pattern match
#   Section 10: Commands — each command has specific argument syntax
#
# Parser Architecture:
#   - Recursive descent parser (no parser generator needed)
#   - One-lookahead (LL(1)) with occasional two-token lookahead (peek2)
#   - Expression parsing uses operator precedence via recursive descent
#   - Command parsing dispatches on the command word
#
# Design Decisions:
#   - The parser is line-oriented: parseLine() reads one line's worth of
#     commands. This matches M's line-oriented execution model.
#   - Command detection uses `atCommandPos()` which checks for whitespace
#     before a known command word. This implements M's "command boundary"
#     rule.
#   - The parser preserves case for variable names (M is case-sensitive
#     for variables) but uppercases command names (M is case-insensitive
#     for commands).
#   - Error handling is minimal — we use Nim's exception mechanism for
#     unexpected tokens. A production parser would have better recovery.
#
# Genera-Style Introspection Notes:
#   - A Genera parser would produce a fully annotated AST with source
#     locations, comments, and whitespace information
#   - A syntax-directed editor would use the parser for incremental
#     re-parsing of modified regions
#   - A Genera trace would show each parse decision: "atCommandPos? yes,
#     command=SET, parsing setArgs..."
#   - Parse errors would include the token stream context and expected
#     tokens for recovery suggestions
#   - A MUMPS mode in Genera's editor would provide real-time syntax
#     checking by re-parsing on each keystroke
#
# Cross-References:
#   - Uses: lexer.nim (nextToken, Token, TokKind, isBinop, tokToBinop)
#   - Uses: ast.nim (all AST node types)
#   - Consumed by: runtime.nim (parseLine result fed to runLine)
#
# ==============================================================================

import std/[options, strutils]

import ast
import lexer

## Parser — The Parser State
##
## The parser maintains:
##   src:     The original source text (for whitespace checks)
##   lexer:   The lexer instance
##   cur:     The current token (already consumed from lexer)
##   peeked:  One token of lookahead (optional)
##
## Design Decision: We use a two-token lookahead buffer. Most M constructs
## can be parsed with one lookahead, but the FOR specification needs two:
##   FOR I=1:1:3  — need to see "=" after "I" to know it's a counted FOR
##   FOR  — need to see that the next token is NOT a word followed by "="
type
  Parser* = object
    src*: string
    lexer*: Lexer
    cur*: Token
    peeked*: Option[Token]

## newParser — Create a Parser and Prime It
##
## Initializes the lexer, reads the first token, and sets up the parser.
proc newParser*(src: string): Parser =
  var lx = newLexer(src)
  let first = lx.nextToken()
  result = Parser(src: src, lexer: lx, cur: first, peeked: none(Token))

## peek — Look at Current Token Kind (No Consume)
proc peek(p: Parser): TokKind = p.cur.kind

## peek2 — Two-Token Lookahead
##
## Returns the kind of the NEXT token without consuming the current one.
## This is needed for FOR: we need to see if a word is followed by '='
## to distinguish "FOR I=1:1:3" from "FOR I QUIT:I>2".
proc peek2(p: var Parser): TokKind =
  if not p.peeked.isSome:
    p.peeked = some(p.lexer.nextToken())
  p.peeked.get.kind

## advance — Consume and Return the Current Token
##
## Moves the parser forward by one token. Returns the consumed token.
proc advance(p: var Parser): Token =
  result = p.cur
  if p.peeked.isSome:
    p.cur = p.peeked.get
    p.peeked = none(Token)
  else:
    p.cur = p.lexer.nextToken()

## precededByWs — Check if Token Was Preceded by Whitespace
##
## This is THE critical function for M parsing. In M, a command is
## identified by whitespace before it. "SETX=1" is a variable name,
## but "SET X=1" has SET as a command and X as a variable.
##
## We check if the character before the token's start position is
## whitespace. Position 0 is always preceded by "whitespace" (start of input).
##
## ANSI/ISO Section 3.1: "A command is introduced by one or more space
## or tab characters following the end of a preceding command argument."
proc precededByWs(p: Parser, t: Token): bool =
  t.start == 0 or p.src[t.start - 1] in {' ', '\t', '\r', '\n'}

## cmdSepBefore — True when a two-space command separator precedes token t
##
## ANSI/ISO Section 7.1.1: a command that takes no arguments (or an
## argument list that has ended) is terminated by TWO spaces; the next
## word then starts a new command rather than continuing the arguments.
proc cmdSepBefore(p: Parser, t: Token): bool =
  t.start >= 2 and p.src[t.start - 1] in {' ', '\t'} and
    p.src[t.start - 2] in {' ', '\t'}

## isCommandWord — Test if a Word is a Known M Command
##
## Returns true if the word (case-insensitive) matches a known command.
## This list includes both ANSI/ISO standard commands and common extensions.
##
## Design Decision: We include single-letter abbreviations (S for SET,
## W for WRITE, etc.) which are essential for real M code. The standard
## allows these abbreviations.
##
## Note: "ELSE" is a command in M but is handled specially — it's really
## just "IF '0" (IF NOT false). We include it for recognition but the
## parser doesn't have a specific ELSE handler.
proc equiWord(a, b: string): bool {.inline.} =
  if a.len != b.len: return false
  for i in 0..<a.len:
    if a[i].toLowerAscii() != b[i].toLowerAscii():
      return false
  return true

proc isCommandWord(p: Parser, w: string): bool =
  if w.len == 0: return false
  let c = w[0].toLowerAscii()
  case c
  of 's': equiWord(w, "SET") or equiWord(w, "S")
  of 'w': equiWord(w, "WRITE") or equiWord(w, "W")
  of 'i': equiWord(w, "IF") or equiWord(w, "I")
  of 'f': equiWord(w, "FOR") or equiWord(w, "F")
  of 'q': equiWord(w, "QUIT") or equiWord(w, "Q")
  of 'k': equiWord(w, "KILL") or equiWord(w, "K")
  of 'n': equiWord(w, "NEW") or equiWord(w, "N")
  of 'h': equiWord(w, "HANG") or equiWord(w, "H") or equiWord(w, "HALT")
  of 'l': equiWord(w, "LOCK") or equiWord(w, "L")
  of 'm': equiWord(w, "MERGE") or equiWord(w, "M")
  of 'x': equiWord(w, "XECUTE") or equiWord(w, "X")
  of 'd': equiWord(w, "DO") or equiWord(w, "D")
  of 'g': equiWord(w, "GOTO") or equiWord(w, "G")
  of 'b': equiWord(w, "BREAK") or equiWord(w, "B")
  of 'e': equiWord(w, "ELSE") or equiWord(w, "E")
  of 'r': equiWord(w, "READ") or equiWord(w, "R")
  of 'o': equiWord(w, "OPEN") or equiWord(w, "O")
  of 'c': equiWord(w, "CLOSE") or equiWord(w, "C")
  of 'u': equiWord(w, "USE") or equiWord(w, "U")
  of 'v': equiWord(w, "VIEW") or equiWord(w, "V")
  of 'j': equiWord(w, "JOB") or equiWord(w, "J")
  of 'z':
    equiWord(w, "ZWRITE") or equiWord(w, "ZKILL") or equiWord(w, "ZBREAK") or
    equiWord(w, "ZGOTO") or equiWord(w, "ZPRINT") or equiWord(w, "ZQUIT") or
    equiWord(w, "ZSAVE") or equiWord(w, "ZSYSTEM") or equiWord(w, "ZHALT") or
    equiWord(w, "ZMESSAGE") or equiWord(w, "ZTRAP") or equiWord(w, "ZLOAD") or
    equiWord(w, "ZSTEP") or equiWord(w, "ZCONTINUE") or equiWord(w, "ZREMOVE") or
    equiWord(w, "ZEDIT") or equiWord(w, "ZE") or equiWord(w, "ZLINK") or
    equiWord(w, "ZL") or equiWord(w, "ZALLOCATE") or equiWord(w, "ZA") or
    equiWord(w, "ZDEALLOCATE") or equiWord(w, "ZD")
  of 'y': equiWord(w, "YOPEN") or equiWord(w, "YLISTEN") or equiWord(w, "YREAD") or equiWord(w, "YWRITE") or equiWord(w, "YCLOSE")
  else: false

## atCommandPos — Test if Current Token Starts a Command
##
## A token is at a command position if:
##   1. It's a word token (tokWord)
##   2. The word is a known command (isCommandWord)
##   3. It's preceded by whitespace (precededByWs)
##
## This triple check implements M's command boundary detection.
## It's the key insight that makes M parsing work despite the lack
## of explicit statement terminators.
proc atCommandPos(p: Parser): bool =
  p.cur.kind == tokWord and isCommandWord(p, p.cur.text) and precededByWs(p, p.cur)

## readWord — Consume a Word Token
##
## Returns the word text, or "" if the current token isn't a word.
## Used for reading variable names, command names, and labels.
proc readWord(p: var Parser): string =
  let t = p.advance()
  if t.kind == tokWord:
    t.text
  else:
    ""

## readDollarName — Read a $ Function/Special Variable Name
##
## After seeing a $ token, we read the following word(s) to get the
## function or special variable name. Names can be compound with
## underscores: $Y_HTTP, $Y_JSON, $Y_EMBED.
##
## Design Decision: We concatenate underscore-separated words because
## some M extensions use compound names like $Y_HTTP. The standard
## only has single-word names like $HOROLOG, $IO, etc.
##
## We uppercase the result because M function names are case-insensitive.
proc readDollarName(p: var Parser): string =
  result = p.readWord()
  # Only NI_* extension functions use compound underscore names ($NI_HTTP);
  # for everything else an underscore is the concat operator, so
  # "$JOB_"z"" must parse as $JOB _ "z".
  if result.toUpperAscii == "NI":
    while p.peek() == tokConcat:
      discard p.advance() # consume _
      let next = p.readWord()
      result.add("_")
      result.add(next)
  result = result.toUpperAscii

## isExprStart — Test if Current Token Could Start an Expression
##
## Used to determine when to stop parsing argument lists. If the
## current token can't start an expression, we're done.
proc isExprStart(p: Parser): bool =
  case p.cur.kind
  of tokNumber, tokStr, tokDollar, tokCaret, tokLParen, tokMinus, tokPlus, tokNot, tokAt,
     tokWord:
    true
  else:
    false

# ======================================================================
# Expression Parsing
# ======================================================================
#
# M expression grammar (simplified):
#   expr     = prefix (binop prefix | '?' pattern | ''?' pattern)*
#   prefix   = '-' prefix | '' prefix | primary
#   primary  = number | string | '(' expr ')' | '$' name args?
#            | '^' name subscripts? | name subscripts? | '@' primary
#
# Operator precedence (handled by recursive descent structure):
#   1. Unary: - ' (prefix)
#   2. Binary: all operators (parsed left-to-right, precedence in evalBinop)
#
# Note: The parser doesn't enforce operator precedence at parse time.
# Instead, it builds a flat binary tree and the runtime evaluates with
# the correct precedence. This is simpler but means the AST doesn't
# reflect precedence directly. A more sophisticated implementation would
# use Pratt parsing or precedence climbing.

proc parseExpr*(p: var Parser): Expr
proc parsePrefix(p: var Parser): Expr
proc parsePrimary(p: var Parser): Expr
proc parseSubscripts(p: var Parser): seq[Expr]
proc parseFuncArgs(p: var Parser, name: string): seq[Expr]
proc parsePatternAtoms(p: var Parser): seq[PatternAtom]

## parseExpr — Parse an Expression
##
## Parses a complete expression with binary operators and pattern matches.
## This is the top-level expression parser.
##
## Algorithm:
##   1. Parse the left operand (prefix expression)
##   2. While we see a binary operator or pattern match:
##      a. Consume the operator
##      b. Parse the right operand
##      c. Build a binary expression node
##   3. Return the expression
##
## Pattern match (? and '?) is handled here because it's an infix
## operator in M, but its right operand is a pattern (not a normal
## expression). We parse pattern atoms specially.
##
## Design Decision: We parse binary operators in a left-associative
## loop. This means "1+2+3" becomes ((1+2)+3). M's arithmetic is
## left-associative, so this is correct.
proc parseExpr(p: var Parser): Expr =
  var left = parsePrefix(p)
  var iterations = 0
  while true:
    if iterations >= MaxParseIterations:
      break
    inc iterations
    if isBinop(p.peek()):
      let op = tokToBinop(p.peek()).get()
      discard p.advance()
      let right = parsePrefix(p)
      left = Expr(kind: eBinary, op: op, left: left, right: right)
    elif p.peek() == tokQuestion:
      # Pattern match: expr ? pattern
      discard p.advance()
      let atoms = parsePatternAtoms(p)
      left = Expr(kind: ePattern, patLhs: left, atoms: atoms)
    elif p.peek() == tokNotQuestion:
      # Not pattern match: expr '? pattern → NOT(expr ? pattern)
      discard p.advance()
      let atoms = parsePatternAtoms(p)
      left = Expr(kind: eNot, operand: Expr(kind: ePattern, patLhs: left, atoms: atoms))
    else:
      break
  left

## parsePrefix — Parse Unary Prefix Operators
##
## Handles unary minus (-), unary plus (+), and logical NOT (').
## These are right-associative: --x means -(-x), ''x means NOT(NOT(x)).
##
## Design Decision: We use recursion for right-associativity. This means
## "---x" parses correctly as -(-(-x)).
proc parsePrefix(p: var Parser): Expr =
  if p.peek() == tokMinus:
    discard p.advance()
    Expr(kind: eNeg, operand: parsePrefix(p))
  elif p.peek() == tokPlus:
    # Unary plus — numeric coercion per RSM/RFC: +"2E3"→"2000",
    # +"01.50"→"1.5", +"abc"→"0". Explicit node (#280).
    discard p.advance()
    Expr(kind: ePos, operand: parsePrefix(p))
  elif p.peek() == tokNot:
    discard p.advance()
    Expr(kind: eNot, operand: parsePrefix(p))
  else:
    parsePrimary(p)

## parsePrimary — Parse a Primary Expression
##
## Primary expressions are the atoms of the expression grammar:
##   - Numeric literals: 42, 3.14
##   - String literals: "hello"
##   - Parenthesized expressions: (expr)
##   - $ functions and special variables: $PIECE(...), $HOROLOG
##   - Global variables: ^GLOBAL, ^GLOBAL(1,2)
##   - Local variables: X, X(1,2)
##   - Indirection: @expr
##
## Design Decision: We handle the number "." number case here (e.g.,
## "1.5" as a decimal number) by looking ahead for a dot followed by
## a number after reading the integer part. This is necessary because
## the lexer doesn't know that "1" followed by "." followed by "5"
## should be one token — the dot could also be a range operator or
## a pattern "or more" indicator.
##
## The $ case is interesting: we read the name, then check if '('
## follows. If yes, it's a function call ($PIECE(...)). If no, it's
## a special variable ($HOROLOG). This distinction is made at parse
## time, not lex time.
##
## The @ (indirection) case: M supports indirection where a variable's
## value is used as part of the program. We parse @primary by just
## parsing the primary — the runtime will handle the indirection.
## (Note: this implementation doesn't fully support indirection.)
proc parsePrimary(p: var Parser): Expr =
  case p.peek()
  of tokNumber:
    let t = p.advance()
    # Combine an integer literal with a following `.digits` into a decimal.
    if p.peek() == tokDot and p.peek2() == tokNumber:
      discard p.advance()
      let f = p.advance()
      Expr(kind: numLit, sval: t.text & "." & f.text, cachedFloat: parseFloat(t.text & "." & f.text), hasCachedFloat: true)
    else:
      Expr(kind: numLit, sval: t.text, cachedFloat: parseFloat(t.text), hasCachedFloat: true)
  of tokStr:
    let t = p.advance()
    Expr(kind: eStr, sval: t.text)
  of tokLParen:
    discard p.advance()
    let e = parseExpr(p)
    if p.peek() == tokRParen:
      discard p.advance()
    e
  of tokDollar:
    # $ introduces functions and special variables
    discard p.advance()
    let name = p.readDollarName()
    if p.peek() == tokLParen:
      # Function call: $NAME(args...)
      let args = parseFuncArgs(p, name)
      Expr(kind: eFunc, fname: name, fargs: args)
    else:
      # Special variable: $NAME
      Expr(kind: eSvar, sname: name)
  of tokCaret:
    # Global variable: ^NAME or ^NAME(subs...)
    # Naked reference: ^(subs...) — uses last global reference
    discard p.advance()
    if p.peek() == tokLParen:
      # Naked reference: ^(subs...)
      let subs = parseSubscripts(p)
      Expr(kind: eVar, vname: "^", subs: subs)
    else:
      # ^NAME or ^$SSV (Structured System Variable, #278) or naked ^
      var prefix = "^"
      if p.peek() == tokDollar:
        discard p.advance()
        prefix = "^$"
      let name = p.readWord()
      let subs = parseSubscripts(p)
      Expr(kind: eVar, vname: prefix & name, subs: subs)
  of tokWord:
    # Local variable: NAME or NAME(subs...)
    let name = p.readWord()
    let subs = parseSubscripts(p)
    Expr(kind: eVar, vname: name, subs: subs)
  of tokAt:
    # Indirection: @expr or @(expr, sub1, sub2)
    # For @X(1), X is the variable name and (1) are the subscripts
    discard p.advance()
    # Read just the variable name (not subscripts)
    var innerExpr: Expr
    if p.peek() == tokWord:
      let name = p.readWord()
      innerExpr = Expr(kind: eVar, vname: name, subs: @[])
    elif p.peek() == tokCaret:
      discard p.advance()
      let name = p.readWord()
      innerExpr = Expr(kind: eVar, vname: "^" & name, subs: @[])
    elif p.peek() == tokDollar:
      discard p.advance()
      let name = p.readDollarName()
      innerExpr = Expr(kind: eSvar, sname: name)
    else:
      innerExpr = parsePrimary(p)
    var subs: seq[Expr] = @[]
    # Check for subscripts: @X(sub1, sub2)
    if p.peek() == tokLParen:
      discard p.advance()
      while true:
        subs.add(parseExpr(p))
        if p.peek() == tokComma:
          discard p.advance()
        else:
          break
      if p.peek() == tokRParen:
        discard p.advance()
    Expr(kind: eIndirect, indirectExpr: innerExpr, indirectSubs: subs)
  else:
    # Unexpected token — return a zero literal as fallback
    discard p.advance()
    Expr(kind: numLit, sval: "0", cachedFloat: 0.0, hasCachedFloat: true)

## parseSubscripts — Parse Variable Subscripts
##
## Subscripts are parenthesized comma-separated expressions:
##   A(1)      → subs = [numLit(1)]
##   A(1,"x")  → subs = [numLit(1), eStr("x")]
##   A         → subs = []  (no parentheses)
proc parseSubscripts(p: var Parser): seq[Expr] =
  var subs: seq[Expr] = @[]
  if p.peek() == tokLParen:
    discard p.advance()
    while true:
      subs.add parseExpr(p)
      if p.peek() == tokComma:
        discard p.advance()
      else:
        break
    if p.peek() == tokRParen:
      discard p.advance()
  subs

## parseFuncArgs — Parse Function Arguments
##
## Most functions have comma-separated arguments. $SELECT is special:
## its arguments are condition:value pairs separated by commas, with
## each pair separated by a colon.
##
## $SELECT syntax: $SELECT(cond1:val1,cond2:val2,...)
## We flatten this into [cond1, val1, cond2, val2, ...] in the AST.
##
## Design Decision: We special-case $SELECT here because its syntax
## is fundamentally different from other functions. The runtime knows
## to interpret the args as alternating condition/value pairs.
proc parseFuncArgs(p: var Parser, name: string): seq[Expr] =
  var args: seq[Expr] = @[]
  if p.peek() == tokLParen:
    discard p.advance()
  if name == "SELECT":
    # $SELECT has condition:value pairs
    while true:
      let cond = parseExpr(p)
      if p.peek() == tokColon:
        discard p.advance()
      let val = parseExpr(p)
      args.add cond
      args.add val
      if p.peek() == tokComma:
        discard p.advance()
      else:
        break
  elif name == "CASE":
    # $CASE(expr, val1:result1, val2:result2, ..., :default)
    # First arg is the expression to match
    args.add parseExpr(p)
    if p.peek() == tokComma:
      discard p.advance()
    # Remaining args are val:result pairs
    while true:
      let val = parseExpr(p)
      if p.peek() == tokColon:
        discard p.advance()
      let result = parseExpr(p)
      args.add val
      args.add result
      if p.peek() == tokComma:
        discard p.advance()
      else:
        break
  else:
    # Normal function: comma-separated expressions
    while true:
      args.add parseExpr(p)
      if p.peek() == tokComma:
        discard p.advance()
      else:
        break
  if p.peek() == tokRParen:
    discard p.advance()
  args

## parsePatternAtoms — Parse Pattern Match Atoms
##
## Pattern atoms follow the ? operator. Each atom has:
##   - An optional count (default 1)
##   - An optional dot (.) meaning "or more"
##   - A pattern code (single letter: A, N, E, U, L, P, C, H)
##
## Examples:
##   3U        → [PatternAtom(count=3, code='U', orMore=false)]
##   2.4N      → [PatternAtom(count=2, code='N', orMore=true)]
##   3U2.4N1E  → [3U, 2.N(upper=4), 1E]  (but we don't store upper)
##   "abc"     → [PatternAtom(count=1, code='E', orMore=false)]  (literal)
##
## Design Decision: We approximate literal patterns ("abc") as 'E'
## (any character) atoms. This is a simplification — the standard
## says literal patterns match the exact string. A more complete
## implementation would handle literals specially.
proc parsePatternAtoms(p: var Parser): seq[PatternAtom] =
  var atoms: seq[PatternAtom] = @[]
  var pendingWord = ""
  var pendingCount = -1
  var pendingOrMore = false
  var iterations = 0
  
  while true:
    if iterations >= MaxParseIterations:
      break
    inc iterations
    var count = 1
    var orMore = false
    
    if pendingWord.len > 0:
      # Parse from pending word
      if pendingCount >= 0:
        count = pendingCount
        pendingCount = -1
      orMore = pendingOrMore
      pendingOrMore = false
      
      var pos = 0
      # Parse leading digits
      var numStr = ""
      while pos < pendingWord.len and pendingWord[pos] in {'0'..'9'}:
        numStr.add(pendingWord[pos])
        inc pos
      if numStr.len > 0:
        try: count = parseInt(numStr)
        except: count = 1
      
      # Parse optional dot — a bare dot (no explicit count) means the
      # minimum is ZERO ("zero or more"), per §7.5.2.
      if pos < pendingWord.len and pendingWord[pos] == '.':
        inc pos
        orMore = true
        if numStr.len == 0 and pendingCount < 0:
          count = 0
        while pos < pendingWord.len and pendingWord[pos] in {'0'..'9'}:
          inc pos
      
      # Parse pattern code
      if pos < pendingWord.len and pendingWord[pos] in {'A'..'Z', 'a'..'z'}:
        let code = pendingWord[pos]
        inc pos
        if pos < pendingWord.len:
          pendingWord = pendingWord[pos..^1]
        else:
          pendingWord = ""
        atoms.add PatternAtom(count: count, code: code, orMore: orMore)
        continue
      elif pos < pendingWord.len and pendingWord[pos] in {'0'..'9'}:
        var numStr2 = ""
        while pos < pendingWord.len and pendingWord[pos] in {'0'..'9'}:
          numStr2.add(pendingWord[pos])
          inc pos
        if numStr2.len > 0:
          try: pendingCount = parseInt(numStr2)
          except: pendingCount = 1
        if pos < pendingWord.len:
          pendingWord = pendingWord[pos..^1]
        else:
          pendingWord = ""
        pendingOrMore = orMore
        continue
      else:
        # pendingWord exhausted. If it ended in a bare count (e.g. the
        # word "L1" contributing '1'), carry that count into the next
        # atom instead of aborting — the next atom may come from a
        # separate token (string literal, etc.).
        pendingWord = ""
        if numStr.len > 0 or pendingCount >= 0:
          if numStr.len > 0:
            pendingCount = count
          pendingOrMore = orMore
        else:
          break
    else:
      # Read from parser tokens
      if pendingCount >= 0:
        count = pendingCount
        pendingCount = -1
        orMore = pendingOrMore
        pendingOrMore = false
      
      var explicitCount = false
      if p.peek() == tokNumber:
        try: count = parseInt(p.cur.text)
        except: count = 1
        explicitCount = true
        discard p.advance()

      if p.peek() == tokDot:
        discard p.advance()
        orMore = true
        if not explicitCount:
          # Bare dot: zero or more (§7.5.2)
          count = 0
        if p.peek() == tokNumber:
          discard p.advance()

      if p.peek() == tokWord:
        let word = p.cur.text
        if word.len == 1:
          discard p.advance()
          atoms.add PatternAtom(count: count, code: word[0], orMore: orMore)
          continue
        elif word.len > 1:
          pendingWord = word
          pendingCount = count
          pendingOrMore = orMore
          discard p.advance()
          continue
      elif p.peek() == tokStr:
        # Literal string atom: must match exactly (§7.5.1)
        let litVal = p.cur.text
        discard p.advance()
        atoms.add PatternAtom(count: count, code: '\0', orMore: false, lit: litVal)
        continue
      else:
        break
  
  atoms

# ======================================================================
# Command Parsing
# ======================================================================
#
# Each M command has its own argument syntax. The parser dispatches on
# the command word and calls the appropriate argument parser.
#
# M Command Syntax Summary:
#   SET var=expr,var=expr,...
#   WRITE expr,expr,...,!,#,?n
#   IF expr commands
#   FOR var=init:step:limit commands
#   QUIT expr
#   KILL var,var,... or KILL (keep,keep,...)
#   NEW var,var,...
#   HANG expr
#   LOCK ref,ref,...
#   MERGE dst=src,dst=src,...
#   XECUTE expr
#   DO label,label,...
#   GOTO label
#   BREAK
#   READ var,var,...

proc parseLine*(p: var Parser, inBody: bool = false): Line
proc parseCommand(p: var Parser): CommandNode
proc parseSetArgs(p: var Parser): seq[SetItem]
proc parseSetTarget(p: var Parser): SetTarget
proc parseVarRef(p: var Parser): (string, seq[Expr])
proc parseWriteArgs(p: var Parser): seq[WriteArg]
proc parseForSpec(p: var Parser): ForSpec
proc parseForArg(p: var Parser, varName: string): ForSpec
proc parseKill(p: var Parser): Cmd
proc parseExprList(p: var Parser): seq[Expr]
proc parseNameList(p: var Parser): seq[string]
proc parseMergePairs(p: var Parser): seq[(string, string)]

## parseLine — Parse a Line of M Commands
##
## A line consists of zero or more commands, each identified by
## atCommandPos(). We stop at EOF or when the next token isn't
## a command.
##
## Design Decision: We don't parse labels here. Labels are handled
## by the routine loader (runtime.nim) which scans for labels before
## parsing commands. This separation keeps the parser focused on
## command parsing.
proc parseLine*(p: var Parser, inBody: bool = false): Line =
  ## When inBody is true (FOR/ELSE/inline-DO bodies built from merged dot
  ## continuations), a single BlockSep token terminates this body and is
  ## consumed (#282). At top level, stray BlockSeps are skipped so trailing
  ## commands after closed blocks still run.
  result = Line(cmds: @[])
  var iterations = 0
  while true:
    if iterations >= MaxParseIterations:
      break
    inc iterations
    if p.peek() == tokEof:
      break
    if p.peek() == tokWord and p.cur.text == blockSep:
      discard p.advance()
      if inBody:
        break
      else:
        continue
    if p.atCommandPos():
      result.cmds.add parseCommand(p)
    else:
      break

## parseCommand — Parse a Single Command
##
## Dispatches on the command word to the appropriate argument parser.
## Also handles postconditionals (the :expr after a command name).
##
## ANSI/ISO Section 10: Every command can have an optional
## postconditional: COMMAND:condition
## The postconditional is evaluated, and if false, the command is skipped.
##
## Design Decision: We normalize command names to uppercase for
## case-insensitive comparison. Single-letter abbreviations are mapped
## to their full forms in the case statement.
proc parseCommand(p: var Parser): CommandNode =
  let word = p.readWord()
  let name = word.toUpperAscii
  var postcond: Expr = nil
  if p.peek() == tokColon:
    discard p.advance()
    postcond = p.parseExpr()

  var cmd: Cmd
  case name
  of "SET", "S":
    cmd = Cmd(kind: cSet, setItems: parseSetArgs(p))
  of "WRITE", "W":
    cmd = Cmd(kind: cWrite, writeArgs: parseWriteArgs(p))
  of "IF", "I":
    # Comma-separated conditions (§7.2.8): all must be true; desugar to AND chain
    var cond = p.parseExpr()
    while p.peek() == tokComma:
      discard p.advance()
      cond = Expr(kind: eBinary, op: bAnd, left: cond, right: p.parseExpr())
    # Parse body until ELSE, BlockSep (merged-block boundary), or end of line
    var body = Line(cmds: @[])
    while true:
      if p.peek() == tokEof:
        break
      if p.peek() == tokWord and p.cur.text == blockSep:
        discard p.advance()
        break
      # Check if next token is ELSE
      if p.peek() == tokWord and equiWord(p.cur.text, "ELSE"):
        break
      if p.atCommandPos():
        body.cmds.add parseCommand(p)
      else:
        break
    cmd = Cmd(kind: cIf, ifCond: cond, ifBody: body)
  of "ELSE", "E":
    let body = p.parseLine(true)
    cmd = Cmd(kind: cElse, elseBody: body)
  of "FOR", "F":
    let spec = parseForSpec(p)
    let body = p.parseLine(true)
    cmd = Cmd(kind: cFor, forSpec: spec, forBody: body)
  of "QUIT", "Q":
    if isExprStart(p) and not p.atCommandPos():
      cmd = Cmd(kind: cQuit, quitVal: p.parseExpr())
    else:
      cmd = Cmd(kind: cQuit, quitVal: nil)
  of "KILL", "K":
    cmd = parseKill(p)
  of "NEW", "N":
    # Exclusive NEW (A,B): save+clear all locals EXCEPT listed (§7.2.12)
    if p.peek() == tokLParen:
      discard p.advance()
      var keep: seq[string] = @[]
      while true:
        if p.peek() == tokWord:
          keep.add(p.readWord())
        else:
          break
        if p.peek() == tokComma:
          discard p.advance()
        else:
          break
      if p.peek() == tokRParen:
        discard p.advance()
      cmd = Cmd(kind: cNewExcept, newKeep: keep)
    else:
    # NEW can have no arguments (push scope for all) or a list of variable names
    # The first word after NEW is always a variable name (even X = XECUTE)
    # But subsequent words should not be command words
      var names: seq[string] = @[]
      if p.peek() == tokWord:
        let word = p.cur.text
        # Check if this looks like a real command (not just X)
        let upperWord = word.toUpperAscii
        if upperWord != "X" and isCommandWord(p, upperWord):
          # It's a real command like SET, WRITE — treat as NEW without args
          discard
        else:
          # First word is a variable name
          names.add(word)
          discard p.advance()
          # Additional variable names (comma-separated)
          while p.peek() == tokComma:
            discard p.advance()
            if p.peek() == tokWord:
              let nextWord = p.cur.text
              let upperNext = nextWord.toUpperAscii
              if upperNext != "X" and isCommandWord(p, upperNext):
                break
              names.add(nextWord)
              discard p.advance()
      cmd = Cmd(kind: cNew, newNames: names)
  of "HANG", "H":
    cmd = Cmd(kind: cHang, hangExpr: p.parseExpr())
  of "LOCK", "L":
    cmd = Cmd(kind: cLock, lockRefs: parseExprList(p))
  of "MERGE", "M":
    cmd = Cmd(kind: cMerge, mergePairs: parseMergePairs(p))
  of "XECUTE", "X":
    cmd = Cmd(kind: cXecute, xecExpr: p.parseExpr())
  of "JOB", "J":
    # JOB entryref[(args)][:timeout]
    # entryref: LABEL^ROUTINE or ^ROUTINE
    # Labels and routine names can contain underscores (concatenation operator
    # in expressions, but part of the identifier in entryref context)
    var entryStr = ""
    if p.peek() == tokCaret:
      discard p.advance()
      entryStr = "^"
      if p.peek() == tokWord:
        entryStr.add(p.readWord())
        while p.peek() == tokConcat:
          discard p.advance()
          if p.peek() == tokWord:
            entryStr.add("_" & p.readWord())
    elif p.peek() == tokWord:
      entryStr = p.readWord()
      while p.peek() == tokConcat:
        discard p.advance()
        if p.peek() == tokWord:
          entryStr.add("_" & p.readWord())
      if p.peek() == tokCaret:
        discard p.advance()
        entryStr.add("^")
        if p.peek() == tokWord:
          entryStr.add(p.readWord())
          while p.peek() == tokConcat:
            discard p.advance()
            if p.peek() == tokWord:
              entryStr.add("_" & p.readWord())
    # Skip optional (args)
    if p.peek() == tokLParen:
      discard p.advance()
      var depth = 1
      while depth > 0 and p.peek() != tokEof:
        if p.peek() == tokLParen: depth.inc
        elif p.peek() == tokRParen: depth.dec
        discard p.advance()
    var timeout: Expr = nil
    if p.peek() == tokColon:
      discard p.advance()
      timeout = p.parseExpr()
    cmd = Cmd(kind: cJob, jobEntry: Expr(kind: eStr, sval: entryStr), jobTimeout: timeout)
  of "DO", "D":
    # DO can execute inline commands or call labels
    # Check if next token is a command word (inline DO) or a variable name (label DO)
    if p.peek() == tokWord and isCommandWord(p, p.cur.text):
      # Inline DO: DO command
      let body = p.parseLine(true)
      cmd = Cmd(kind: cDoInline, doInlineBody: body)
    else:
      # Label DO: DO label,label,...
      cmd = Cmd(kind: cDo, doArgs: parseExprList(p))
  of "GOTO", "G":
    cmd = Cmd(kind: cGoto, gotoExpr: p.parseExpr())
  of "BREAK", "B":
    cmd = Cmd(kind: cBreak)
  of "READ", "R":
    cmd = Cmd(kind: cRead, readVars: parseExprList(p))
  of "ZWRITE":
    cmd = Cmd(kind: cZwrite, zwriteExpr: p.parseExpr())
  of "ZKILL":
    cmd = Cmd(kind: cZkill, zkillExpr: p.parseExpr())
  of "ZHALT":
    var haltCode: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      haltCode = p.parseExpr()
    cmd = Cmd(kind: cZhalt, zhaltCode: haltCode)
  of "ZMESSAGE":
    cmd = Cmd(kind: cZmessage, zmessageExpr: p.parseExpr())
  of "ZSAVE":
    var saveExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      saveExpr = p.parseExpr()
    cmd = Cmd(kind: cZsave, zsaveExpr: saveExpr)
  of "ZSYSTEM":
    var sysExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      sysExpr = p.parseExpr()
    cmd = Cmd(kind: cZsystem, zsystemExpr: sysExpr)
  of "ZTRAP":
    cmd = Cmd(kind: cZtrap, ztrapExpr: p.parseExpr())
  of "ZBREAK":
    var breakExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      breakExpr = p.parseExpr()
    cmd = Cmd(kind: cZbreak, zbreakExpr: breakExpr)
  of "ZGOTO":
    cmd = Cmd(kind: cZgoto, zgotoExpr: p.parseExpr())
  of "ZPRINT":
    cmd = Cmd(kind: cZprint, zprintExpr: p.parseExpr())
  of "ZQUIT":
    var quitExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      quitExpr = p.parseExpr()
    cmd = Cmd(kind: cZquit, zquitExpr: quitExpr)
  of "ZLOAD":
    var loadExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      loadExpr = p.parseExpr()
    cmd = Cmd(kind: cZload, zloadExpr: loadExpr)
  of "ZSTEP":
    var stepExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      stepExpr = p.parseExpr()
    cmd = Cmd(kind: cZstep, zstepExpr: stepExpr)
  of "ZCONTINUE":
    cmd = Cmd(kind: cZcontinue)
  of "ZREMOVE":
    var removeExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      removeExpr = p.parseExpr()
    cmd = Cmd(kind: cZremove, zremoveExpr: removeExpr)
  of "ZEDIT", "ZE":
    var editExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      editExpr = p.parseExpr()
    cmd = Cmd(kind: cZedit, zeditExpr: editExpr)
  of "ZLINK", "ZL":
    var linkExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      linkExpr = p.parseExpr()
    cmd = Cmd(kind: cZlink, zlinkExpr: linkExpr)
  of "VIEW", "V":
    var viewExpr: Expr = nil
    if isExprStart(p) and not p.atCommandPos():
      viewExpr = p.parseExpr()
    cmd = Cmd(kind: cView, viewExpr: viewExpr)
  of "ZALLOCATE", "ZA":
    var allocRefs: seq[Expr] = @[]
    if isExprStart(p) and not p.atCommandPos():
      allocRefs = parseExprList(p)
    cmd = Cmd(kind: cZallocate, zallocRefs: allocRefs)
  of "ZDEALLOCATE", "ZD":
    var deallocRefs: seq[Expr] = @[]
    if isExprStart(p) and not p.atCommandPos():
      deallocRefs = parseExprList(p)
    cmd = Cmd(kind: cZdeallocate, zdeallocRefs: deallocRefs)
  of "OPEN", "O":
    # OPEN channel:(file:mode)[:timeout]
    let channelExpr = p.parseExpr()
    var deviceExpr = Expr(kind: eStr, sval: "")
    var modeExpr = Expr(kind: eStr, sval: "IO")
    var timeoutExpr: Expr = nil
    
    if p.peek() == tokColon:
      discard p.advance()  # consume :
      if p.peek() == tokLParen:
        discard p.advance()  # consume (
        deviceExpr = p.parseExpr()
        if p.peek() == tokColon:
          discard p.advance()  # consume :
          modeExpr = p.parseExpr()
          if p.peek() == tokColon:
            discard p.advance()  # consume :
            timeoutExpr = p.parseExpr()
        if p.peek() == tokRParen:
          discard p.advance()  # consume )
    
    cmd = Cmd(kind: cOpen, openChannel: channelExpr, openDevice: deviceExpr, openMode: modeExpr, openTimeout: timeoutExpr)
  of "USE", "U":
    # USE channel[:params]
    let channelExpr = p.parseExpr()
    var paramsExpr: Expr = nil
    if p.peek() == tokColon:
      discard p.advance()  # consume :
      paramsExpr = p.parseExpr()
    cmd = Cmd(kind: cUse, useChannel: channelExpr, useParams: paramsExpr)
  of "CLOSE", "C":
    # CLOSE channel
    let channelExpr = p.parseExpr()
    cmd = Cmd(kind: cClose, closeChannel: channelExpr)
  of "YOPEN", "YLISTEN", "YREAD", "YWRITE", "YCLOSE":
    cmd = Cmd(kind: cNoop)
  else:
    cmd = Cmd(kind: cBreak)
  CommandNode(postcond: postcond, cmd: cmd)

## parseSetArgs — Parse SET Arguments
##
## SET syntax: SET var=expr,var=expr,...
##
## Each argument is a target=value pair. The target can be:
##   - A plain variable: SET X=5
##   - A $PIECE target: SET $PIECE(A,"^",2)="B"
##   - An $EXTRACT target: SET $EXTRACT(A,2,3)="XY"
##
## Design Decision: If there's no '=' after a target, we default
## the value to an empty string. This handles "SET X" which is
## equivalent to "SET X=""" in some M implementations.
proc parseSetArgs(p: var Parser): seq[SetItem] =
  var items: seq[SetItem] = @[]
  while true:
    if p.peek() == tokLParen:
      # Grouped target list: SET (A,B,C)=7 (§7.2.20) — one value, many targets
      discard p.advance()
      var targets: seq[SetTarget] = @[]
      while true:
        targets.add(parseSetTarget(p))
        if p.peek() == tokComma:
          discard p.advance()
        else:
          break
      if p.peek() == tokRParen:
        discard p.advance()
      var value = Expr(kind: eStr, sval: "")
      if p.peek() == tokEq:
        discard p.advance()
        value = p.parseExpr()
      for t in targets:
        items.add SetItem(target: t, value: value)
    else:
      let target = parseSetTarget(p)
      let value =
        if p.peek() == tokEq:
          discard p.advance()
          p.parseExpr()
        else:
          Expr(kind: eStr, sval: "")
      items.add SetItem(target: target, value: value)
    if p.peek() == tokComma:
      discard p.advance()
    else:
      break
  items

## parseSetTarget — Parse a SET Target
##
## SET targets can be:
##   - $PIECE(var,delim,start[,end]) — piece assignment
##   - $EXTRACT(var,start[,end]) — extract assignment
##   - var or var(subs...) — plain variable assignment
##
## Design Decision: We detect $PIECE/$EXTRACT by checking for the
## dollar sign and the function name. The arguments to $PIECE/$EXTRACT
## are parsed inline (not as function arguments) because the syntax
## is slightly different in SET context.
proc parseSetTarget(p: var Parser): SetTarget =
  if p.peek() == tokDollar:
    discard p.advance()
    let name = p.readWord().toUpperAscii
    if name == "PIECE" or name == "EXTRACT":
      if p.peek() == tokLParen:
        discard p.advance()
      let varName = p.readWord()
      var args: seq[Expr] = @[]
      while true:
        if p.peek() == tokComma:
          discard p.advance()
          args.add p.parseExpr()
        else:
          break
      if p.peek() == tokRParen:
        discard p.advance()
      if name == "PIECE":
        SetTarget(kind: stPiece, targetVar: varName, targs: args)
      else:
        SetTarget(kind: stExtract, targetVar: varName, targs: args)
    else:
      # Special variable: $X, $Y, etc.
      # Use the full name with $ prefix
      SetTarget(kind: stVar, tname: "$" & name, tsubs: @[])
  elif p.peek() == tokAt:
    # Indirect: @X or @X(sub1, sub2)
    discard p.advance()
    # Read just the variable name (not subscripts)
    var indirectExpr: Expr
    if p.peek() == tokWord:
      let name = p.readWord()
      indirectExpr = Expr(kind: eVar, vname: name, subs: @[])
    elif p.peek() == tokCaret:
      discard p.advance()
      let name = p.readWord()
      indirectExpr = Expr(kind: eVar, vname: "^" & name, subs: @[])
    else:
      indirectExpr = parsePrimary(p)
    var subs: seq[Expr] = @[]
    # Check for subscripts: @X(sub1, sub2)
    if p.peek() == tokLParen:
      discard p.advance()
      while true:
        subs.add(parseExpr(p))
        if p.peek() == tokComma:
          discard p.advance()
        else:
          break
      if p.peek() == tokRParen:
        discard p.advance()
    SetTarget(kind: stIndirect, indirectExpr: indirectExpr, indirectSubs: subs)
  else:
    let (name, subs) = parseVarRef(p)
    SetTarget(kind: stVar, tname: name, tsubs: subs)

## parseVarRef — Parse a Variable Reference
##
## Returns (name, subscripts). The name includes the leading "^" for globals.
proc parseVarRef(p: var Parser): (string, seq[Expr]) =
  var name: string
  if p.peek() == tokCaret:
    discard p.advance()
    if p.peek() == tokLParen:
      # Naked reference: ^(subs...)
      name = "^"
    else:
      name = "^" & p.readWord()
  else:
    name = p.readWord()
  let subs = parseSubscripts(p)
  (name, subs)

## parseWriteArgs — Parse WRITE Arguments
##
## WRITE syntax: WRITE expr,expr,...,!,#,?n
##
## WRITE arguments can be:
##   - Expressions (evaluated and printed)
##   - ! (newline)
##   - # (form feed)
##   - ?n (tab to column n)
##
## Design Decision: We treat format controls as separate argument
## types (wrNewline, wrFormFeed, wrColumn) rather than expressions,
## because they have no value — they're pure side effects.
proc parseWriteArgs(p: var Parser): seq[WriteArg] =
  var args: seq[WriteArg] = @[]
  while true:
    case p.peek()
    of tokOr:
      # ! → newline
      discard p.advance()
      args.add WriteArg(kind: wrNewline)
    of tokHash:
      # # → form feed
      discard p.advance()
      args.add WriteArg(kind: wrFormFeed)
    of tokQuestion:
      # ?n → tab to column n
      discard p.advance()
      var n = 0
      if p.peek() == tokNumber:
        try:
          n = parseInt(p.cur.text)
        except ValueError:
          n = 0
        discard p.advance()
      args.add WriteArg(kind: wrColumn, col: n)
    else:
      if isExprStart(p):
        args.add WriteArg(kind: wrExpr, wexpr: p.parseExpr())
      else:
        break
    if p.peek() == tokComma:
      discard p.advance()
    else:
      break
  args

## parseForSpec — Parse FOR Specification
##
## FOR syntax variants:
##   FOR              (argumentless FOR — loops until QUIT)
##   FOR I=expr       (infinite FOR, step defaults to 1)
##   FOR I=expr:expr  (FOR with limit)
##   FOR I=expr:expr:expr  (FOR with step and limit)
##
## Design Decision: We use peek2 to look two tokens ahead to determine
## if a word followed by '=' is a FOR variable. This is necessary because
## "FOR I=1:1:3" has I as the variable, but "FOR I QUIT" has I as a
## command argument (which doesn't make sense for FOR — but we need to
## distinguish the cases).
proc parseForArg(p: var Parser, varName: string): ForSpec =
  ## One FOR argument per §7.2.6: bare expr = one iteration;
  ## expr:inc = infinite; expr:inc:expr = counted.
  result = ForSpec(varName: varName, initE: nil, stepE: nil, limitE: nil,
                   hasLimit: false)
  result.initE = p.parseExpr()
  if p.peek() == tokColon:
    discard p.advance()
    let s = p.parseExpr()
    if p.peek() == tokColon:
      discard p.advance()
      result.stepE = s
      result.limitE = p.parseExpr()
      result.hasLimit = true
    else:
      result.stepE = s
  else:
    result.onceOnly = true

proc parseForSpec(p: var Parser): ForSpec =
  result = ForSpec(varName: "", initE: nil, stepE: nil, limitE: nil)
  if p.peek() == tokWord:
    if p.peek2() == tokEq:
      # FOR var=arg,arg,arg — comma-separated args share the loop variable
      let varName = p.readWord()
      discard p.advance() # consume =
      result = parseForArg(p, varName)
      while p.peek() == tokComma:
        discard p.advance()
        result.altSpecs.add(parseForArg(p, varName))

## parseKill — Parse KILL Command
##
## KILL has two forms:
##   KILL var,var,...           (kill listed variables)
##   KILL (keep,keep,...)      (kill everything EXCEPT listed variables)
##
## Design Decision: We detect the exception form by checking for '('
## as the first token. The exception form produces cKillExcept, while
## the normal form produces cKill.
proc parseKill(p: var Parser): Cmd =
  if p.peek() == tokLParen:
    # KILL (var,var,...) — kill all except listed
    discard p.advance()
    var vars: seq[Expr] = @[]
    while true:
      let (name, subs) = parseVarRef(p)
      vars.add Expr(kind: eVar, vname: name, subs: subs)
      if p.peek() == tokComma:
        discard p.advance()
      else:
        break
    if p.peek() == tokRParen:
      discard p.advance()
    Cmd(kind: cKillExcept, killKeep: vars)
  elif p.peek() == tokWord or p.peek() == tokCaret:
    # KILL var,var,... — parse as variable list
    # A command word after the two-space separator ends the list (§7.1.1),
    # e.g. "KILL  WRITE X" is bare KILL followed by WRITE.
    var refs: seq[Expr] = @[]
    while true:
      if p.peek() == tokWord and cmdSepBefore(p, p.cur) and
          isCommandWord(p, p.cur.text):
        break
      let (name, subs) = parseVarRef(p)
      refs.add Expr(kind: eVar, vname: name, subs: subs)
      if p.peek() == tokComma:
        discard p.advance()
      else:
        break
    Cmd(kind: cKill, killRefs: refs)
  else:
    # KILL without arguments — kill all local variables
    Cmd(kind: cKill, killRefs: @[])

## parseExprList — Parse a Comma-Separated Expression List
proc parseExprList(p: var Parser): seq[Expr] =
  var list: seq[Expr] = @[]
  if not isExprStart(p):
    return list
  while true:
    # Stop if we hit a command word at command position
    if p.atCommandPos():
      break
    list.add p.parseExpr()
    if p.peek() == tokComma:
      discard p.advance()
    else:
      break
  list

## parseNameList — Parse a Comma-Separated Name List
##
## Used for NEW: NEW A,B,C
proc parseNameList(p: var Parser): seq[string] =
  var names: seq[string] = @[]
  while true:
    names.add p.readWord()
    if p.peek() == tokComma:
      discard p.advance()
    else:
      break
  names

## parseMergePairs — Parse MERGE Command Arguments
##
## MERGE syntax: MERGE dst=src,dst=src,...
##
## Design Decision: We only parse the variable names (not subscripts)
## for MERGE pairs. The standard allows MERGE A(1)=B(2) but this
## implementation simplifies to whole-variable MERGE.
proc parseMergePairs(p: var Parser): seq[(string, string)] =
  var pairs: seq[(string, string)] = @[]
  while true:
    let (dst, _) = parseVarRef(p)
    if p.peek() == tokEq:
      discard p.advance()
    let (src, _) = parseVarRef(p)
    pairs.add (dst, src)
    if p.peek() == tokComma:
      discard p.advance()
    else:
      break
  pairs
