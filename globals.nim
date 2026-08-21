# globals.nim — Global/Local variable storage for nimm
# Provides M/MUMPS variable storage with NEW/QUIT scoping

import tables
import strutils
import algorithm
import storage/lmdb_store
import storage/key_encoding

type
  SpecialVarGetter* = proc(): string
  SpecialVarSetter* = proc(val: string)

  Globals* = object
    ## Variable storage with local/global separation and scoping
    scopes*: seq[Table[string, string]]  # Stack of local scopes (flat key -> value)
    globals*: LmdbStore                   # LMDB-backed global storage
    memGlobals: Table[string, string]     # In-memory global store (when no -db)
    specialGetters*: Table[string, SpecialVarGetter]
    specialSetters*: Table[string, SpecialVarSetter]
    dbPath*: string
    nakedGlobal*: string                  # Last global name for naked references
    nakedSubs*: seq[string]               # Last subscripts for naked references
    scopeShared*: seq[bool]               # True if scope shares parent (COW pending)

proc makeKey(name: string, subs: seq[string]): string =
  ## Create flat key for storage (pre-computed exact size)
  var size = name.len
  for sub in subs:
    size += 1 + sub.len
  result = newString(size)
  var pos = name.len
  result[0..<pos] = name
  for sub in subs:
    result[pos] = '\0'
    inc pos
    result[pos..<pos+sub.len] = sub
    pos += sub.len

proc newGlobals*(dbPath: string = ""): Globals =
  result.scopes = @[initTable[string, string]()]
  result.scopeShared = @[false]
  result.dbPath = dbPath
  result.specialGetters = initTable[string, SpecialVarGetter]()
  result.specialSetters = initTable[string, SpecialVarSetter]()
  result.nakedGlobal = ""
  result.nakedSubs = @[]
  
  if dbPath.len > 0:
    result.globals.init(dbPath)

proc close*(g: var Globals) =
  if g.dbPath.len > 0:
    g.globals.close()

# --- Local variable operations ---

proc ensureWritable(g: var Globals)

proc getLocal*(g: Globals, name: string, subs: seq[string] = @[]): string =
  ## Get local variable value (searches all scopes from inner to outer)
  let key = makeKey(name, subs)
  for i in countdown(g.scopes.len - 1, 0):
    if key in g.scopes[i]:
      return g.scopes[i][key]
  return ""

proc getLocalDirect*(g: Globals, name: string): string =
  ## Get local variable value directly (no subscripts, no seq allocation)
  for i in countdown(g.scopes.len - 1, 0):
    if name in g.scopes[i]:
      return g.scopes[i][name]
  return ""

proc ensureWritable(g: var Globals) =
  ## Copy-on-write: if current scope is shared, duplicate it
  if g.scopeShared.len > 0 and g.scopeShared[^1]:
    g.scopes[^1] = g.scopes[^1]
    g.scopeShared[^1] = false

proc setLocal*(g: var Globals, name: string, subs: seq[string], value: string) =
  ## Set local variable value
  g.ensureWritable()
  let key = makeKey(name, subs)
  g.scopes[^1][key] = value

proc setLocalDirect*(g: var Globals, name: string, value: string) =
  ## Set local variable value directly (no subscripts, no seq allocation)
  g.ensureWritable()
  g.scopes[^1][name] = value

proc killLocal*(g: var Globals, name: string, subs: seq[string] = @[]) =
  ## Kill local variable
  g.ensureWritable()
  let scope = addr g.scopes[^1]
  if subs.len == 0:
    let prefix = name & "\x00"
    var toDelete: seq[string] = @[]
    for k in scope[].keys:
      if k == name or k.startsWith(prefix):
        toDelete.add(k)
    for k in toDelete:
      scope[].del(k)
  else:
    # Kill node and any descendants below it (§7.2.9)
    let key = makeKey(name, subs)
    let prefix = key & "\x00"
    var toDelete: seq[string] = @[]
    for k in scope[].keys:
      if k == key or k.startsWith(prefix):
        toDelete.add(k)
    for k in toDelete:
      scope[].del(k)

proc killAllLocal*(g: var Globals) =
  ## Kill all local variables in current scope
  g.ensureWritable()
  g.scopes[^1].clear()

proc killAllExceptLocal*(g: var Globals, keep: seq[string]) =
  ## Exclusive KILL: delete every local whose base variable is not in keep
  g.ensureWritable()
  var toDelete: seq[string] = @[]
  for key in g.scopes[^1].keys:
    let base = key.split('\x00')[0]
    if base notin keep:
      toDelete.add(key)
  for key in toDelete:
    g.scopes[^1].del(key)

proc killAllGlobalsExcept*(g: var Globals, keep: seq[string]) =
  ## Exclusive KILL: delete every global whose base name is not in keep
  if g.dbPath.len == 0: return
  let allKeys = g.globals.listKeys("")
  for key in allKeys:
    let base = key.split('\x00')[0]
    if base.startsWith("^") and base notin keep:
      # Reconstruct subscript list from the stored key
      var subs: seq[string] = @[]
      if '\0' in key:
        subs = key.split('\x00')[1..^1]
      g.globals.delete(base, subs)

proc dataLocal*(g: Globals, name: string, subs: seq[string] = @[]): int =
  ## $DATA for local variables
  let key = makeKey(name, subs)
  let scope = g.scopes[^1]
  let hasValue = key in scope and scope[key].len > 0
  
  # Check for descendants
  let prefix = key & "\x00"
  var hasChildren = false
  for k in scope.keys:
    if k.startsWith(prefix):
      hasChildren = true
      break
  
  if hasValue and hasChildren: return 11
  if hasValue: return 1
  if hasChildren: return 10
  return 0

proc orderLocal*(g: Globals, name: string, subs: seq[string] = @[], forward: bool = true): string =
  ## $ORDER for local variables with M-collation
  let scope = g.scopes[^1]
  let prefix = name & "\x00"
  
  var keys: seq[string] = @[]
  for k in scope.keys:
    if k.startsWith(prefix):
      let rest = k[prefix.len..^1]
      if '\0' notin rest:
        keys.add(rest)
  
  # M-collation sort (numeric before string)
  keys.sort(mCollationCmp)
  
  if keys.len == 0: return ""
  
  if subs.len == 0:
    if forward: return keys[0]
    else: return keys[^1]
  
  # Find the next key after the given subscript
  let lastSub = subs[^1]
  if lastSub.len == 0 and not forward:
    # §9.9: the null subscript precedes everything, so backward from ""
    # there is nothing left.
    return ""
  if forward:
    for k in keys:
      if mCollationCmp(k, lastSub) > 0:
        return k
    return ""
  # Backward: return the last key that is less than lastSub
  for i in countdown(keys.len - 1, 0):
    if mCollationCmp(keys[i], lastSub) < 0:
      return keys[i]
  
  return ""

# --- Global variable operations ---

proc getGlobal*(g: Globals, name: string, subs: seq[string] = @[]): string =
  ## Get global variable value from LMDB (or in-memory store when no -db)
  if g.dbPath.len == 0: return g.memGlobals.getOrDefault(makeKey(name, subs), "")
  return g.globals.get(name, subs)

proc setGlobal*(g: var Globals, name: string, subs: seq[string], value: string) =
  ## Set global variable value in LMDB (or in-memory store when no -db)
  # Track last global reference for naked indirection
  g.nakedGlobal = name
  g.nakedSubs = subs
  if g.dbPath.len == 0:
    g.memGlobals[makeKey(name, subs)] = value
    return
  g.globals.put(name, subs, value)

proc setNaked*(g: var Globals, name: string, subs: seq[string]) =
  ## Update the naked indicator without touching stored data
  g.nakedGlobal = name
  g.nakedSubs = subs

proc killGlobal*(g: var Globals, name: string, subs: seq[string] = @[]) =
  ## Kill global variable
  if g.dbPath.len == 0:
    let key = makeKey(name, subs)
    if subs.len == 0:
      # Kill node and all descendants (keys starting with name\x00)
      var toDelete: seq[string] = @[]
      for k in g.memGlobals.keys:
        if k == key or k.startsWith(key & "\x00"):
          toDelete.add(k)
      for k in toDelete:
        g.memGlobals.del(k)
    else:
      # Kill node and any descendants below it (§7.2.9)
      let prefix = key & "\x00"
      var toDelete: seq[string] = @[]
      for k in g.memGlobals.keys:
        if k == key or k.startsWith(prefix):
          toDelete.add(k)
      for k in toDelete:
        g.memGlobals.del(k)
    return
  g.globals.delete(name, subs)

# --- Unified get/set (auto-detect local vs global) ---

proc get*(g: Globals, name: string, subs: seq[string] = @[]): string =
  ## Get variable value (auto-detect local vs global)
  if name.len > 0 and name[0] == '^':
    return g.getGlobal(name, subs)
  else:
    return g.getLocal(name, subs)

proc set*(g: var Globals, name: string, subs: seq[string], value: string) =
  ## Set variable value (auto-detect local vs global)
  if name.len > 0 and name[0] == '^':
    g.setGlobal(name, subs, value)
  else:
    g.setLocal(name, subs, value)

proc kill*(g: var Globals, name: string, subs: seq[string] = @[]) =
  ## Kill variable (auto-detect local vs global)
  if name.len > 0 and name[0] == '^':
    g.killGlobal(name, subs)
  else:
    g.killLocal(name, subs)

proc orderGlobalMem(g: Globals, name: string, subs: seq[string], forward: bool): string =
  ## $ORDER over the in-memory global store
  let prefix = name & "\x00"
  var keys: seq[string] = @[]
  for k in g.memGlobals.keys:
    if k.startsWith(prefix):
      let rest = k[prefix.len..^1]
      if '\0' notin rest:
        keys.add(rest)
  keys.sort(mCollationCmp)
  if keys.len == 0: return ""
  if subs.len == 0:
    return if forward: keys[0] else: keys[^1]
  let lastSub = subs[^1]
  if lastSub.len == 0 and not forward:
    # §9.9: backward from the null subscript there is nothing
    return ""
  if forward:
    for k in keys:
      if mCollationCmp(k, lastSub) > 0: return k
    return ""
  for i in countdown(keys.len - 1, 0):
    if mCollationCmp(keys[i], lastSub) < 0: return keys[i]
  return ""

proc order*(g: Globals, name: string, subs: seq[string] = @[], forward: bool = true): string =
  ## $ORDER (auto-detect local vs global)
  if name.len > 0 and name[0] == '^':
    # For globals, use LMDB cursor (or in-memory store when no -db)
    if g.dbPath.len == 0: return orderGlobalMem(g, name, subs, forward)
    return g.globals.order(name, subs, forward)
  else:
    return g.orderLocal(name, subs, forward)

proc tupCollationCmp(a, b: seq[string]): int =
  ## Collation-aware comparison of subscript tuples; shorter prefix sorts first,
  ## which matches depth-first pre-order tree traversal.
  for i in 0 ..< min(a.len, b.len):
    let c = mCollationCmp(a[i], b[i])
    if c != 0: return c
  return system.cmp(a.len, b.len)

proc queryGlobalMem(g: Globals, name: string, subs: seq[string], forward: bool): seq[string] =
  ## $QUERY over the in-memory global store: next node in DFS pre-order
  let basePrefix = name & "\x00"
  var tuples: seq[seq[string]] = @[]
  for k in g.memGlobals.keys:
    if k.startsWith(basePrefix):
      tuples.add(k[basePrefix.len..^1].split('\x00'))
  tuples.sort(tupCollationCmp)
  if forward:
    for t in tuples:
      if tupCollationCmp(t, subs) > 0: return t
    return @[]
  else:
    for i in countdown(tuples.len - 1, 0):
      if tupCollationCmp(tuples[i], subs) < 0: return tuples[i]
    return @[]

proc query*(g: Globals, name: string, subs: seq[string] = @[], forward: bool = true): seq[string] =
  ## $QUERY (auto-detect local vs global)
  ## Returns all subscripts of the next node (any depth)
  if name.len > 0 and name[0] == '^':
    # For globals: LMDB cursor when persistent; mem store otherwise
    if g.dbPath.len == 0: return queryGlobalMem(g, name, subs, forward)
    return g.globals.query(name, subs, forward)
  else:
    # For locals: same DFS pre-order over the current scope's keys
    let prefix = name & "\x00"
    var tuples: seq[seq[string]] = @[]
    for k in g.scopes[^1].keys:
      if k.startsWith(prefix):
        tuples.add(k[prefix.len..^1].split('\x00'))
    tuples.sort(tupCollationCmp)
    if forward:
      for t in tuples:
        if tupCollationCmp(t, subs) > 0: return t
      return @[]
    else:
      for i in countdown(tuples.len - 1, 0):
        if tupCollationCmp(tuples[i], subs) < 0: return tuples[i]
      return @[]

proc dataGlobalMem(g: Globals, name: string, subs: seq[string]): int =
  ## $DATA tri-state over the in-memory global store
  let key = makeKey(name, subs)
  let hasValue = key in g.memGlobals
  let prefix = key & "\x00"
  var hasChildren = false
  for k in g.memGlobals.keys:
    if k.startsWith(prefix):
      hasChildren = true
      break
  if hasValue and hasChildren: return 11
  if hasValue: return 1
  if hasChildren: return 10
  return 0

proc data*(g: Globals, name: string, subs: seq[string] = @[]): int =
  ## $DATA (auto-detect local vs global, tri-state per ANSI/ISO 8.5)
  if name.len > 0 and name[0] == '^':
    if g.dbPath.len == 0:
      return dataGlobalMem(g, name, subs)
    let val = g.globals.get(name, subs)
    if val.len > 0:
      # Node has a value; check for descendants via listSubs
      let kids = g.globals.listSubs(name, subs)
      return if kids.len > 0: 11 else: 1
    let kids = g.globals.listSubs(name, subs)
    return if kids.len > 0: 10 else: 0
  else:
    return g.dataLocal(name, subs)

proc listSubs*(g: Globals, name: string, subs: seq[string] = @[]): seq[seq[string]] =
  ## List all subscripts under a given variable
  ## Returns a sequence of subscript sequences
  if name.len > 0 and name[0] == '^':
    # For globals: LMDB cursor when persistent; scan memGlobals otherwise
    if g.dbPath.len == 0:
      let prefix = makeKey(name, subs) & "\x00"
      var keys: seq[string] = @[]
      for k in g.memGlobals.keys:
        if k.startsWith(prefix):
          keys.add(k)
      keys.sort(system.cmp)
      result = @[]
      for k in keys:
        let rest = k[prefix.len..^1]
        var subSeq: seq[string] = @[]
        var current = ""
        for ch in rest:
          if ch == '\x00':
            subSeq.add(current)
            current = ""
          else:
            current.add(ch)
        subSeq.add(current)
        result.add(subSeq)
      return result
    return g.globals.listSubs(name, subs)
  else:
    # For locals, scan the scope table
    let scope = g.scopes[^1]
    let base = makeKey(name, subs)
    let prefix = base & "\x00"
    var result: seq[seq[string]] = @[]
    for k in scope.keys:
      if k == base or k.startsWith(prefix):
        # Extract subscripts after the prefix
        let rest = k[prefix.len..^1]
        var subSeq: seq[string] = @[]
        var current = ""
        for ch in rest:
          if ch == '\0':
            if current.len > 0:
              subSeq.add(current)
              current = ""
          else:
            current.add(ch)
        if current.len > 0:
          subSeq.add(current)
        if subSeq.len > 0:
          result.add(subSeq)
    return result

# --- NEW/QUIT scoping ---

proc pushScope*(g: var Globals) =
  ## Push new local scope (NEW) — shares parent scope (COW)
  g.scopes.add(g.scopes[^1])  # Share reference (cheap)
  g.scopeShared.add(true)     # Mark as shared

proc popScope*(g: var Globals) =
  ## Pop local scope (QUIT) — discards current scope
  if g.scopes.len > 1:
    g.scopes.setLen(g.scopes.len - 1)
    g.scopeShared.setLen(g.scopeShared.len - 1)

proc scopeDepth*(g: Globals): int =
  return g.scopes.len

# --- Special variables ---

proc registerSpecialVar*(g: var Globals, name: string, getter: SpecialVarGetter, setter: SpecialVarSetter = nil) =
  g.specialGetters[name] = getter
  if setter != nil:
    g.specialSetters[name] = setter

proc getSpecialVar*(g: Globals, name: string): string =
  if name in g.specialGetters:
    return g.specialGetters[name]()
  return ""

proc setSpecialVar*(g: var Globals, name: string, value: string) =
  if name in g.specialSetters:
    g.specialSetters[name](value)
