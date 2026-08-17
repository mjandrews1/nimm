# repl.nim — Interactive REPL for nimm
# Provides Read-Eval-Print Loop with line editing and special commands

import strutils
import os
import engine
import runtime

type
  ReplState* = object
    ## REPL state
    history: seq[string]
    maxHistory: int

proc newReplState(): ReplState =
  result.history = @[]
  result.maxHistory = 100

proc addToHistory(state: var ReplState, line: string) =
  ## Add line to history
  if line.strip().len > 0:
    state.history.add(line)
    if state.history.len > state.maxHistory:
      state.history.delete(0)

proc showHelp() =
  ## Show REPL help
  echo ""
  echo "nimm REPL Commands:"
  echo "  /quit, /exit    — Exit REPL"
  echo "  /load FILE      — Load routine from file"
  echo "  /clear          — Clear screen"
  echo "  /history        — Show command history"
  echo "  /vars           — Show local variables"
  echo "  /globals        — Show global variables"
  echo "  /help           — Show this help"
  echo ""

proc showHistory(state: ReplState) =
  ## Show command history
  echo ""
  if state.history.len == 0:
    echo "No history"
  else:
    for i, h in state.history:
      echo "  " & $(i + 1) & ": " & h
  echo ""

proc repl*(eng: var Engine, rt: var Runtime) =
  ## Interactive REPL
  var state = newReplState()
  
  echo ""
  echo "nimm M/MUMPS REPL"
  echo "=================="
  echo "Type M code or /help for commands"
  echo ""
  
  while true:
    stdout.write("nimm> ")
    stdout.flushFile()
    
    var line: string
    try:
      line = stdin.readLine()
    except EOFError:
      echo ""
      break
    except:
      echo "Error reading input"
      continue
    
    let trimmed = line.strip()
    
    # Handle empty line
    if trimmed.len == 0:
      continue
    
    # Handle special commands
    if trimmed.startsWith("/"):
      let cmd = trimmed.toLowerAscii()
      case cmd
      of "/quit", "/exit":
        echo "Goodbye!"
        break
      of "/help":
        showHelp()
      of "/clear":
        # Clear screen (ANSI escape)
        echo "\x1b[2J\x1b[H"
      of "/history":
        showHistory(state)
      of "/vars":
        # Show local variables (simplified)
        echo ""
        echo "Local variables: (use WRITE to inspect)"
        echo ""
      of "/globals":
        # Show global variables (simplified)
        echo ""
        echo "Global variables: (use WRITE ^ to inspect)"
        echo ""
      else:
        # Check for /load command
        if cmd.startsWith("/load "):
          let filename = trimmed[6..^1].strip()
          if fileExists(filename):
            try:
              let routine = rt.loadRoutine(filename)
              rt.currentRoutine = routine.name
              echo "Loaded: " & routine.name & " (" & $routine.lines.len & " lines)"
            except:
              echo "Error loading file: " & getCurrentExceptionMsg()
          else:
            echo "File not found: " & filename
        else:
          echo "Unknown command: " & trimmed
          echo "Type /help for available commands"
      continue
    
    # Add to history
    state.addToHistory(trimmed)
    
    # Execute M code
    try:
      eng.clearOutput()
      let result = eng.execute(parseLine(trimmed))
      let output = eng.getOutput()
      if output.len > 0:
        echo output
      if result.len > 0 and result != "QUIT":
        echo "=> " & result
    except:
      echo "Error: " & getCurrentExceptionMsg()
