# vm.nim — Stack-based virtual machine for NimM bytecode
# Executes compiled bytecode instructions

import strutils
import math
import algorithm
import bytecode
import globals
import value
import xmlload

type
  VM* = ref object
    ## Virtual machine state
    stack*: seq[string]          # Value stack
    output*: string              # Output buffer
    globalsRef*: ptr Globals     # Global variable storage
    pc*: int                     # Program counter
    halted*: bool                # Execution halted
    ctrlKind*: string            # Control transfer: "" | "GOTO" | "CALL" | "QUIT"
    ctrlLabel*: string           # Target label (for GOTO/CALL)
    ctrlRoutine*: string         # Target routine (for GOTO/CALL; "" = current)

proc newVM*(g: ptr Globals): VM =
  new(result)
  result.stack = @[]
  result.output = ""
  result.globalsRef = g
  result.pc = 0
  result.halted = false
  result.ctrlKind = ""

proc push*(vm: VM, value: string) =
  vm.stack.add(value)

proc pop*(vm: VM): string =
  if vm.stack.len == 0: return ""
  result = vm.stack[^1]
  vm.stack.setLen(vm.stack.len - 1)

proc peek*(vm: VM): string =
  if vm.stack.len == 0: return ""
  return vm.stack[^1]

proc writeOut*(vm: VM, s: string) =
  vm.output.add(s)


proc execute*(vm: VM, bc: Bytecode): string =
  ## Execute bytecode and return output
  vm.output = ""
  vm.pc = 0
  vm.halted = false
  vm.ctrlKind = ""

  while vm.pc < bc.instructions.len and not vm.halted:
    let instr = bc.instructions[vm.pc]
    vm.pc += 1

    case instr.opcode
    of opPushConst:
      let idx = instr.argInt
      if idx >= 0 and idx < bc.constants.len:
        vm.push(bc.constants[idx])
      else:
        vm.push("")

    of opPushVar:
      let name = instr.arg1
      if vm.globalsRef != nil:
        vm.push(vm.globalsRef[].get(name, @[]))
      else:
        vm.push("")

    of opPushGlobal:
      let name = instr.arg1
      var subs: seq[string] = @[]
      if instr.arg2.len > 0:
        subs.add(instr.arg2)
      if vm.globalsRef != nil:
        vm.push(vm.globalsRef[].get(name, subs))
      else:
        vm.push("")

    of opPushSvar:
      let name = instr.arg1
      if vm.globalsRef != nil:
        vm.push(vm.globalsRef[].getSpecialVar("$" & name))
      else:
        vm.push("")

    of opSetVar:
      let name = instr.arg1
      let val = vm.pop()
      if vm.globalsRef != nil:
        vm.globalsRef[].setLocalDirect(name, val)

    of opSetGlobal:
      let name = instr.arg1
      var subs: seq[string] = @[]
      if instr.arg2.len > 0:
        subs.add(instr.arg2)
      let val = vm.pop()
      if vm.globalsRef != nil:
        vm.globalsRef[].set(name, subs, val)

    of opSetSvar:
      let name = instr.arg1
      let val = vm.pop()
      if vm.globalsRef != nil:
        vm.globalsRef[].setSpecialVar("$" & name, val)

    of opPushVarSub, opPushGlobalSub:
      # Pop N subscripts (reverse order), push the node's value (#394)
      let name = instr.arg1
      let n = instr.argInt
      var subs: seq[string] = @[]
      for i in 0 ..< n:
        subs.add(vm.pop())
      subs.reverse()
      if vm.globalsRef != nil:
        if instr.opcode == opPushGlobalSub:
          vm.push(vm.globalsRef[].get(name, subs))
        else:
          vm.push(vm.globalsRef[].getLocal(name, subs))
      else:
        vm.push("")

    of opSetVarSub, opSetGlobalSub:
      # Pop N subscripts + value, set the node (#394)
      let name = instr.arg1
      let n = instr.argInt
      var subs: seq[string] = @[]
      for i in 0 ..< n:
        subs.add(vm.pop())
      subs.reverse()
      let val = vm.pop()
      if vm.globalsRef != nil:
        if instr.opcode == opSetGlobalSub:
          vm.globalsRef[].set(name, subs, val)
        else:
          vm.globalsRef[].setLocal(name, subs, val)

    of opPop:
      discard vm.pop()

    of opDup:
      let val = vm.peek()
      vm.push(val)

    # Arithmetic
    of opAdd:
      let right = vm.pop()
      let left = vm.pop()
      vm.push(formatNumber(numPrefix(left) + numPrefix(right)))

    of opSub:
      let right = vm.pop()
      let left = vm.pop()
      vm.push(formatNumber(numPrefix(left) - numPrefix(right)))

    of opMul:
      let right = vm.pop()
      let left = vm.pop()
      vm.push(formatNumber(numPrefix(left) * numPrefix(right)))

    of opDiv:
      let right = vm.pop()
      let left = vm.pop()
      let r = numPrefix(right)
      if r == 0.0: vm.push("0")
      else: vm.push(formatNumber(numPrefix(left) / r))

    of opIntDiv:
      let right = vm.pop()
      let left = vm.pop()
      let r = numPrefix(right)
      if r == 0.0: vm.push("0")
      else: vm.push(formatNumber(float(int(numPrefix(left) / r))))

    of opMod:
      let right = vm.pop()
      let left = vm.pop()
      let r = numPrefix(right)
      if r == 0.0: vm.push("0")
      else:
        let l = numPrefix(left)
        vm.push(formatNumber(l - r * floor(l / r)))

    of opPow:
      let right = vm.pop()
      let left = vm.pop()
      vm.push(formatNumber(pow(numPrefix(left), numPrefix(right))))

    # Comparison
    of opCmpEql:
      let right = vm.pop()
      let left = vm.pop()
      if numPrefix(left) == numPrefix(right): vm.push("1")
      else: vm.push("0")

    of opCmpNeq:
      let right = vm.pop()
      let left = vm.pop()
      if numPrefix(left) != numPrefix(right): vm.push("1")
      else: vm.push("0")

    of opCmpLt:
      let right = vm.pop()
      let left = vm.pop()
      if numPrefix(left) < numPrefix(right): vm.push("1")
      else: vm.push("0")

    of opCmpGt:
      let right = vm.pop()
      let left = vm.pop()
      if numPrefix(left) > numPrefix(right): vm.push("1")
      else: vm.push("0")

    of opCmpLe:
      let right = vm.pop()
      let left = vm.pop()
      if numPrefix(left) <= numPrefix(right): vm.push("1")
      else: vm.push("0")

    of opCmpGe:
      let right = vm.pop()
      let left = vm.pop()
      if numPrefix(left) >= numPrefix(right): vm.push("1")
      else: vm.push("0")

    of opCmpContains:
      let right = vm.pop()
      let left = vm.pop()
      if right.find(left) >= 0: vm.push("1")
      else: vm.push("0")

    of opCmpFollows:
      let right = vm.pop()
      let left = vm.pop()
      if left > right: vm.push("1")
      else: vm.push("0")

    # String operations
    of opConcat:
      let right = vm.pop()
      let left = vm.pop()
      vm.push(left & right)

    of opPiece:
      let toIdx = parseInt(vm.pop())
      let fromIdx = parseInt(vm.pop())
      let delimiter = vm.pop()
      let s = vm.pop()
      # Simple piece extraction
      var pieces: seq[string] = @[]
      var current = ""
      for ch in s:
        if ch == delimiter[0]:
          pieces.add(current)
          current = ""
        else:
          current.add(ch)
      pieces.add(current)
      var res = ""
      for i in fromIdx..toIdx:
        if i > 0 and i <= pieces.len:
          if res.len > 0: res.add(delimiter)
          res.add(pieces[i - 1])
      vm.push(res)

    of opExtract:
      let last = parseInt(vm.pop())
      let first = parseInt(vm.pop())
      let s = vm.pop()
      if first < 1 or first > s.len: vm.push("")
      elif last > s.len: vm.push(s[first-1..^1])
      elif last < first: vm.push("")
      else: vm.push(s[first-1..<last])

    of opLength:
      let s = vm.pop()
      vm.push($s.len)

    # Control flow
    of opJump:
      vm.pc = instr.argInt

    of opJumpIfFalse:
      let cond = vm.pop()
      if not truthy(cond):
        vm.pc = instr.argInt

    of opJumpIfTrue:
      let cond = vm.pop()
      if truthy(cond):
        vm.pc = instr.argInt

    of opReturn:
      vm.halted = true

    of opQuit:
      vm.halted = true
      vm.ctrlKind = "QUIT"

    # I/O
    of opWrite:
      let argc = instr.argInt
      for i in 0..<argc:
        let val = vm.pop()
        vm.writeOut(val)

    of opWriteNl:
      vm.writeOut("\n")

    of opWriteFf:
      vm.writeOut("\f")

    # M-specific
    of opNewScope:
      if vm.globalsRef != nil:
        vm.globalsRef[].pushScope()

    of opPopScope:
      if vm.globalsRef != nil:
        vm.globalsRef[].popScope()

    of opLockAcquire:
      let name = instr.arg1
      if vm.globalsRef != nil:
        vm.globalsRef[].acquireLock(name)

    of opLockRelease:
      let name = instr.arg1
      if vm.globalsRef != nil:
        vm.globalsRef[].releaseLock(name)

    of opLockReleaseAll:
      if vm.globalsRef != nil:
        vm.globalsRef[].releaseAllLocks()

    of opTstart:
      if vm.globalsRef != nil:
        vm.globalsRef[].tstart()

    of opTcommit:
      if vm.globalsRef != nil:
        vm.globalsRef[].tcommit()

    of opTrollback:
      if vm.globalsRef != nil:
        vm.globalsRef[].trollback()

    of opZloadxml:
      # ZLOADXML file, global, format
      let format = vm.pop()
      let globalName = vm.pop()
      let filePath = vm.pop()
      try:
        let count = xmlload.loadXmlData(vm.globalsRef[], filePath, globalName, format)
        vm.globalsRef[].set("^ZLOADXML", @[], $count)
        vm.push($count)
      except:
        vm.push("0")

    of opKill:
      # KILL var (arg1 = name, "" = kill all locals)
      let name = instr.arg1
      if vm.globalsRef != nil:
        if name.len == 0:
          vm.globalsRef[].killAllLocal()
        else:
          vm.globalsRef[].kill(name, @[])

    of opBreak:
      # BREAK — halt in the bytecode VM (no interactive debugger)
      vm.halted = true

    of opGoto:
      # GOTO label[^routine] — signal the engine to jump (#378)
      vm.ctrlKind = "GOTO"
      vm.ctrlLabel = instr.arg1
      vm.ctrlRoutine = instr.arg2
      vm.halted = true

    of opCallLabel:
      # DO label[^routine] — signal the engine to call a sub-routine (#378)
      vm.ctrlKind = "CALL"
      vm.ctrlLabel = instr.arg1
      vm.ctrlRoutine = instr.arg2
      vm.halted = true

    of opMerge:
      # MERGE dst=src — copy the source variable tree to the destination
      let dst = instr.arg1
      let src = instr.arg2
      if vm.globalsRef != nil:
        let rootVal = vm.globalsRef[].get(src, @[])
        if rootVal.len > 0:
          vm.globalsRef[].set(dst, @[], rootVal)
        for subs in vm.globalsRef[].listSubs(src):
          vm.globalsRef[].set(dst, subs, vm.globalsRef[].get(src, subs))

    of opNop:
      discard

  return vm.output
