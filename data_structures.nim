# data_structures.nim — nimm data structures
# Implements 9 M/MUMPS-compatible data structures

import tables
import deques
import strutils
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

