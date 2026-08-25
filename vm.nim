# vm.nim — Stack-based virtual machine for NimM bytecode
# Executes compiled bytecode instructions

import strutils
import math
import bytecode
import globals
import value

type
  VM* = ref object
    ## Virtual machine state
    stack*: seq[string]          # Value stack
    output*: string              # Output buffer
    globalsRef*: ptr Globals     # Global variable storage
    pc*: int                     # Program counter
    halted*: bool                # Execution halted

proc newVM*(g: ptr Globals): VM =
  new(result)
  result.stack = @[]
  result.output = ""
  result.globalsRef = g
  result.pc = 0
  result.halted = false

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

proc extractBetween(s: string, startTag: string, endTag: string): string =
  let startIdx = s.find(startTag)
  if startIdx < 0: return ""
  let closeIdx = s.find(">", startIdx)
  if closeIdx < 0: return ""
  let contentStart = closeIdx + 1
  let endIdx = s.find(endTag, contentStart)
  if endIdx < 0: return ""
  return s[contentStart ..< endIdx].strip()

proc extractAll(s: string, startTag: string, endTag: string): seq[string] =
  result = @[]
  var pos = 0
  while pos < s.len:
    let startIdx = s.find(startTag, pos)
    if startIdx < 0: break
    let closeIdx = s.find(">", startIdx)
    if closeIdx < 0: break
    let contentStart = closeIdx + 1
    let endIdx = s.find(endTag, contentStart)
    if endIdx < 0: break
    result.add(s[contentStart ..< endIdx].strip())
    pos = endIdx + endTag.len

proc loadXmlData*(vm: VM, filePath: string, globalName: string, format: string): int =
  var f = open(filePath, fmRead)
  if f == nil:
    raise newException(IOError, "Cannot open: " & filePath)
  defer: f.close()
  
  var count = 0
  var buffer = ""
  var batchCount = 0
  const BATCH_SIZE = 1000
  
  vm.globalsRef[].beginWriteBatch()
  
  case format.toLowerAscii
  of "mesh-descriptor", "mesh":
    for line in f.lines:
      buffer.add(line)
      buffer.add("\n")
      
      if "</DescriptorRecord>" in buffer:
        let ui = extractBetween(buffer, "<DescriptorUI>", "</DescriptorUI>")
        let name = extractBetween(buffer, "<String>", "</String>")
        let scope = extractBetween(buffer, "<ScopeNote>", "</ScopeNote>")
        
        if ui.len > 0 and name.len > 0:
          vm.globalsRef[].set(globalName, @[ui, "name"], name)
          if scope.len > 0:
            vm.globalsRef[].set(globalName, @[ui, "scopeNote"], scope)
          
          let trees = extractAll(buffer, "<TreeNumber>", "</TreeNumber>")
          for tree in trees:
            vm.globalsRef[].set(globalName, @[ui, "treeNumber", tree], "1")
          
          let quals = extractAll(buffer, "<QualifierUI>", "</QualifierUI>")
          for qual in quals:
            vm.globalsRef[].set(globalName, @[ui, "qualifier", qual], "1")
          
          count += 1
          inc batchCount
          if batchCount >= BATCH_SIZE:
            vm.globalsRef[].endWriteBatch()
            vm.globalsRef[].beginWriteBatch()
            batchCount = 0
        
        buffer = ""
  
  of "mesh-qualifier", "qualifier":
    for line in f.lines:
      buffer.add(line)
      buffer.add("\n")
      
      if "</QualifierRecord>" in buffer:
        let ui = extractBetween(buffer, "<QualifierUI>", "</QualifierUI>")
        let name = extractBetween(buffer, "<String>", "</String>")
        let abbrev = extractBetween(buffer, "<Abbreviation>", "</Abbreviation>")
        
        if ui.len > 0 and name.len > 0:
          vm.globalsRef[].set(globalName, @[ui, "name"], name)
          if abbrev.len > 0:
            vm.globalsRef[].set(globalName, @[ui, "abbreviation"], abbrev)
          count += 1
        
        buffer = ""
  
  else:
    raise newException(ValueError, "Unknown XML format: " & format)
  
  if vm.globalsRef[].writeTxnActive:
    vm.globalsRef[].endWriteBatch()
  
  return count

proc execute*(vm: VM, bc: Bytecode): string =
  ## Execute bytecode and return output
  vm.output = ""
  vm.pc = 0
  vm.halted = false

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
      var result = ""
      for i in fromIdx..toIdx:
        if i > 0 and i <= pieces.len:
          if result.len > 0: result.add(delimiter)
          result.add(pieces[i - 1])
      vm.push(result)

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

    of opCall:
      # Function call — args already on stack
      let name = instr.arg1
      let argc = instr.argInt
      var args: seq[string] = @[]
      for i in 0..<argc:
        args.add(vm.pop())
      # Reverse args since stack is LIFO
      var reversed: seq[string] = @[]
      for i in countdown(args.len - 1, 0):
        reversed.add(args[i])
      args = reversed
      # Fall back to evaluator for function calls
      # For now, push empty result
      vm.push("")

    of opReturn:
      vm.halted = true

    of opQuit:
      vm.halted = true

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
    of opForInit:
      let varName = instr.arg1
      let limit = parseInt(instr.arg2)
      let step = instr.argInt
      if vm.globalsRef != nil:
        vm.globalsRef[].setLocalDirect(varName, "1")
      vm.push($limit)
      vm.push($step)

    of opForNext:
      let varName = instr.arg1
      let offset = instr.argInt
      if vm.globalsRef != nil:
        let current = parseInt(vm.globalsRef[].get(varName, @[]))
        let step = parseInt(vm.pop())
        let limit = parseInt(vm.pop())
        let next = current + step
        vm.globalsRef[].setLocalDirect(varName, $next)
        if next <= limit:
          vm.push($limit)
          vm.push($step)
          vm.pc = offset
        else:
          vm.push($limit)
          vm.push($step)

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

    of opXecute:
      # Dynamic code — fall back to AST interpreter
      # For now, just push empty result
      vm.push("")

    of opZloadxml:
      # ZLOADXML file, global, format
      let format = vm.pop()
      let globalName = vm.pop()
      let filePath = vm.pop()
      try:
        let count = vm.loadXmlData(filePath, globalName, format)
        vm.globalsRef[].set("^ZLOADXML", @[], $count)
        vm.push($count)
      except:
        vm.push("0")

    of opNop:
      discard

  return vm.output
