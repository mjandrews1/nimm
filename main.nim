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
import osproc

import ast
import globals
import evaluator
import runtime
import engine
import lexer
import parser
import special_vars
import repl
import mcp_server
import json
import static_analysis

type
  CliArgs = object
    code: string
    routineFile: string
    dbPath: string
    mode: string
    repl: bool
    mcp: bool
    mcpPort: int
    apiKey: string
    auditLog: string
    parentJobNum: int  # -p: parent M job number (set by JOB command)

proc parseArgs(): CliArgs =
  result.code = ""
  result.routineFile = ""
  result.dbPath = ""
  result.mode = "nimm"
  result.repl = false
  result.mcp = false
  result.mcpPort = 8080
  result.apiKey = ""
  result.auditLog = ""
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
      of "mcp":
        result.mcp = true
      of "mcp-port":
        if i + 1 < args.len:
          inc i
          try:
            result.mcpPort = parseInt(args[i])
          except:
            discard
      of "api-key":
        if i + 1 < args.len:
          inc i
          result.apiKey = args[i]
      of "audit-log":
        if i + 1 < args.len:
          inc i
          result.auditLog = args[i]
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
        echo "  nimm --mcp                   Start MCP JSON-RPC server"
        echo "  nimm -m MODE -x CODE        Set mode (nimm|strict|rsm)"
        echo ""
        echo "Options:"
        echo "  -x CODE       Execute M code string"
        echo "  -r FILE       Load routine from file"
        echo "  -e CODE       Code to execute after loading routine"
        echo "  -d PATH       LMDB database path"
        echo "  -m MODE       Mode: nimm (default), strict, rsm"
        echo "  --repl        Start interactive REPL"
        echo "  --mcp         Start MCP JSON-RPC server"
        echo "  --mcp-port N  MCP server port (default: 8080)"
        echo "  --api-key KEY API key for MCP authentication"
        echo "  --audit-log F Audit log file for MCP server"
        echo "  -h/--help     Show this help"
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

  # Execute, REPL, or MCP server
  if args.mcp:
    # Start MCP JSON-RPC server (#331)
    var mcp = newMCPServer(port = args.mcpPort, apiKey = args.apiKey)
    if args.auditLog.len > 0:
      mcp.setAuditFile(args.auditLog)
    
    # Register read-only tools
    mcp.registerTool("execute_m_code", "Execute M/MUMPS code and return output", %*{
      "type": "object",
      "properties": {"code": {"type": "string", "description": "M code to execute"}},
      "required": ["code"]
    }, proc(params: JsonNode): JsonNode =
      let code = params["code"].getStr()
      try:
        eng.clearOutput()
        let result = execCode(eng, code)
        let output = eng.getOutput()
        return %*{"result": result, "output": output}
      except:
        return %*{"error": getCurrentExceptionMsg()}
    )
    
    mcp.registerTool("read_global", "Read a global variable value", %*{
      "type": "object",
      "properties": {
        "name": {"type": "string", "description": "Global name (e.g. ^X)"},
        "subscripts": {"type": "array", "items": {"type": "string"}, "description": "Subscripts"}
      },
      "required": ["name"]
    }, proc(params: JsonNode): JsonNode =
      let name = params["name"].getStr()
      var subs: seq[string] = @[]
      if params.hasKey("subscripts"):
        for s in params["subscripts"]:
          subs.add(s.getStr())
      let val = eng.globals[].get(name, subs)
      return %*{"name": name, "subscripts": subs, "value": val}
    )
    
    mcp.registerTool("run_tests", "Run conformance test suite", %*{
      "type": "object",
      "properties": {"suite": {"type": "string", "description": "Suite: iso, extended, unit"}}
    }, proc(params: JsonNode): JsonNode =
      let suite = if params.hasKey("suite"): params["suite"].getStr() else: "iso"
      try:
        case suite
        of "iso":
          let (output, exitCode) = execCmdEx("python3 tests/ansi_iso_m_conformance.py --impls nimm --runs 1")
          return %*{"suite": "iso", "output": output, "exitCode": exitCode}
        of "extended":
          let (output, exitCode) = execCmdEx("python3 tests/mumps_extended_conformance.py --impls nimm")
          return %*{"suite": "extended", "output": output, "exitCode": exitCode}
        of "unit":
          let (output, exitCode) = execCmdEx("./run_all_tests")
          return %*{"suite": "unit", "output": output, "exitCode": exitCode}
        else:
          return %*{"error": "Unknown suite: " & suite}
      except:
        return %*{"error": getCurrentExceptionMsg()}
    )
    
    mcp.registerTool("analyze_code", "Run static analysis on M code", %*{
      "type": "object",
      "properties": {"code": {"type": "string", "description": "M code to analyze"}},
      "required": ["code"]
    }, proc(params: JsonNode): JsonNode =
      let code = params["code"].getStr()
      try:
        let report = analyzeRoutine(code)
        return %*{"report": formatReport(report), "errors": report.errorCount, "warnings": report.warningCount}
      except:
        return %*{"error": getCurrentExceptionMsg()}
    )
    
    echo "Starting MCP server on port ", args.mcpPort
    mcp.start()
  elif args.repl:
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
