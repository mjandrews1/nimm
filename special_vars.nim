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
  io: string = "0"
  key: string = ""
  principal: string = "0"
  quit: string = "0"
  reference: string = ""
  globalsRef: ptr Globals = nil  # For $TLEVEL/$TRESTART access
  doDepthRef: ptr int = nil      # For $ESTACK access
  test: string = "1"
  x: int = 0
  y: int = 0
  zeof: string = "0"  # $ZEOF - end-of-file flag
  zerror: string = ""  # $ZERROR - error message
  zstatus: string = ""  # $ZSTATUS - status
  ztrap: string = ""  # $ZTRAP - trap handler
  jobNumber: int = 0  # M job number for $JOB
  isChildProcess: bool = false  # true if spawned by JOB command
  parentJobNum: int = 0  # parent's job number (negative in child)
  # $HOROLOG cache (1-second TTL)
  horologCache: string = ""
  horologCacheTime: int64 = 0  # epoch seconds when cache was written

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
  # Cache with 1-second TTL to avoid recomputing on every call
  let now = times.getTime()
  let epochSec = now.toUnix()
  if epochSec == horologCacheTime and horologCache.len > 0:
    return horologCache

  let nowTime = times.now()
  # Calculate days since Dec 31, 1840
  # This is a simplified calculation
  let year = nowTime.year
  let month = nowTime.month.ord
  let day = nowTime.monthday
  
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
  
  let seconds = nowTime.hour * 3600 + nowTime.minute * 60 + nowTime.second
  horologCache = $days & "," & $seconds
  horologCacheTime = epochSec
  return horologCache

proc getIo(): string =
  return io

proc setIo(val: string) =
  io = val

proc getJob(): string =
  # $JOB returns M job number (not OS PID)
  if isChildProcess:
    # Child process: return negative of parent's job number
    return $(-parentJobNum)
  elif jobNumber > 0:
    # Parent process with assigned job number
    return $jobNumber
  else:
    # Standalone process: root job is always 1
    return "1"

proc setJobNumber*(num: int) =
  ## Set the M job number for this process
  jobNumber = num

proc initChildJob*(parentNum: int) =
  ## Initialize as a child process spawned by JOB
  isChildProcess = true
  parentJobNum = parentNum

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

var storageCache: string = ""
var storageCacheTime: int64 = 0

proc getStorage(): string =
  # $STORAGE returns available memory in bytes
  # Cache for 60 seconds to avoid repeated subprocess/file reads (#327)
  let now = getTime().toUnix()
  if storageCache.len > 0 and now - storageCacheTime < 60:
    return storageCache
  try:
    when defined(linux):
      let meminfo = readFile("/proc/meminfo")
      for line in meminfo.splitLines():
        if line.startsWith("MemAvailable:"):
          let parts = line.split()
          if parts.len >= 2:
            let kb = parseInt(parts[1])
            storageCache = $(kb * 1024)
            storageCacheTime = now
            return storageCache
    elif defined(macosx):
      let (output, _) = execCmdEx("sysctl -n hw.memsize")
      let bytes = parseInt(output.strip())
      storageCache = $bytes
      storageCacheTime = now
      return storageCache
  except:
    discard
  if storageCache.len == 0:
    storageCache = "1000000000"  # Fallback: 1GB
  return storageCache

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

proc advanceDevicePos*(s: string) =
  ## Track $X/$Y for text written to the principal device (§6.3.22/23):
  ## newline advances $Y and resets $X; form feed resets $X; other
  ## characters advance $X by one.
  for ch in s:
    case ch
    of '\n':
      inc(y)
      x = 0
    of '\f':
      x = 0
    else:
      inc(x)

proc getEstack(): string =
  if doDepthRef != nil: return $doDepthRef[]
  return "0"
proc getTlevel(): string =
  if globalsRef != nil: return $globalsRef[].txn.levels.len
  return "0"
proc getTrestart(): string =
  if globalsRef != nil: return $globalsRef[].txn.trestart
  return "0"

proc getZeof(): string =
  return zeof

proc setZeof(val: string) =
  zeof = val

proc getZerror(): string =
  return zerror

proc setZerror(val: string) =
  zerror = val

proc getZstatus(): string =
  return zstatus

proc setZstatus(val: string) =
  zstatus = val

proc getZtrap(): string =
  return ztrap

proc setZtrap(val: string) =
  ztrap = val

proc getZversion(): string =
  return "nimm 0.1.7"

proc registerAllSpecialVars*(g: var Globals) =
  ## Register all special variables with the globals system
  globalsRef = addr g
  g.registerSpecialVar("$DEVICE", getDevice, setDevice)
  g.registerSpecialVar("$ECODE", getEcode, setEcode)
  g.registerSpecialVar("$ESTACK", getEstack)
  g.registerSpecialVar("$ETRAP", getEtrap, setEtrap)
  g.registerSpecialVar("$HOROLOG", getHorolog)
  g.registerSpecialVar("$H", getHorolog)
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
  g.registerSpecialVar("$TLEVEL", getTlevel)
  g.registerSpecialVar("$TRESTART", getTrestart)
  g.registerSpecialVar("$X", getX, setX)
  g.registerSpecialVar("$Y", getY, setY)
  g.registerSpecialVar("$ZEOF", getZeof, setZeof)
  g.registerSpecialVar("$ZERROR", getZerror, setZerror)
  g.registerSpecialVar("$ZSTATUS", getZstatus, setZstatus)
  g.registerSpecialVar("$ZTRAP", getZtrap, setZtrap)
  g.registerSpecialVar("$ZVERSION", getZversion)

proc setDoDepthRef*(depth: var int) =
  ## Wire $ESTACK to engine's doDepth (call after engine creation)
  doDepthRef = addr depth
