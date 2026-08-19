# global_store.nim — Abstract storage interface for nimm
# Provides a common interface for different storage backends

type
  GlobalStore* = ref object of RootObj
    ## Abstract base class for global storage

proc init*(store: var GlobalStore, path: string) {.base.} =
  ## Initialize the store
  raise newException(CatchableError, "Not implemented")

proc close*(store: var GlobalStore) {.base.} =
  ## Close the store
  raise newException(CatchableError, "Not implemented")

proc get*(store: GlobalStore, global: string, subs: seq[string] = @[]): string {.base.} =
  ## Get value for global[sub1,sub2,...]
  raise newException(CatchableError, "Not implemented")

proc put*(store: GlobalStore, global: string, subs: seq[string], value: string) {.base.} =
  ## Set value for global[sub1,sub2,...]
  raise newException(CatchableError, "Not implemented")

proc delete*(store: GlobalStore, global: string, subs: seq[string] = @[]) {.base.} =
  ## Delete global[sub1,sub2,...]
  raise newException(CatchableError, "Not implemented")

proc order*(store: GlobalStore, global: string, subs: seq[string] = @[], forward: bool = true): string {.base.} =
  ## Get next/previous subscript
  raise newException(CatchableError, "Not implemented")

proc sync*(store: GlobalStore) {.base.} =
  ## Flush data to disk
  raise newException(CatchableError, "Not implemented")

proc listKeys*(store: GlobalStore, prefix: string = ""): seq[string] {.base.} =
  ## List all keys with optional prefix
  raise newException(CatchableError, "Not implemented")
