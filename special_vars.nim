# special_vars.nim — Special variables for nimm
# Implements $DEVICE, $ECODE, $ETRAP, $HOROLOG, $IO, $JOB
# $KEY, $PRINCIPAL, $QUIT, $REFERENCE, $STORAGE
# $STACK, $SYSTEM, $TEST, $X, $Y

import os
import times
import strutils
import osproc
import globals

var
  device: string = ""
  ecode: string = ""
  etrap: string = ""
  io: string = "stdout"
  key: string = ""
  principal: string = "stdin"
  quit: string = "0"
  reference: string = ""
  test: string = "1"
  x: int = 0
  y: int = 0
  zeof: string = "0"  # $ZEOF - end-of-file flag

proc getDevice(): string =
  return device

proc setDevice(val: string) =
  device = val

proc getEcode(): string =
  return ecode

proc setEcode(val: string) =
  ecode = val

proc getEtrap(): string =
  return etrap

proc setEtrap(val: string) =
  etrap = val

proc getHorolog(): string =
  # $HOROLOG returns days since Dec 31, 1840,seconds since midnight
  let now = times.now()
  # Calculate days since Dec 31, 1840
  # This is a simplified calculation
  let year = now.year
  let month = now.month.ord
  let day = now.monthday
  
  # Days from 1840 to current year
  var days = 0
  for y in 1840..<year:
    if y mod 4 == 0 and (y mod 100 != 0 or y mod 400 == 0):
      days += 366
    else:
      days += 365
  
  # Days in current year
  let monthDays = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  for m in 1..<month:
    days += monthDays[m]
    if m == 2 and (year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0)):
      days += 1
  days += day
  
  let seconds = now.hour * 3600 + now.minute * 60 + now.second
  return $days & "," & $seconds

proc getIo(): string =
  return io

proc setIo(val: string) =
  io = val

proc getJob(): string =
  # $JOB returns current process ID
  return $os.getCurrentProcessId()

proc getKey(): string =
  return key

proc setKey(val: string) =
  key = val

proc getPrincipal(): string =
  return principal

proc setPrincipal(val: string) =
  principal = val

proc getQuit(): string =
  return quit

proc setQuit(val: string) =
  quit = val

proc getReference(): string =
  return reference

proc setReference(val: string) =
  reference = val

proc getStorage(): string =
  # $STORAGE returns available memory in bytes
  try:
    when defined(linux):
      let meminfo = readFile("/proc/meminfo")
      for line in meminfo.splitLines():
        if line.startsWith("MemAvailable:"):
          let parts = line.split()
          if parts.len >= 2:
            let kb = parseInt(parts[1])
            return $(kb * 1024)
    elif defined(macosx):
      let (output, _) = execCmdEx("sysctl -n hw.memsize")
      let bytes = parseInt(output.strip())
      return $bytes
  except:
    discard
  return "1000000000"  # Fallback: 1GB

var stackDepth: int = 0

proc getStack(): string =
  # $STACK returns call stack depth
  return $stackDepth

proc pushStack*() =
  inc stackDepth

proc popStack*() =
  if stackDepth > 0:
    dec stackDepth

proc resetStack*() =
  stackDepth = 0

proc getSystem(): string =
  # $SYSTEM returns system info
  return "nimm/1.0"

proc getTest(): string =
  return test

proc setTest(val: string) =
  test = val

proc getX(): string =
  return $x

proc setX(val: string) =
  try:
    x = parseInt(val)
  except:
    discard

proc getY(): string =
  return $y

proc setY(val: string) =
  try:
    y = parseInt(val)
  except:
    discard

proc getZeof(): string =
  return zeof

proc setZeof(val: string) =
  zeof = val

proc registerAllSpecialVars*(g: var Globals) =
  ## Register all special variables with the globals system
  g.registerSpecialVar("$DEVICE", getDevice, setDevice)
  g.registerSpecialVar("$ECODE", getEcode, setEcode)
  g.registerSpecialVar("$ETRAP", getEtrap, setEtrap)
  g.registerSpecialVar("$HOROLOG", getHorolog)
  g.registerSpecialVar("$IO", getIo, setIo)
  g.registerSpecialVar("$JOB", getJob)
  g.registerSpecialVar("$KEY", getKey, setKey)
  g.registerSpecialVar("$PRINCIPAL", getPrincipal, setPrincipal)
  g.registerSpecialVar("$QUIT", getQuit, setQuit)
  g.registerSpecialVar("$REFERENCE", getReference, setReference)
  g.registerSpecialVar("$STORAGE", getStorage)
  g.registerSpecialVar("$STACK", getStack)
  g.registerSpecialVar("$SYSTEM", getSystem)
  g.registerSpecialVar("$TEST", getTest, setTest)
  g.registerSpecialVar("$X", getX, setX)
  g.registerSpecialVar("$Y", getY, setY)
  g.registerSpecialVar("$ZEOF", getZeof, setZeof)
