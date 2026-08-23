# main.nim — CLI entry point for nimm M/MUMPS interpreter
#
# Usage:
#   nimm -V                                       # Show version
#   nimm -x 'WRITE "Hello, World!"'           # Execute code directly
#   nimm -r file.m -e 'DO ENTRY'              # Load routine, execute entry point
#   nimm -d /path/to/db -x 'SET ^X=1'        # With LMDB database
#   nimm --repl                                # Interactive REPL
#   nimm -m strict -x 'SET X=1'               # Strict mode

const Version* = "0.1.6"

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
import special_vars
import repl

type
  CliArgs = object
    code: string
    routineFile: string
    dbPath: string
    mode: string
    repl: bool
    parentJobNum: int  # -p: parent M job number (set by JOB command)

proc parseArgs(): CliArgs =
  result.code = ""
  result.routineFile = ""
  result.dbPath = ""
  result.mode = "nimm"
  result.repl = false
  result.parentJobNum = 0

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
      of "p":
        if i + 1 < args.len:
          inc i
          try:
            result.parentJobNum = parseInt(args[i])
          except:
            discard
      of "m":
        if i + 1 < args.len:
          inc i
          result.mode = args[i].toLowerAscii()
      of "repl":
        result.repl = true
      of "V", "version":
        echo "nimm " & Version
        quit(0)
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
  var g = newGlobals(args.dbPath)
  g.registerAllSpecialVars()
  var rt = newRuntime(mode)
  var ev = newEvaluator(g, rt)
  var eng = newEngine(g, ev, rt)
  setDoDepthRef(eng.doDepth)
  ev.setInspector(eng.inspector)

  # Detect if spawned by JOB command (child process mode)
  # Uses -p flag (preferred) or NIMM_PARENT_JOB env var (fallback)
  if args.parentJobNum > 0:
    initChildJob(args.parentJobNum)
  else:
    let parentJobEnv = getEnv("NIMM_PARENT_JOB")
    if parentJobEnv.len > 0:
      try:
        let parentNum = parseInt(parentJobEnv)
        initChildJob(parentNum)
      except:
        discard

  # Load routine file if specified
  if args.routineFile.len > 0:
    if not fileExists(args.routineFile):
      echo "Error: File not found: " & args.routineFile
      quit(1)
    let routine = rt.loadRoutine(args.routineFile)
    rt.currentRoutine = routine.name
    rt.currentFile = args.routineFile

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
      # Check for error indicators
      if result.startsWith("Error") or result.startsWith("M Error"):
        quit(1)
    except:
      echo "Error: " & getCurrentExceptionMsg()
      quit(1)
  elif args.routineFile.len > 0:
    # Routine loaded but no code to execute — just exit
    discard
  else:
    # No code or REPL — show help
    echo "nimm M/MUMPS Interpreter"
    echo "Usage: nimm -x 'CODE' | nimm -r file.m | nimm --repl"
    echo "Try 'nimm --help' for more options"

  # Cleanup
  g.close()

when isMainModule:
  main()
