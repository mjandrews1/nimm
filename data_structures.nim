# data_structures.nim — nimm data structures
# Implements 9 M/MUMPS-compatible data structures

import tables
import deques
import sequtils
import random

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
  if index < 0 or index >= arr.data.len:
    raise newException(IndexDefect, "NiArray index out of bounds: " & $index)
  return arr.data[index]

proc set*(arr: var NiArray, index: int, value: string) =
  if index < 0 or index >= arr.data.len:
    raise newException(IndexDefect, "NiArray index out of bounds: " & $index)
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

proc keys*(m: NiMap): seq[string] =
  result = @[]
  for (k, v) in m.data:
    result.add(k)

proc values*(m: NiMap): seq[string] =
  result = @[]
  for (k, v) in m.data:
    result.add(v)

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
  if capacity <= 0:
    raise newException(ValueError, "NiRing capacity must be positive: " & $capacity)
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
  if capacity <= 0:
    raise newException(ValueError, "NiLRU capacity must be positive: " & $capacity)
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
  if size < 0:
    raise newException(ValueError, "NiBitSet size must be non-negative: " & $size)
  let numWords = (size + 63) div 64
  result.bits = newSeq[uint64](numWords)
  result.size = size

proc set*(bs: var NiBitSet, index: int) =
  if index < 0 or index >= bs.size:
    raise newException(IndexDefect, "NiBitSet index out of bounds: " & $index)
  let word = index div 64
  let bit = index mod 64
  bs.bits[word] = bs.bits[word] or (1'u64 shl bit)

proc clear*(bs: var NiBitSet, index: int) =
  if index < 0 or index >= bs.size:
    raise newException(IndexDefect, "NiBitSet index out of bounds: " & $index)
  let word = index div 64
  let bit = index mod 64
  bs.bits[word] = bs.bits[word] and not (1'u64 shl bit)

proc test*(bs: NiBitSet, index: int): bool =
  if index < 0 or index >= bs.size:
    raise newException(IndexDefect, "NiBitSet index out of bounds: " & $index)
  let word = index div 64
  let bit = index mod 64
  return (bs.bits[word] and (1'u64 shl bit)) != 0

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

# --- NiSkipList ---
type
  SkipNode = ref object
    value*: string
    next*: seq[SkipNode]  # next[i] = next node at level i

  NiSkipList* = object
    ## Probabilistic sorted data structure with O(log n) search
    head*: SkipNode
    maxLevel*: int
    size*: int

proc newSkipList*(maxLevel: int = 16): NiSkipList =
  result.head = SkipNode(value: "", next: newSeq[SkipNode](maxLevel))
  result.maxLevel = maxLevel
  result.size = 0

proc randomLevel(maxLevel: int): int =
  var level = 1
  while level < maxLevel and (rand(1.0) < 0.5):
    inc level
  return level

proc search*(sl: NiSkipList, value: string): bool =
  var current = sl.head
  for i in countdown(sl.maxLevel - 1, 0):
    while current.next[i] != nil and current.next[i].value < value:
      current = current.next[i]
    if current.next[i] != nil and current.next[i].value == value:
      return true
  return false

proc insert*(sl: var NiSkipList, value: string) =
  var update = newSeq[SkipNode](sl.maxLevel)
  var current = sl.head
  
  for i in countdown(sl.maxLevel - 1, 0):
    while current.next[i] != nil and current.next[i].value < value:
      current = current.next[i]
    update[i] = current
  
  let newLevel = randomLevel(sl.maxLevel)
  let newNode = SkipNode(value: value, next: newSeq[SkipNode](newLevel))
  
  for i in 0..<newLevel:
    newNode.next[i] = update[i].next[i]
    update[i].next[i] = newNode
  
  inc sl.size

proc len*(sl: NiSkipList): int = sl.size

# --- NiTreap ---
type
  TreapNode = ref object
    value*: string
    priority*: float
    left*, right*: TreapNode

  NiTreap* = object
    ## Balanced BST with randomization
    root*: TreapNode
    size*: int

proc newTreap*(): NiTreap =
  result.root = nil
  result.size = 0

proc rotateRight(y: TreapNode): TreapNode =
  let x = y.left
  y.left = x.right
  x.right = y
  return x

proc rotateLeft(x: TreapNode): TreapNode =
  let y = x.right
  x.right = y.left
  y.left = x
  return y

proc insertNode(node: TreapNode, value: string): TreapNode =
  if node == nil:
    return TreapNode(value: value, priority: rand(1.0))
  
  var n = node
  if value < n.value:
    n.left = insertNode(n.left, value)
    if n.left.priority > n.priority:
      n = rotateRight(n)
  elif value > n.value:
    n.right = insertNode(n.right, value)
    if n.right.priority > n.priority:
      n = rotateLeft(n)
  
  return n

proc insert*(t: var NiTreap, value: string) =
  t.root = insertNode(t.root, value)
  inc t.size

proc searchNode(node: TreapNode, value: string): bool =
  if node == nil: return false
  if value == node.value: return true
  if value < node.value: return searchNode(node.left, value)
  return searchNode(node.right, value)

proc search*(t: NiTreap, value: string): bool =
  return searchNode(t.root, value)

proc len*(t: NiTreap): int = t.size

# --- NiDisjointSet ---
type
  NiDisjointSet* = object
    ## Union-find for connectivity problems
    parent*: seq[int]
    rank*: seq[int]
    size*: int

proc newDisjointSet*(n: int): NiDisjointSet =
  result.parent = newSeq[int](n)
  result.rank = newSeq[int](n)
  result.size = n
  for i in 0..<n:
    result.parent[i] = i

proc find*(ds: var NiDisjointSet, x: int): int =
  if ds.parent[x] != x:
    ds.parent[x] = ds.find(ds.parent[x])  # Path compression
  return ds.parent[x]

proc union*(ds: var NiDisjointSet, x, y: int) =
  let px = ds.find(x)
  let py = ds.find(y)
  if px == py: return
  
  # Union by rank
  if ds.rank[px] < ds.rank[py]:
    ds.parent[px] = py
  elif ds.rank[px] > ds.rank[py]:
    ds.parent[py] = px
  else:
    ds.parent[py] = px
    inc ds.rank[px]

proc connected*(ds: var NiDisjointSet, x, y: int): bool =
  return ds.find(x) == ds.find(y)

proc componentCount*(ds: var NiDisjointSet): int =
  var roots: seq[int] = @[]
  for i in 0..<ds.size:
    if ds.find(i) == i:
      roots.add(i)
  return roots.len

# --- NiSegmentTree ---
type
  NiSegmentTree* = object
    ## Range query data structure (min/max/sum)
    data*: seq[int]
    tree*: seq[int]
    n*: int
    op*: string  # "min", "max", "sum"

proc newSegmentTree*(n: int, op: string = "sum"): NiSegmentTree =
  result.n = n
  result.data = newSeq[int](n)
  result.tree = newSeq[int](4 * n)
  result.op = op

proc merge(a, b: int, op: string): int =
  case op
  of "min": return min(a, b)
  of "max": return max(a, b)
  of "sum": return a + b
  else: return a + b

proc build*(st: var NiSegmentTree, node, start, endIdx: int) =
  if start == endIdx:
    st.tree[node] = st.data[start]
  else:
    let mid = (start + endIdx) div 2
    st.build(2 * node, start, mid)
    st.build(2 * node + 1, mid + 1, endIdx)
    st.tree[node] = merge(st.tree[2 * node], st.tree[2 * node + 1], st.op)

proc update*(st: var NiSegmentTree, node, start, endIdx, idx, val: int) =
  if start == endIdx:
    st.data[idx] = val
    st.tree[node] = val
  else:
    let mid = (start + endIdx) div 2
    if idx <= mid:
      st.update(2 * node, start, mid, idx, val)
    else:
      st.update(2 * node + 1, mid + 1, endIdx, idx, val)
    st.tree[node] = merge(st.tree[2 * node], st.tree[2 * node + 1], st.op)

proc query*(st: NiSegmentTree, node, start, endIdx, l, r: int): int =
  if r < start or endIdx < l:
    case st.op
    of "min": return high(int)
    of "max": return low(int)
    of "sum": return 0
    else: return 0
  if l <= start and endIdx <= r:
    return st.tree[node]
  let mid = (start + endIdx) div 2
  let left = st.query(2 * node, start, mid, l, r)
  let right = st.query(2 * node + 1, mid + 1, endIdx, l, r)
  return merge(left, right, st.op)

# --- NiFenwickTree ---
type
  NiFenwickTree* = object
    ## Binary indexed tree for prefix sums
    data*: seq[int]
    n*: int

proc newFenwickTree*(n: int): NiFenwickTree =
  result.data = newSeq[int](n + 1)
  result.n = n

proc update*(ft: var NiFenwickTree, i: int, delta: int) =
  var idx = i + 1
  while idx <= ft.n:
    ft.data[idx] += delta
    idx += (idx and (-idx))

proc query*(ft: NiFenwickTree, i: int): int =
  result = 0
  var idx = i + 1
  while idx > 0:
    result += ft.data[idx]
    idx -= (idx and (-idx))

proc rangeQuery*(ft: NiFenwickTree, l, r: int): int =
  if l == 0:
    return ft.query(r)
  return ft.query(r) - ft.query(l - 1)

# --- NiSparseMatrix ---
type
  NiSparseMatrix* = object
    ## Sparse 2D data structure
    rows*: int
    cols*: int
    data*: Table[(int, int), float]

proc newSparseMatrix*(rows, cols: int): NiSparseMatrix =
  result.rows = rows
  result.cols = cols
  result.data = initTable[(int, int), float]()

proc get*(m: NiSparseMatrix, row, col: int): float =
  let key = (row, col)
  if key in m.data:
    return m.data[key]
  return 0.0

proc set*(m: var NiSparseMatrix, row, col: int, value: float) =
  if value != 0.0:
    m.data[(row, col)] = value
  elif (row, col) in m.data:
    m.data.del((row, col))

proc nnz*(m: NiSparseMatrix): int = m.data.len

proc toDense*(m: NiSparseMatrix): seq[seq[float]] =
  result = newSeq[seq[float]](m.rows)
  for i in 0..<m.rows:
    result[i] = newSeq[float](m.cols)
  for key, val in m.data.pairs:
    result[key[0]][key[1]] = val

# --- NiIntervalTree ---
type
  Interval = object
    low*, high*: int
    data*: string

  IntervalNode = ref object
    interval*: Interval
    max*: int
    left*, right*: IntervalNode

  NiIntervalTree* = object
    ## Interval overlap queries
    root*: IntervalNode

proc newIntervalTree*(): NiIntervalTree =
  result.root = nil

proc newNode(interval: Interval): IntervalNode =
  result = IntervalNode(interval: interval, max: interval.high)

proc insertNode(node: IntervalNode, interval: Interval): IntervalNode =
  if node == nil:
    return newNode(interval)
  
  let l = node.interval.low
  
  if interval.low < l:
    node.left = insertNode(node.left, interval)
  else:
    node.right = insertNode(node.right, interval)
  
  if node.max < interval.high:
    node.max = interval.high
  
  return node

proc insert*(it: var NiIntervalTree, low, high: int, data: string = "") =
  it.root = insertNode(it.root, Interval(low: low, high: high, data: data))

proc overlaps(a, b: Interval): bool =
  return a.low <= b.high and b.low <= a.high

proc findOverlapping(node: IntervalNode, interval: Interval): seq[Interval] =
  result = @[]
  if node == nil: return
  
  if overlaps(node.interval, interval):
    result.add(node.interval)
  
  if node.left != nil and node.left.max >= interval.low:
    result.add(findOverlapping(node.left, interval))
  
  result.add(findOverlapping(node.right, interval))

proc query*(it: NiIntervalTree, low, high: int): seq[Interval] =
  return findOverlapping(it.root, Interval(low: low, high: high))

# --- NiSuffixArray ---
type
  NiSuffixArray* = object
    ## Suffix array for string pattern matching
    text*: string
    sa*: seq[int]       # suffix array (sorted indices)
    lcp*: seq[int]      # longest common prefix array

proc buildSuffixArray*(text: string): seq[int] =
  ## Build suffix array using prefix doubling
  let n = text.len
  var sa = newSeq[int](n)
  var rank = newSeq[int](n)
  var tmp = newSeq[int](n)
  
  for i in 0..<n:
    sa[i] = i
    rank[i] = int(text[i])
  
  var k = 1
  while k < n:
    # Create comparison pairs
    var pairs = newSeq[(int, int, int)](n)
    for i in 0..<n:
      let ri = rank[i]
      let rj = if i + k < n: rank[i + k] else: -1
      pairs[i] = (ri, rj, i)
    
    # Sort by pairs (bubble sort for simplicity)
    for i in 0..<n-1:
      for j in 0..<n-i-1:
        let cmp_r1 = pairs[j][0] - pairs[j+1][0]
        let cmp_r2 = pairs[j][1] - pairs[j+1][1]
        if cmp_r1 > 0 or (cmp_r1 == 0 and cmp_r2 > 0):
          swap(pairs[j], pairs[j+1])
    
    # Extract sorted indices
    for i in 0..<n:
      sa[i] = pairs[i][2]
    
    # Update ranks
    tmp[sa[0]] = 0
    for i in 1..<n:
      tmp[sa[i]] = tmp[sa[i-1]]
      if pairs[i][0] != pairs[i-1][0] or pairs[i][1] != pairs[i-1][1]:
        inc tmp[sa[i]]
    
    for i in 0..<n:
      rank[i] = tmp[i]
    
    if rank[sa[n-1]] == n - 1:
      break
    k *= 2
  
  return sa

proc buildLCP(text: string, sa: seq[int]): seq[int] =
  ## Build LCP array from suffix array
  let n = text.len
  var rank = newSeq[int](n)
  for i in 0..<n:
    rank[sa[i]] = i
  
  result = newSeq[int](n)
  var h = 0
  for i in 0..<n:
    if rank[i] > 0:
      let j = sa[rank[i] - 1]
      while i + h < n and j + h < n and text[i + h] == text[j + h]:
        inc h
      result[rank[i]] = h
      if h > 0: dec h

proc newSuffixArray*(text: string): NiSuffixArray =
  result.text = text
  result.sa = buildSuffixArray(text)
  result.lcp = buildLCP(text, result.sa)

proc search*(sa: NiSuffixArray, pattern: string): seq[int] =
  ## Search for pattern in suffix array
  result = @[]
  let n = sa.text.len
  let m = pattern.len
  if m == 0 or m > n: return
  
  # Binary search for first occurrence
  var lo = 0
  var hi = n
  while lo < hi:
    let mid = (lo + hi) div 2
    let suffix = sa.text[sa.sa[mid]..^1]
    let cmpLen = min(m, suffix.len)
    let cmp = suffix[0..<cmpLen].cmp(pattern[0..<cmpLen])
    if cmp < 0:
      lo = mid + 1
    else:
      hi = mid
  
  # Collect all matches
  var i = lo
  while i < n:
    let suffix = sa.text[sa.sa[i]..^1]
    if suffix.len >= m and suffix[0..<m] == pattern:
      result.add(sa.sa[i])
    else:
      let cmpLen = min(m, suffix.len)
      if suffix[0..<cmpLen].cmp(pattern[0..<cmpLen]) > 0:
        break
    inc i

# --- NiWaveletTree ---
type
  WaveletNode = ref object
    low*, high*: int
    bits*: seq[int]  # bit vector (cumulative count)
    left*, right*: WaveletNode

  NiWaveletTree* = object
    ## Wavelet tree for range queries on sequences
    root*: WaveletNode
    minVal*, maxVal*: int
    data*: seq[int]

proc buildWavelet(data: seq[int], lo, hi: int): WaveletNode =
  if data.len == 0: return nil
  
  if lo >= hi:
    # Leaf node - all values are the same
    var node = WaveletNode(low: lo, high: hi)
    node.bits = newSeq[int](data.len + 1)
    for i in 0..<data.len:
      node.bits[i + 1] = node.bits[i] + 1
    return node
  
  let mid = (lo + hi) div 2
  var node = WaveletNode(low: lo, high: hi)
  node.bits = newSeq[int](data.len + 1)
  
  var leftData, rightData: seq[int] = @[]
  for i in 0..<data.len:
    node.bits[i + 1] = node.bits[i]
    if data[i] <= mid:
      leftData.add(data[i])
      inc node.bits[i + 1]
    else:
      rightData.add(data[i])
  
  node.left = buildWavelet(leftData, lo, mid)
  node.right = buildWavelet(rightData, mid + 1, hi)
  return node

proc newWaveletTree*(data: seq[int]): NiWaveletTree =
  result.data = data
  if data.len == 0:
    result.minVal = 0
    result.maxVal = 0
  else:
    result.minVal = data[0]
    result.maxVal = data[0]
    for v in data:
      if v < result.minVal: result.minVal = v
      if v > result.maxVal: result.maxVal = v
  result.root = buildWavelet(data, result.minVal, result.maxVal)

proc rank*(node: WaveletNode, pos: int, val: int): int =
  ## Count occurrences of val in [0, pos]
  if node == nil or pos < 0: return 0
  if node.low == node.high:
    return pos + 1  # All values at this level match
  let mid = (node.low + node.high) div 2
  if val <= mid:
    let newpos = node.bits[pos + 1] - 1
    return rank(node.left, newpos, val)
  else:
    let newpos = pos - node.bits[pos + 1]
    return rank(node.right, newpos, val)

proc rangeRank*(wt: NiWaveletTree, lo, hi: int, val: int): int =
  ## Count occurrences of val in [lo, hi]
  if lo > hi: return 0
  return rank(wt.root, hi, val) - (if lo > 0: rank(wt.root, lo - 1, val) else: 0)

# --- NiKdTree ---
type
  KdPoint = object
    coords*: seq[float]
    data*: string

  KdNode = ref object
    point*: KdPoint
    left*, right*: KdNode
    axis*: int

  NiKdTree* = object
    ## K-d tree for spatial queries
    root*: KdNode
    dimensions*: int

proc newKdTree*(dimensions: int): NiKdTree =
  result.root = nil
  result.dimensions = dimensions

proc buildKdTree(points: var seq[KdPoint], depth: int, dims: int): KdNode =
  if points.len == 0: return nil
  
  let axis = depth mod dims
  
  # Sort by axis (bubble sort)
  for i in 0..<points.len-1:
    for j in 0..<points.len-i-1:
      if points[j].coords[axis] > points[j+1].coords[axis]:
        swap(points[j], points[j+1])
  
  let mid = points.len div 2
  var left = points[0..<mid]
  var right = points[mid+1..^1]
  
  result = KdNode(
    point: points[mid],
    axis: axis,
    left: buildKdTree(left, depth + 1, dims),
    right: buildKdTree(right, depth + 1, dims)
  )

proc insert*(tree: var NiKdTree, coords: seq[float], data: string = "") =
  let point = KdPoint(coords: coords, data: data)
  var points: seq[KdPoint] = @[]
  
  # Collect existing points
  proc collect(node: KdNode) =
    if node == nil: return
    points.add(node.point)
    collect(node.left)
    collect(node.right)
  
  collect(tree.root)
  points.add(point)
  tree.root = buildKdTree(points, 0, tree.dimensions)

proc distanceSquared(a, b: seq[float]): float =
  result = 0.0
  for i in 0..<a.len:
    let d = a[i] - b[i]
    result += d * d

proc nearestNeighbor(node: KdNode, target: seq[float], best: var KdPoint, bestDist: var float) =
  if node == nil: return
  
  let dist = distanceSquared(node.point.coords, target)
  if dist < bestDist:
    bestDist = dist
    best = node.point
  
  let axis = node.axis
  let diff = target[axis] - node.point.coords[axis]
  
  var first, second: KdNode
  if diff < 0:
    first = node.left
    second = node.right
  else:
    first = node.right
    second = node.left
  
  nearestNeighbor(first, target, best, bestDist)
  
  if diff * diff < bestDist:
    nearestNeighbor(second, target, best, bestDist)

proc nearest*(tree: NiKdTree, coords: seq[float]): KdPoint =
  var best = KdPoint()
  var bestDist = high(float)
  nearestNeighbor(tree.root, coords, best, bestDist)
  return best

# --- NiRope ---
type
  RopeNode = ref object
    left*, right*: RopeNode
    text*: string
    weight*: int  # total length of left subtree

  NiRope* = object
    ## Rope for large string manipulation
    root*: RopeNode
    length*: int

proc newRope*(text: string): NiRope =
  result.root = RopeNode(text: text, weight: text.len)
  result.length = text.len

proc ropeLen(node: RopeNode): int =
  if node == nil: return 0
  return node.weight + (if node.right != nil: ropeLen(node.right) else: 0)

proc buildRope(text: string): RopeNode =
  if text.len <= 32:  # leaf threshold
    return RopeNode(text: text, weight: text.len)
  
  let mid = text.len div 2
  result = RopeNode(
    left: buildRope(text[0..<mid]),
    right: buildRope(text[mid..^1]),
    weight: mid
  )

proc concat*(a, b: NiRope): NiRope =
  result.root = RopeNode(left: a.root, right: b.root, weight: ropeLen(a.root))
  result.length = a.length + b.length

proc toString*(node: RopeNode): string =
  if node == nil: return ""
  result = ""
  if node.left != nil:
    result.add(toString(node.left))
  result.add(node.text)
  if node.right != nil:
    result.add(toString(node.right))

proc toString*(r: NiRope): string =
  return toString(r.root)

proc substring*(r: NiRope, start, length: int): string =
  let s = r.toString()
  if start < 0 or start >= s.len: return ""
  let endIdx = min(start + length, s.len)
  return s[start..<endIdx]

# --- NiMerkleTree ---
type
  MerkleNode = ref object
    hash*: string
    left*, right*: MerkleNode
    data*: string  # leaf data

  NiMerkleTree* = object
    ## Merkle tree for cryptographic verification
    root*: MerkleNode
    leaves*: seq[string]

proc simpleHash(s: string): string =
  ## Simple hash for demonstration (use SHA-256 in production)
  var h: uint32 = 2166136261'u32
  for ch in s:
    h = h xor uint32(ch)
    h = h * 16777619'u32
  return $h

proc buildMerkleTree(leaves: seq[string]): MerkleNode =
  if leaves.len == 0: return nil
  if leaves.len == 1:
    return MerkleNode(hash: simpleHash(leaves[0]), data: leaves[0])
  
  let mid = (leaves.len + 1) div 2
  let left = buildMerkleTree(leaves[0..<mid])
  let right = buildMerkleTree(leaves[mid..^1])
  
  let combined = (if left != nil: left.hash else: "") & (if right != nil: right.hash else: "")
  return MerkleNode(
    hash: simpleHash(combined),
    left: left,
    right: right
  )

proc newMerkleTree*(data: seq[string]): NiMerkleTree =
  result.leaves = data
  result.root = buildMerkleTree(data)

proc rootHash*(tree: NiMerkleTree): string =
  if tree.root != nil:
    return tree.root.hash
  return ""

proc verify*(tree: NiMerkleTree, index: int, data: string): bool =
  ## Verify a leaf is in the tree
  if index < 0 or index >= tree.leaves.len: return false
  return tree.leaves[index] == data

proc leafCount*(tree: NiMerkleTree): int = tree.leaves.len

