# data_structures.nim — nimm data structures
# Implements 9 M/MUMPS-compatible data structures

import tables
import deques
import strutils
import sequtils

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

# --- NiHeap (Priority Queue) ---
type
  NiHeap* = object
    ## Min-heap priority queue
    data*: seq[string]
    cmp*: proc(a, b: string): int

proc defaultCmp(a, b: string): int =
  if a < b: return -1
  if a > b: return 1
  return 0

proc newHeap*(): NiHeap =
  result.data = @[]
  result.cmp = defaultCmp

proc parent(i: int): int = (i - 1) div 2
proc left(i: int): int = 2 * i + 1
proc right(i: int): int = 2 * i + 2

proc heapifyUp(h: var NiHeap, i: int) =
  var idx = i
  while idx > 0:
    let p = parent(idx)
    if h.cmp(h.data[idx], h.data[p]) < 0:
      swap(h.data[idx], h.data[p])
      idx = p
    else:
      break

proc heapifyDown(h: var NiHeap, i: int) =
  var idx = i
  while true:
    let l = left(idx)
    let r = right(idx)
    var smallest = idx
    if l < h.data.len and h.cmp(h.data[l], h.data[smallest]) < 0:
      smallest = l
    if r < h.data.len and h.cmp(h.data[r], h.data[smallest]) < 0:
      smallest = r
    if smallest != idx:
      swap(h.data[idx], h.data[smallest])
      idx = smallest
    else:
      break

proc push*(h: var NiHeap, value: string) =
  h.data.add(value)
  heapifyUp(h, h.data.len - 1)

proc pop*(h: var NiHeap): string =
  if h.data.len == 0: return ""
  result = h.data[0]
  h.data[0] = h.data[^1]
  h.data.setLen(h.data.len - 1)
  if h.data.len > 0:
    heapifyDown(h, 0)

proc peek*(h: NiHeap): string =
  if h.data.len > 0: return h.data[0]
  return ""

proc len*(h: NiHeap): int = h.data.len

# --- NiRing (Circular Buffer) ---
type
  NiRing* = object
    ## Fixed-size circular buffer
    data*: seq[string]
    capacity*: int
    head*: int
    tail*: int
    count*: int

proc newRing*(capacity: int): NiRing =
  result.data = newSeq[string](capacity)
  result.capacity = capacity
  result.head = 0
  result.tail = 0
  result.count = 0

proc push*(r: var NiRing, value: string) =
  r.data[r.tail] = value
  r.tail = (r.tail + 1) mod r.capacity
  if r.count < r.capacity:
    inc r.count
  else:
    r.head = (r.head + 1) mod r.capacity

proc pop*(r: var NiRing): string =
  if r.count == 0: return ""
  result = r.data[r.head]
  r.head = (r.head + 1) mod r.capacity
  dec r.count

proc peek*(r: NiRing): string =
  if r.count == 0: return ""
  return r.data[r.head]

proc len*(r: NiRing): int = r.count

proc isFull*(r: NiRing): bool = r.count == r.capacity

proc isEmpty*(r: NiRing): bool = r.count == 0

proc toSeq*(r: NiRing): seq[string] =
  result = @[]
  var idx = r.head
  for i in 0..<r.count:
    result.add(r.data[idx])
    idx = (idx + 1) mod r.capacity

# --- NiLRU (LRU Cache) ---
type
  NiLRU* = object
    ## Least Recently Used cache
    capacity*: int
    order*: seq[string]  # Most recent at end
    data*: Table[string, string]

proc newLRU*(capacity: int): NiLRU =
  result.capacity = capacity
  result.order = @[]
  result.data = initTable[string, string]()

proc get*(lru: var NiLRU, key: string): string =
  if key in lru.data:
    # Move to end (most recent)
    lru.order = lru.order.filterIt(it != key)
    lru.order.add(key)
    return lru.data[key]
  return ""

proc put*(lru: var NiLRU, key: string, value: string) =
  if key in lru.data:
    # Update existing
    lru.data[key] = value
    lru.order = lru.order.filterIt(it != key)
    lru.order.add(key)
  else:
    # Evict if full
    if lru.order.len >= lru.capacity:
      let evict = lru.order[0]
      lru.order.delete(0)
      lru.data.del(evict)
    lru.data[key] = value
    lru.order.add(key)

proc has*(lru: NiLRU, key: string): bool = key in lru.data

proc len*(lru: NiLRU): int = lru.data.len

proc clear*(lru: var NiLRU) =
  lru.order.setLen(0)
  lru.data.clear()

# --- NiBitSet ---
type
  NiBitSet* = object
    ## Bit array for efficient boolean operations
    bits*: seq[uint64]
    size*: int

proc newBitSet*(size: int): NiBitSet =
  let numWords = (size + 63) div 64
  result.bits = newSeq[uint64](numWords)
  result.size = size

proc set*(bs: var NiBitSet, index: int) =
  if index >= 0 and index < bs.size:
    let word = index div 64
    let bit = index mod 64
    bs.bits[word] = bs.bits[word] or (1'u64 shl bit)

proc clear*(bs: var NiBitSet, index: int) =
  if index >= 0 and index < bs.size:
    let word = index div 64
    let bit = index mod 64
    bs.bits[word] = bs.bits[word] and not (1'u64 shl bit)

proc test*(bs: NiBitSet, index: int): bool =
  if index >= 0 and index < bs.size:
    let word = index div 64
    let bit = index mod 64
    return (bs.bits[word] and (1'u64 shl bit)) != 0
  return false

proc count*(bs: NiBitSet): int =
  result = 0
  for word in bs.bits:
    var w = word
    while w > 0:
      result += int(w and 1)
      w = w shr 1

proc `or`*(a, b: NiBitSet): NiBitSet =
  assert a.size == b.size
  result = newBitSet(a.size)
  for i in 0..<a.bits.len:
    result.bits[i] = a.bits[i] or b.bits[i]

proc `and`*(a, b: NiBitSet): NiBitSet =
  assert a.size == b.size
  result = newBitSet(a.size)
  for i in 0..<a.bits.len:
    result.bits[i] = a.bits[i] and b.bits[i]

proc clear*(bs: var NiBitSet) =
  for i in 0..<bs.bits.len:
    bs.bits[i] = 0

# --- NiTrie (Prefix Tree) ---
type
  TrieNode = ref object
    children*: Table[char, TrieNode]
    isEnd*: bool
    value*: string

  NiTrie* = object
    ## Prefix tree for string searching
    root*: TrieNode

proc newTrie*(): NiTrie =
  result.root = TrieNode(children: initTable[char, TrieNode](), isEnd: false)

proc insert*(t: var NiTrie, key: string, value: string = "") =
  var node = t.root
  for ch in key:
    if ch notin node.children:
      node.children[ch] = TrieNode(children: initTable[char, TrieNode](), isEnd: false)
    node = node.children[ch]
  node.isEnd = true
  node.value = value

proc search*(t: NiTrie, key: string): bool =
  var node = t.root
  for ch in key:
    if ch notin node.children:
      return false
    node = node.children[ch]
  return node.isEnd

proc get*(t: NiTrie, key: string): string =
  var node = t.root
  for ch in key:
    if ch notin node.children:
      return ""
    node = node.children[ch]
  if node.isEnd:
    return node.value
  return ""

proc startsWith*(t: NiTrie, prefix: string): bool =
  var node = t.root
  for ch in prefix:
    if ch notin node.children:
      return false
    node = node.children[ch]
  return true

proc collectAll(node: TrieNode, prefix: string, results: var seq[string]) =
  if node.isEnd:
    results.add(prefix)
  for ch, child in node.children:
    collectAll(child, prefix & ch, results)

proc autocomplete*(t: NiTrie, prefix: string): seq[string] =
  result = @[]
  var node = t.root
  for ch in prefix:
    if ch notin node.children:
      return result
    node = node.children[ch]
  collectAll(node, prefix, result)

# --- NiGraph (Adjacency List) ---
type
  NiGraph* = object
    ## Graph with adjacency lists
    adj*: Table[string, seq[(string, float)]]  # node -> [(neighbor, weight)]
    directed*: bool

proc newGraph*(directed: bool = true): NiGraph =
  result.adj = initTable[string, seq[(string, float)]]()
  result.directed = directed

proc addNode*(g: var NiGraph, node: string) =
  if node notin g.adj:
    g.adj[node] = @[]

proc addEdge*(g: var NiGraph, src: string, dst: string, weight: float = 1.0) =
  g.addNode(src)
  g.addNode(dst)
  g.adj[src].add((dst, weight))
  if not g.directed:
    g.adj[dst].add((src, weight))

proc neighbors*(g: NiGraph, node: string): seq[(string, float)] =
  if node in g.adj:
    return g.adj[node]
  return @[]

proc hasNode*(g: NiGraph, node: string): bool = node in g.adj

proc hasEdge*(g: NiGraph, src: string, dst: string): bool =
  if src notin g.adj: return false
  for (n, w) in g.adj[src]:
    if n == dst: return true
  return false

proc nodeCount*(g: NiGraph): int = g.adj.len

proc edgeCount*(g: NiGraph): int =
  result = 0
  for edges in g.adj.values:
    result += edges.len
  if not g.directed:
    result = result div 2

proc dfs*(g: NiGraph, start: string): seq[string] =
  ## Depth-first search traversal
  result = @[]
  var visited: Table[string, bool] = initTable[string, bool]()
  var stack: seq[string] = @[start]
  while stack.len > 0:
    let node = stack.pop()
    if node in visited: continue
    visited[node] = true
    result.add(node)
    for (neighbor, _) in g.neighbors(node):
      if neighbor notin visited:
        stack.add(neighbor)

proc bfs*(g: NiGraph, start: string): seq[string] =
  ## Breadth-first search traversal
  result = @[]
  var visited: Table[string, bool] = initTable[string, bool]()
  var queue: seq[string] = @[start]
  visited[start] = true
  while queue.len > 0:
    let node = queue[0]
    queue.delete(0)
    result.add(node)
    for (neighbor, _) in g.neighbors(node):
      if neighbor notin visited:
        visited[neighbor] = true
        queue.add(neighbor)

# --- NiMatrix (2D Array) ---
type
  NiMatrix* = object
    ## 2D matrix for numerical computing
    rows*: int
    cols*: int
    data*: seq[float]

proc newMatrix*(rows, cols: int): NiMatrix =
  result.rows = rows
  result.cols = cols
  result.data = newSeq[float](rows * cols)

proc get*(m: NiMatrix, row, col: int): float =
  if row >= 0 and row < m.rows and col >= 0 and col < m.cols:
    return m.data[row * m.cols + col]
  return 0.0

proc set*(m: var NiMatrix, row, col: int, value: float) =
  if row >= 0 and row < m.rows and col >= 0 and col < m.cols:
    m.data[row * m.cols + col] = value

proc rows*(m: NiMatrix): int = m.rows
proc cols*(m: NiMatrix): int = m.cols

proc `+`*(a, b: NiMatrix): NiMatrix =
  assert a.rows == b.rows and a.cols == b.cols
  result = newMatrix(a.rows, a.cols)
  for i in 0..<a.data.len:
    result.data[i] = a.data[i] + b.data[i]

proc `*`*(a, b: NiMatrix): NiMatrix =
  assert a.cols == b.rows
  result = newMatrix(a.rows, b.cols)
  for i in 0..<a.rows:
    for j in 0..<b.cols:
      var sum = 0.0
      for k in 0..<a.cols:
        sum += a.get(i, k) * b.get(k, j)
      result.set(i, j, sum)

proc transpose*(m: NiMatrix): NiMatrix =
  result = newMatrix(m.cols, m.rows)
  for i in 0..<m.rows:
    for j in 0..<m.cols:
      result.set(j, i, m.get(i, j))

proc toString*(m: NiMatrix): string =
  result = ""
  for i in 0..<m.rows:
    for j in 0..<m.cols:
      if j > 0: result.add("\t")
      result.add($m.get(i, j))
    if i < m.rows - 1: result.add("\n")

# --- NiBloom (Bloom Filter) ---
type
  NiBloom* = object
    ## Bloom filter for probabilistic set membership
    bits*: NiBitSet
    hashCount*: int
    size*: int

proc newBloom*(size: int, hashCount: int = 3): NiBloom =
  result.bits = newBitSet(size)
  result.hashCount = hashCount
  result.size = size

proc hash(s: string, seed: uint32): uint32 =
  var h = seed
  for ch in s:
    h = h * 31 + uint32(ch)
  return h

proc add*(b: var NiBloom, item: string) =
  for i in 0..<b.hashCount:
    let h = hash(item, uint32(i)) mod uint32(b.size)
    b.bits.set(int(h))

proc contains*(b: NiBloom, item: string): bool =
  for i in 0..<b.hashCount:
    let h = hash(item, uint32(i)) mod uint32(b.size)
    if not b.bits.test(int(h)):
      return false
  return true

proc clear*(b: var NiBloom) =
  b.bits.clear()

