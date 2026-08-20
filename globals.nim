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
    specialGetters*: Table[string, SpecialVarGetter]
    specialSetters*: Table[string, SpecialVarSetter]
    dbPath*: string
    nakedGlobal*: string                  # Last global name for naked references
    nakedSubs*: seq[string]               # Last subscripts for naked references

proc makeKey(name: string, subs: seq[string]): string =
  ## Create flat key for storage
  result = name
  for sub in subs:
    result.add('\0')
    result.add(sub)

proc newGlobals*(dbPath: string = ""): Globals =
  result.scopes = @[initTable[string, string]()]
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

proc getLocal*(g: Globals, name: string, subs: seq[string] = @[]): string =
  ## Get local variable value (searches all scopes from inner to outer)
  let key = makeKey(name, subs)
  for i in countdown(g.scopes.len - 1, 0):
    if key in g.scopes[i]:
      return g.scopes[i][key]
  return ""

proc setLocal*(g: var Globals, name: string, subs: seq[string], value: string) =
  ## Set local variable value
  let key = makeKey(name, subs)
  g.scopes[^1][key] = value

proc killLocal*(g: var Globals, name: string, subs: seq[string] = @[]) =
  ## Kill local variable
  let scope = addr g.scopes[^1]
  if subs.len == 0:
    # Kill all with this name prefix
    let prefix = name & "\x00"
    var toDelete: seq[string] = @[]
    for k in scope[].keys:
      if k == name or k.startsWith(prefix):
        toDelete.add(k)
    for k in toDelete:
      scope[].del(k)
  else:
    let key = makeKey(name, subs)
    scope[].del(key)

proc killAllLocal*(g: var Globals) =
  ## Kill all local variables in current scope
  g.scopes[^1].clear()

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
  for i, k in keys:
    if forward and k > lastSub:
      return k
  # For backward: return the last key that is less than lastSub
  # (keys are sorted ascending, so iterate to find the closest one)
  for i in countdown(keys.len - 1, 0):
    if keys[i] < lastSub:
      return keys[i]
  
  return ""

# --- Global variable operations ---

proc getGlobal*(g: Globals, name: string, subs: seq[string] = @[]): string =
  ## Get global variable value from LMDB
  if g.dbPath.len == 0: return ""
  return g.globals.get(name, subs)

proc setGlobal*(g: var Globals, name: string, subs: seq[string], value: string) =
  ## Set global variable value in LMDB
  if g.dbPath.len == 0: return
  g.globals.put(name, subs, value)
  # Track last global reference for naked indirection
  g.nakedGlobal = name
  g.nakedSubs = subs

proc killGlobal*(g: var Globals, name: string, subs: seq[string] = @[]) =
  ## Kill global variable
  if g.dbPath.len == 0: return
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

proc order*(g: Globals, name: string, subs: seq[string] = @[], forward: bool = true): string =
  ## $ORDER (auto-detect local vs global)
  if name.len > 0 and name[0] == '^':
    # For globals, use LMDB cursor
    if g.dbPath.len == 0: return ""
    return g.globals.order(name, subs, forward)
  else:
    return g.orderLocal(name, subs, forward)

proc query*(g: Globals, name: string, subs: seq[string] = @[], forward: bool = true): seq[string] =
  ## $QUERY (auto-detect local vs global)
  ## Returns all subscripts of the next node (any depth)
  if name.len > 0 and name[0] == '^':
    # For globals, use LMDB cursor
    if g.dbPath.len == 0: return @[]
    return g.globals.query(name, subs, forward)
  else:
    # For locals, use order (same as $ORDER for locals)
    let nextSub = g.orderLocal(name, subs, forward)
    if nextSub.len == 0: return @[]
    var result: seq[string] = @[]
    for sub in subs:
      result.add(sub)
    result.add(nextSub)
    return result

proc data*(g: Globals, name: string, subs: seq[string] = @[]): int =
  ## $DATA (auto-detect local vs global)
  if name.len > 0 and name[0] == '^':
    let val = g.getGlobal(name, subs)
    if val.len > 0: return 1
    return 0
  else:
    return g.dataLocal(name, subs)

proc listSubs*(g: Globals, name: string, subs: seq[string] = @[]): seq[seq[string]] =
  ## List all subscripts under a given variable
  ## Returns a sequence of subscript sequences
  if name.len > 0 and name[0] == '^':
    # For globals, use LMDB cursor
    if g.dbPath.len == 0: return @[]
    return g.globals.listSubs(name, subs)
  else:
    # For locals, scan the scope table
    let scope = g.scopes[^1]
    let prefix = makeKey(name, subs)
    var result: seq[seq[string]] = @[]
    for k in scope.keys:
      if k.startsWith(prefix) and k.len > prefix.len:
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
  ## Push new local scope (NEW) — inherits current scope
  g.scopes.add(g.scopes[^1])

proc popScope*(g: var Globals) =
  ## Pop local scope (QUIT) — discards current scope
  if g.scopes.len > 1:
    g.scopes.setLen(g.scopes.len - 1)

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
