# main.nim — CLI entry point for nimm M/MUMPS interpreter
#
# Usage:
#   nimm -x 'WRITE "Hello, World!"'           # Execute code directly
#   nimm -r file.m -e 'DO ENTRY'              # Load routine, execute entry point
#   nimm -d /path/to/db -x 'SET ^X=1'        # With LMDB database
#   nimm --repl                                # Interactive REPL
#   nimm -m strict -x 'SET X=1'               # Strict mode

import os
import strutils
import tables

import ast
import globals
import evaluator
import runtime
import engine
import lexer
import parser

type
  CliArgs = object
    code: string
    routineFile: string
    dbPath: string
    mode: string
    repl: bool

proc parseArgs(): CliArgs =
  result.code = ""
  result.routineFile = ""
  result.dbPath = ""
  result.mode = "nimm"
  result.repl = false

  let args = os.commandLineParams()
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let key = arg.strip(chars = {'-'})
      case key
      of "x":
        if i + 1 < args.len:
          inc i
          result.code = args[i]
      of "r":
        if i + 1 < args.len:
          inc i
          result.routineFile = args[i]
      of "e":
        if i + 1 < args.len:
          inc i
          if result.code.len == 0:
            result.code = args[i]
      of "d":
        if i + 1 < args.len:
          inc i
          result.dbPath = args[i]
      of "m":
        if i + 1 < args.len:
          inc i
          result.mode = args[i].toLowerAscii()
      of "repl":
        result.repl = true
      of "h", "help":
        echo "nimm — M/MUMPS Interpreter"
        echo ""
        echo "Usage:"
        echo "  nimm -x 'CODE'              Execute code directly"
        echo "  nimm -r file.m -e 'CODE'    Load routine, execute code"
        echo "  nimm -d /path/to/db -x CODE With LMDB database"
        echo "  nimm --repl                  Interactive REPL"
        echo "  nimm -m MODE -x CODE        Set mode (nimm|strict|rsm)"
        echo ""
        echo "Options:"
        echo "  -x CODE    Execute M code string"
        echo "  -r FILE    Load routine from file"
        echo "  -e CODE    Code to execute after loading routine"
        echo "  -d PATH    LMDB database path"
        echo "  -m MODE    Mode: nimm (default), strict, rsm"
        echo "  --repl     Start interactive REPL"
        echo "  -h/--help  Show this help"
        quit(0)
      else:
        discard
    else:
      # Positional arg = code to execute
      if result.code.len == 0:
        result.code = arg
    inc i

proc execCode(eng: var Engine, code: string): string =
  ## Parse and execute a code string
  let line = parseLine(code)
  return eng.execute(line)

proc repl(eng: var Engine, rt: var Runtime) =
  ## Interactive REPL
  echo "nimm M/MUMPS REPL (type QUIT to exit)"
  echo "======================================="
  echo ""

  while true:
    stdout.write("nimm> ")
    stdout.flushFile()
    let line = stdin.readLine()
    
    if line.strip().toUpperAscii() == "QUIT":
      break
    
    if line.strip().len == 0:
      continue
    
    try:
      eng.clearOutput()
      let result = execCode(eng, line)
      let output = eng.getOutput()
      if output.len > 0:
        echo output
      if result.len > 0 and result != "QUIT":
        echo "=> " & result
    except:
      echo "Error: " & getCurrentExceptionMsg()

proc main() =
  let args = parseArgs()

  # Select mode
  var mode: Mode
  case args.mode
  of "strict":
    mode = Strict
  of "rsm":
    mode = RSM
  else:
    mode = nimm

  # Initialize components
  var g = newGlobals()
  var ev = newEvaluator(g)
  var rt = newRuntime(mode)
  var eng = newEngine(g, ev, rt)

  # Load LMDB if specified
  # TODO: Wire LMDB when storage/lmdb_store.nim is integrated

  # Load routine file if specified
  if args.routineFile.len > 0:
    if not fileExists(args.routineFile):
      echo "Error: File not found: " & args.routineFile
      quit(1)
    let routine = rt.loadRoutine(args.routineFile)
    rt.currentRoutine = routine.name

  # Execute or REPL
  if args.repl:
    repl(eng, rt)
  elif args.code.len > 0:
    try:
      eng.clearOutput()
      let result = execCode(eng, args.code)
      let output = eng.getOutput()
      if output.len > 0:
        echo output
    except:
      echo "Error: " & getCurrentExceptionMsg()
      quit(1)
  else:
    # No code or REPL — show help
    echo "nimm M/MUMPS Interpreter"
    echo "Usage: nimm -x 'CODE' | nimm -r file.m | nimm --repl"
    echo "Try 'nimm --help' for more options"

when isMainModule:
  main()
