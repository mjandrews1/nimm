# data_structures.nim — nimm data structures
# Implements 9 M/MUMPS-compatible data structures

import tables
import deques
import algorithm
import strutils

type
  NiArray* = object
    ## Dynamic array (ordered sequence of values)
    data*: seq[string]

  NiObject* = object
    ## Key-value object (unordered)
    data*: Table[string, string]

  NiStack* = object
    ## LIFO stack
    data*: seq[string]

  NiQueue* = object
    ## FIFO queue
    data*: seq[string]

  NiSet* = object
    ## Unordered set (unique values)
    data*: Table[string, bool]

  NiMap* = object
    ## Ordered map (key-value, sorted by key)
    data*: seq[(string, string)]

  NiSorted* = object
    ## Sorted collection (unique values, sorted)
    data*: seq[string]

  NiDeque* = object
    ## Double-ended queue
    data*: Deque[string]

  NiBag* = object
    ## Multiset (allows duplicate values)
    data*: Table[string, int]  # value -> count

# --- NiArray ---
proc newArray*(): NiArray = NiArray(data: @[])

proc add*(arr: var NiArray, value: string) =
  arr.data.add(value)

proc get*(arr: NiArray, index: int): string =
  if index >= 0 and index < arr.data.len:
    return arr.data[index]
  return ""

proc set*(arr: var NiArray, index: int, value: string) =
  if index >= 0 and index < arr.data.len:
    arr.data[index] = value

proc len*(arr: NiArray): int = arr.data.len

proc clear*(arr: var NiArray) = arr.data.setLen(0)

# --- NiObject ---
proc newObject*(): NiObject = NiObject(data: initTable[string, string]())

proc set*(obj: var NiObject, key: string, value: string) =
  obj.data[key] = value

proc get*(obj: NiObject, key: string): string =
  if key in obj.data:
    return obj.data[key]
  return ""

proc has*(obj: NiObject, key: string): bool = key in obj.data

proc del*(obj: var NiObject, key: string) = obj.data.del(key)

proc len*(obj: NiObject): int = obj.data.len

proc clear*(obj: var NiObject) = obj.data.clear()

# --- NiStack ---
proc newStack*(): NiStack = NiStack(data: @[])

proc push*(s: var NiStack, value: string) = s.data.add(value)

proc pop*(s: var NiStack): string =
  if s.data.len > 0:
    result = s.data[^1]
    s.data.setLen(s.data.len - 1)
  else:
    result = ""

proc peek*(s: NiStack): string =
  if s.data.len > 0:
    return s.data[^1]
  return ""

proc len*(s: NiStack): int = s.data.len

proc isEmpty*(s: NiStack): bool = s.data.len == 0

# --- NiQueue ---
proc newQueue*(): NiQueue = NiQueue(data: @[])

proc enqueue*(q: var NiQueue, value: string) = q.data.add(value)

proc dequeue*(q: var NiQueue): string =
  if q.data.len > 0:
    result = q.data[0]
    q.data.delete(0)
  else:
    result = ""

proc peek*(q: NiQueue): string =
  if q.data.len > 0:
    return q.data[0]
  return ""

proc len*(q: NiQueue): int = q.data.len

proc isEmpty*(q: NiQueue): bool = q.data.len == 0

# --- NiSet ---
proc newSet*(): NiSet = NiSet(data: initTable[string, bool]())

proc add*(s: var NiSet, value: string) = s.data[value] = true

proc contains*(s: NiSet, value: string): bool = value in s.data

proc remove*(s: var NiSet, value: string) = s.data.del(value)

proc len*(s: NiSet): int = s.data.len

proc clear*(s: var NiSet) = s.data.clear()

proc toSeq*(s: NiSet): seq[string] =
  result = @[]
  for key in s.data.keys:
    result.add(key)

# --- NiMap ---
proc newMap*(): NiMap = NiMap(data: @[])

proc set*(m: var NiMap, key: string, value: string) =
  # Update existing or insert sorted
  for i, (k, v) in m.data:
    if k == key:
      m.data[i] = (key, value)
      return
  # Insert in sorted position
  var pos = 0
  for i, (k, v) in m.data:
    if key < k:
      break
    pos = i + 1
  m.data.insert((key, value), pos)

proc get*(m: NiMap, key: string): string =
  for (k, v) in m.data:
    if k == key:
      return v
  return ""

proc has*(m: NiMap, key: string): bool =
  for (k, v) in m.data:
    if k == key:
      return true
  return false

proc del*(m: var NiMap, key: string) =
  for i, (k, v) in m.data:
    if k == key:
      m.data.delete(i)
      return

proc len*(m: NiMap): int = m.data.len

proc clear*(m: var NiMap) = m.data.setLen(0)

# --- NiSorted ---
proc newSorted*(): NiSorted = NiSorted(data: @[])

proc add*(s: var NiSorted, value: string) =
  # Insert in sorted position (unique)
  for i, v in s.data:
    if v == value:
      return  # Already exists
    if value < v:
      s.data.insert(value, i)
      return
  s.data.add(value)

proc contains*(s: NiSorted, value: string): bool =
  for v in s.data:
    if v == value:
      return true
  return false

proc remove*(s: var NiSorted, value: string) =
  for i, v in s.data:
    if v == value:
      s.data.delete(i)
      return

proc len*(s: NiSorted): int = s.data.len

proc toSeq*(s: NiSorted): seq[string] = s.data

# --- NiDeque ---
proc newDeque*(): NiDeque = NiDeque(data: initDeque[string]())

proc pushFront*(d: var NiDeque, value: string) = d.data.addFirst(value)

proc pushBack*(d: var NiDeque, value: string) = d.data.addLast(value)

proc popFront*(d: var NiDeque): string =
  if d.data.len > 0:
    result = d.data.popFirst()
  else:
    result = ""

proc popBack*(d: var NiDeque): string =
  if d.data.len > 0:
    result = d.data.popLast()
  else:
    result = ""

proc peekFront*(d: NiDeque): string =
  if d.data.len > 0:
    return d.data[0]
  return ""

proc peekBack*(d: NiDeque): string =
  if d.data.len > 0:
    return d.data[^1]
  return ""

proc len*(d: NiDeque): int = d.data.len

proc isEmpty*(d: NiDeque): bool = d.data.len == 0

# --- NiBag ---
proc newBag*(): NiBag = NiBag(data: initTable[string, int]())

proc add*(b: var NiBag, value: string, count: int = 1) =
  if value in b.data:
    b.data[value] += count
  else:
    b.data[value] = count

proc count*(b: NiBag, value: string): int =
  if value in b.data:
    return b.data[value]
  return 0

proc remove*(b: var NiBag, value: string, count: int = 1) =
  if value in b.data:
    b.data[value] -= count
    if b.data[value] <= 0:
      b.data.del(value)

proc len*(b: NiBag): int =
  result = 0
  for v in b.data.values:
    result += v

proc uniqueLen*(b: NiBag): int = b.data.len

proc clear*(b: var NiBag) = b.data.clear()
