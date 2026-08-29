# main.nim — CLI entry point for nimm M/MUMPS interpreter
#
# Usage:
#   nimm -V                                       # Show version
#   nimm -x 'WRITE "Hello, World!"'           # Execute code directly
#   nimm -r file.m -e 'DO ENTRY'              # Load routine, execute entry point
#   nimm -d /path/to/db -x 'SET ^X=1'        # With LMDB database
#   nimm --repl                                # Interactive REPL
#   nimm -m strict -x 'SET X=1'               # Strict mode

const Version* = "0.1.8"

import os
import strutils
import tables
import osproc

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
import network
import bytecode
import algorithm

type
  CliArgs = object
    code: string
    routineFiles: seq[string]
    dbPath: string
    mode: string
    repl: bool
    mcp: bool
    mcpPort: int
    apiKey: string
    auditLog: string
    allowWrite: bool
    allowNetwork: bool
    allowShell: bool
    allowFile: bool
    shellAllowlist: string
    networkAllowlist: string
    fileAllowlist: string
    useBytecode: bool
    pemdas: bool       # --pemdas: use operator precedence (math precedence)
    lint: bool          # --lint: analyze code without executing
    lintStrict: bool    # --lint-strict: exit non-zero on warnings/errors
    parentJobNum: int  # -p: parent M job number (set by JOB command)
    argv: seq[string]  # positional script arguments ($ZARG)

proc parseArgs(): CliArgs =
  result.code = ""
  result.routineFiles = @[]
  result.dbPath = ""
  result.mode = "nimm"
  result.repl = false
  result.mcp = false
  result.mcpPort = 8080
  result.apiKey = ""
  result.auditLog = ""
  result.allowWrite = false
  result.allowNetwork = false
  result.allowShell = false
  result.allowFile = false
  result.shellAllowlist = ""
  result.networkAllowlist = ""
  result.fileAllowlist = ""
  result.useBytecode = false
  result.pemdas = false
  result.lint = false
  result.lintStrict = false
  result.parentJobNum = 0
  result.argv = @[]

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
          result.routineFiles.add(args[i])
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
      of "allow-write":
        result.allowWrite = true
      of "allow-network":
        result.allowNetwork = true
      of "allow-shell":
        result.allowShell = true
      of "allow-file":
        result.allowFile = true
      of "shell-allowlist":
        if i + 1 < args.len:
          inc i
          result.shellAllowlist = args[i]
      of "network-allowlist":
        if i + 1 < args.len:
          inc i
          result.networkAllowlist = args[i]
      of "file-allowlist":
        if i + 1 < args.len:
          inc i
          result.fileAllowlist = args[i]
      of "bytecode":
        result.useBytecode = true
      of "pemdas":
        result.pemdas = true
      of "lint":
        result.lint = true
      of "lint-strict":
        result.lintStrict = true
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
        echo "  --allow-write Enable write commands (SET, KILL, LOCK, MERGE, transactions)"
        echo "  --allow-network Enable network commands (NIOPEN/NILISTEN/NIREAD/NIWRITE/NICLOSE)"
        echo "  --allow-shell Enable shell access (ZSYSTEM)"
        echo "  --allow-file Enable file I/O (OPEN/READ/WRITE/CLOSE)"
        echo "  --shell-allowlist CMD Allowlist for ZSYSTEM commands (comma-separated)"
        echo "  --network-allowlist HOST:PORT Allowlist for network connections (comma-separated)"
        echo "  --file-allowlist PATH Allowlist for file paths (comma-separated)"
        echo "  --bytecode   Enable bytecode VM for compiled routines"
        echo "  --lint       Analyze loaded routine(s)/code, do not execute"
        echo "  --lint-strict Exit non-zero on warnings or errors (implies --lint)"
        echo "  --pemdas     Use standard math precedence (2+3*4 = 14, not 20)"
        echo "  -h/--help     Show this help"
        quit(0)
      else:
        discard
    else:
      # Positional arg — script argument ($ZARG); first is also code for
      # backward-compat (nimm 'W 1') when no -x/-e/-r was given.
      result.argv.add(arg)
      if result.code.len == 0 and result.routineFiles.len == 0:
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
  eng.useBytecode = args.useBytecode
  setDoDepthRef(eng.doDepth)
  ev.setInspector(eng.inspector)
  setArgv(args.argv)
  setPemdas(args.pemdas)
  setLexerMode(rt.config.allowLowercase)

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

  # Load routine files if specified
  for routineFile in args.routineFiles:
    if not fileExists(routineFile):
      echo "Error: File not found: " & routineFile
      quit(1)
    let routine = rt.loadRoutine(routineFile)
    rt.currentRoutine = routine.name
    rt.currentFile = routineFile

  # Lint mode (#384): analyze routines + code and report without executing.
  if args.lint or args.lintStrict:
    var totalErrors = 0
    var totalWarnings = 0
    if args.routineFiles.len > 0:
      for routineFile in args.routineFiles:
        let name = extractFilename(routineFile).splitFile().name.toUpperAscii()
        if name in rt.routines:
          let r = rt.routines[name]
          let srcLines = if r.originalLines.len > 0: r.originalLines else: r.lines
          echo "=== " & name & " ==="
          let report = analyzeLines(srcLines)
          echo formatReport(report)
          totalErrors += report.errorCount
          totalWarnings += report.warningCount
    if args.code.len > 0:
      echo "=== <code> ==="
      let report = analyzeRoutine(args.code)
      echo formatReport(report)
      totalErrors += report.errorCount
      totalWarnings += report.warningCount
    # Exit non-zero on errors (--lint) or errors+warnings (--lint-strict)
    if args.lintStrict:
      if totalErrors > 0 or totalWarnings > 0: quit(1)
    elif totalErrors > 0:
      quit(1)
    quit(0)

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
        let execResult = execCode(eng, code)
        let output = eng.getOutput()
        return %*{"result": execResult, "output": output}
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

    # Write tools (Phase 2 — require --allow-write)
    if args.allowWrite:
      mcp.registerTool("set_global", "Set a global variable value", %*{
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "Global name (e.g. ^X)"},
          "subscripts": {"type": "array", "items": {"type": "string"}, "description": "Subscripts"},
          "value": {"type": "string", "description": "Value to set"}
        },
        "required": ["name", "value"]
      }, proc(params: JsonNode): JsonNode =
        let name = params["name"].getStr()
        let value = params["value"].getStr()
        var subs: seq[string] = @[]
        if params.hasKey("subscripts"):
          for s in params["subscripts"]:
            subs.add(s.getStr())
        try:
          eng.globals[].set(name, subs, value)
          return %*{"status": "ok", "name": name, "subscripts": subs, "value": value}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("kill_global", "Kill a global variable", %*{
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "Global name (e.g. ^X)"},
          "subscripts": {"type": "array", "items": {"type": "string"}, "description": "Subscripts (empty = kill all)"}
        },
        "required": ["name"]
      }, proc(params: JsonNode): JsonNode =
        let name = params["name"].getStr()
        var subs: seq[string] = @[]
        if params.hasKey("subscripts"):
          for s in params["subscripts"]:
            subs.add(s.getStr())
        try:
          eng.globals[].kill(name, subs)
          return %*{"status": "ok", "name": name, "subscripts": subs}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("lock_resource", "Acquire a lock on a resource", %*{
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "Resource name (e.g. ^X)"}
        },
        "required": ["name"]
      }, proc(params: JsonNode): JsonNode =
        let name = params["name"].getStr()
        try:
          eng.globals[].acquireLock(name)
          return %*{"status": "ok", "name": name}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("unlock_resource", "Release a lock on a resource", %*{
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "Resource name (e.g. ^X)"}
        },
        "required": ["name"]
      }, proc(params: JsonNode): JsonNode =
        let name = params["name"].getStr()
        try:
          eng.globals[].releaseLock(name)
          return %*{"status": "ok", "name": name}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("begin_transaction", "Start a new transaction (TSTART)", %*{
        "type": "object",
        "properties": {}
      }, proc(params: JsonNode): JsonNode =
        try:
          eng.globals[].tstart()
          return %*{"status": "ok", "tlevel": eng.globals[].txn.levels.len}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("commit_transaction", "Commit current transaction (TCOMMIT)", %*{
        "type": "object",
        "properties": {}
      }, proc(params: JsonNode): JsonNode =
        try:
          eng.globals[].tcommit()
          return %*{"status": "ok", "tlevel": eng.globals[].txn.levels.len}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("rollback_transaction", "Rollback current transaction (TROLLBACK)", %*{
        "type": "object",
        "properties": {}
      }, proc(params: JsonNode): JsonNode =
        try:
          eng.globals[].trollback()
          return %*{"status": "ok", "tlevel": eng.globals[].txn.levels.len}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

    # Network tools (Phase 3 — require --allow-network)
    if args.allowNetwork:
      mcp.registerTool("open_connection", "Open a network connection (NIOPEN)", %*{
        "type": "object",
        "properties": {
          "protocol": {"type": "string", "description": "Protocol (tcp)"},
          "host": {"type": "string", "description": "Host to connect to"},
          "port": {"type": "integer", "description": "Port number"}
        },
        "required": ["protocol", "host", "port"]
      }, proc(params: JsonNode): JsonNode =
        let protocol = params["protocol"].getStr()
        let host = params["host"].getStr()
        let port = params["port"].getInt()
        try:
          let connId = eng.network.niopen(protocol, host, port)
          return %*{"status": "ok", "connectionId": connId}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("listen_port", "Listen for connections (NILISTEN)", %*{
        "type": "object",
        "properties": {
          "port": {"type": "integer", "description": "Port to listen on"}
        },
        "required": ["port"]
      }, proc(params: JsonNode): JsonNode =
        let port = params["port"].getInt()
        try:
          let listenerId = eng.network.nilisten(port)
          return %*{"status": "ok", "listenerId": listenerId}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("accept_connection", "Accept a connection (NIACCEPT)", %*{
        "type": "object",
        "properties": {
          "listenerId": {"type": "integer", "description": "Listener ID"}
        },
        "required": ["listenerId"]
      }, proc(params: JsonNode): JsonNode =
        let listenerId = params["listenerId"].getInt()
        try:
          let connId = eng.network.niaccept(listenerId)
          return %*{"status": "ok", "connectionId": connId}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("read_connection", "Read data from connection (NIREAD)", %*{
        "type": "object",
        "properties": {
          "connectionId": {"type": "integer", "description": "Connection ID"},
          "size": {"type": "integer", "description": "Bytes to read (default 4096)"}
        },
        "required": ["connectionId"]
      }, proc(params: JsonNode): JsonNode =
        let connId = params["connectionId"].getInt()
        let size = if params.hasKey("size"): params["size"].getInt() else: 4096
        try:
          let data = eng.network.niread(connId, size)
          return %*{"status": "ok", "data": data, "bytes": data.len}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("write_connection", "Write data to connection (NIWRITE)", %*{
        "type": "object",
        "properties": {
          "connectionId": {"type": "integer", "description": "Connection ID"},
          "data": {"type": "string", "description": "Data to write"}
        },
        "required": ["connectionId", "data"]
      }, proc(params: JsonNode): JsonNode =
        let connId = params["connectionId"].getInt()
        let data = params["data"].getStr()
        try:
          let ok = eng.network.niwrite(connId, data)
          return %*{"status": if ok: "ok" else: "error"}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("close_connection", "Close a connection (NICLOSE)", %*{
        "type": "object",
        "properties": {
          "connectionId": {"type": "integer", "description": "Connection ID"}
        },
        "required": ["connectionId"]
      }, proc(params: JsonNode): JsonNode =
        let connId = params["connectionId"].getInt()
        try:
          let ok = eng.network.niclose(connId)
          return %*{"status": if ok: "ok" else: "error"}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

    # Shell tools (Phase 3 — require --allow-shell)
    if args.allowShell:
      mcp.registerTool("execute_shell", "Execute OS command (ZSYSTEM)", %*{
        "type": "object",
        "properties": {
          "command": {"type": "string", "description": "Command to execute"}
        },
        "required": ["command"]
      }, proc(params: JsonNode): JsonNode =
        let command = params["command"].getStr()
        # Check allowlist if configured
        if args.shellAllowlist.len > 0:
          let allowed = args.shellAllowlist.split(",")
          var permitted = false
          for a in allowed:
            if command.startsWith(a.strip()):
              permitted = true
              break
          if not permitted:
            return %*{"error": "Command not in allowlist", "command": command}
        try:
          let exitCode = execShellCmd(command)
          return %*{"status": "ok", "exitCode": exitCode}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

    # File I/O tools (Phase 3 — require --allow-file)
    if args.allowFile:
      mcp.registerTool("read_file", "Read a file", %*{
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "File path"}
        },
        "required": ["path"]
      }, proc(params: JsonNode): JsonNode =
        let path = params["path"].getStr()
        # Check allowlist if configured
        if args.fileAllowlist.len > 0:
          let allowed = args.fileAllowlist.split(",")
          var permitted = false
          for a in allowed:
            if path.startsWith(a.strip()):
              permitted = true
              break
          if not permitted:
            return %*{"error": "Path not in allowlist", "path": path}
        try:
          let content = readFile(path)
          return %*{"status": "ok", "content": content, "size": content.len}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

      mcp.registerTool("write_file", "Write to a file", %*{
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "File path"},
          "content": {"type": "string", "description": "Content to write"}
        },
        "required": ["path", "content"]
      }, proc(params: JsonNode): JsonNode =
        let path = params["path"].getStr()
        let content = params["content"].getStr()
        # Check allowlist if configured
        if args.fileAllowlist.len > 0:
          let allowed = args.fileAllowlist.split(",")
          var permitted = false
          for a in allowed:
            if path.startsWith(a.strip()):
              permitted = true
              break
          if not permitted:
            return %*{"error": "Path not in allowlist", "path": path}
        try:
          writeFile(path, content)
          return %*{"status": "ok", "path": path, "bytes": content.len}
        except:
          return %*{"error": getCurrentExceptionMsg()}
      )

    # Introspection tools (#389 Phase F) — reuse the A–C formatters/APIs.
    mcp.registerTool("list_routines", "List loaded M routines (name, labels, lines)", %*{
      "type": "object",
      "properties": {}
    }, proc(params: JsonNode): JsonNode =
      var routines = newJArray()
      var names: seq[string] = @[]
      for n in rt.routines.keys: names.add(n)
      names.sort()
      for n in names:
        let r = rt.routines[n]
        routines.add(%*{"name": n, "labels": r.labels.len,
                         "lines": r.lines.len, "file": r.filePath})
      return %*{"routines": routines}
    )

    mcp.registerTool("list_variables", "List local variables in the current scope", %*{
      "type": "object",
      "properties": {}
    }, proc(params: JsonNode): JsonNode =
      var variables = newJArray()
      for (name, subs) in eng.globals[].listLocals():
        let kind = if name.startsWith("^"): "global" else: "local"
        variables.add(%*{"name": name, "subscripts": subs,
                          "value": eng.globals[].get(name, subs), "kind": kind})
      return %*{"variables": variables}
    )

    mcp.registerTool("get_source", "Get the source of a loaded routine", %*{
      "type": "object",
      "properties": {"routine": {"type": "string", "description": "Routine name"}},
      "required": ["routine"]
    }, proc(params: JsonNode): JsonNode =
      let name = params["routine"].getStr().toUpperAscii()
      if name notin rt.routines:
        return %*{"error": "Routine not found: " & name}
      let r = rt.routines[name]
      return %*{"name": name, "source": r.originalLines}
    )

    mcp.registerTool("disassemble", "Disassemble a routine's bytecode", %*{
      "type": "object",
      "properties": {"routine": {"type": "string", "description": "Routine name"}},
      "required": ["routine"]
    }, proc(params: JsonNode): JsonNode =
      let name = params["routine"].getStr().toUpperAscii()
      if name notin rt.routines:
        return %*{"error": "Routine not found: " & name}
      try:
        eng.ensureBytecode(name)
        var dump = ""
        for bc in rt.routines[name].bytecodeCache:
          if bc != nil:
            dump.add(disassemble(bc))
        return %*{"name": name, "bytecode": dump}
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
      # Reliable exit codes: top-level QUIT value → process exit status (#368)
      if eng.quitValue.len > 0:
        try:
          quit(parseInt(eng.quitValue))
        except ValueError:
          quit(0)
      # Check for error indicators
      if result.startsWith("Error") or result.startsWith("M Error"):
        quit(1)
    except:
      echo "Error: " & getCurrentExceptionMsg()
      quit(1)
  elif args.routineFiles.len > 0:
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
