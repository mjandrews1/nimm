# jobs.nim — JOB command support for nimm
# Provides process spawning via posix_spawn and job table management

import posix
import os
import strutils
import times

# Platform-specific POSIX_SPAWN_SETSID constant
when defined(macosx):
  const POSIX_SPAWN_SETSID = cint(0x0400)
elif defined(linux):
  const POSIX_SPAWN_SETSID = cint(4)
else:
  const POSIX_SPAWN_SETSID = cint(0)

type
  JobStatus* = enum
    jsRunning
    jsCompleted
    jsFailed

  JobEntry* = object
    jobNumber*: int
    pid*: Pid
    entry*: string
    status*: JobStatus
    startTime*: float

  JobTable* = ref object
    entries*: seq[JobEntry]
    nextJobNumber*: int
    isChild*: bool
    parentJobNumber*: int

proc newJobTable*(): JobTable =
  result = JobTable(
    entries: @[],
    nextJobNumber: 1,
    isChild: false,
    parentJobNumber: 0
  )

  # Detect if this process was spawned by JOB
  let parentJobEnv = getEnv("NIMM_PARENT_JOB")
  if parentJobEnv.len > 0:
    result.isChild = true
    try:
      result.parentJobNumber = parseInt(parentJobEnv)
    except:
      result.parentJobNumber = 0

proc reapCompleted*(jt: JobTable) =
  ## Check for completed children (non-blocking)
  var i = 0
  while i < jt.entries.len:
    if jt.entries[i].status == jsRunning:
      var status: cint = 0
      let pid = waitpid(jt.entries[i].pid, status, WNOHANG)
      if pid > 0:
        if WIFEXITED(status) and WEXITSTATUS(status) == 0:
          jt.entries[i].status = jsCompleted
        else:
          jt.entries[i].status = jsFailed
    inc i

proc spawnJob*(jt: JobTable, entry: string, currentFile: string, dbPath: string = "", parentMJobNum: int = 1, timeout: int = 0): int =
  ## Spawn a new M process via posix_spawn. Returns job number.
  ## The child process runs nimm with the same routine file and executes the entry.
  let jobNum = jt.nextJobNumber
  inc jt.nextJobNumber

  let executable = getAppFilename()

  # Pass parent M job number as environment variable for child
  # (Command-line arg also available: -p parentJobNum)
  putEnv("NIMM_PARENT_JOB", $parentMJobNum)

  # Build arguments for the child process
  var args: seq[string]
  args.add(executable)
  args.add("-p")
  args.add($parentMJobNum)
  if dbPath.len > 0:
    args.add("-d")
    args.add(dbPath)
  if currentFile.len > 0:
    args.add("-r")
    args.add(currentFile)
  args.add("-e")
  args.add("DO " & entry)

  # Convert to C string array (null-terminated)
  var cArgs: seq[cstring]
  for arg in args:
    cArgs.add(cstring(arg))
  cArgs.add(nil)

  # Initialize spawn attributes
  var attr: Tposix_spawnattr
  if posix_spawnattr_init(attr) != 0:
    raise newException(IOError, "posix_spawnattr_init failed")

  # Initialize file actions — redirect stdin/stdout/stderr to /dev/null
  var fileActions: Tposix_spawn_file_actions
  if posix_spawn_file_actions_init(fileActions) != 0:
    discard posix_spawnattr_destroy(attr)
    raise newException(IOError, "posix_spawn_file_actions_init failed")

  let devNull = cstring("/dev/null")
  discard posix_spawn_file_actions_addopen(fileActions, 0, devNull, O_RDONLY, 0)
  discard posix_spawn_file_actions_addopen(fileActions, 1, devNull, O_WRONLY, 0)
  discard posix_spawn_file_actions_addopen(fileActions, 2, devNull, O_WRONLY, 0)

  # Set environment variable for child to detect it was spawned by JOB
  putEnv("NIMM_PARENT_JOB", $parentMJobNum)

  # Spawn the child process
  var childPid: Pid
  let cArgsArr = cast[cstringArray](addr cArgs[0])
  let ret = posix_spawn(childPid, cArgsArr[0], fileActions, attr, cArgsArr, nil)

  # Clean up env immediately
  delEnv("NIMM_PARENT_JOB")

  # Clean up spawn resources
  discard posix_spawnattr_destroy(attr)
  discard posix_spawn_file_actions_destroy(fileActions)

  if ret != 0:
    raise newException(IOError, "posix_spawn failed: error " & $ret)

  # Record in job table
  jt.entries.add(JobEntry(
    jobNumber: jobNum,
    pid: childPid,
    entry: entry,
    status: jsRunning,
    startTime: epochTime()
  ))

  return jobNum

proc getJob*(jt: JobTable, jobNumber: int): JobEntry =
  ## Get job entry by number
  for entry in jt.entries:
    if entry.jobNumber == jobNumber:
      return entry
  raise newException(KeyError, "Job " & $jobNumber & " not found")

proc getJobByPid*(jt: JobTable, pid: Pid): JobEntry =
  ## Get job entry by PID
  for entry in jt.entries:
    if entry.pid == pid:
      return entry
  raise newException(KeyError, "Job with PID " & $pid & " not found")

proc removeJob*(jt: JobTable, jobNumber: int) =
  ## Remove a job from the table
  var i = 0
  while i < jt.entries.len:
    if jt.entries[i].jobNumber == jobNumber:
      jt.entries.delete(i)
      return
    inc i

proc getJobCount*(jt: JobTable): int =
  return jt.entries.len

proc listJobs*(jt: JobTable): seq[JobEntry] =
  return jt.entries

proc getJobPid*(jt: JobTable, jobNumber: int): Pid =
  ## Get PID of a running job
  for entry in jt.entries:
    if entry.jobNumber == jobNumber:
      return entry.pid
  return 0

proc cleanup*(jt: JobTable) =
  ## Clean up all job entries
  for entry in jt.entries:
    if entry.status == jsRunning:
      # Signal the child to terminate
      discard kill(entry.pid, SIGTERM)
  jt.entries.setLen(0)
