# network.nim — Network commands for nimm
# Implements NIOPEN, NILISTEN, NIREAD, NIWRITE, NICLOSE

import nativesockets
import net
import strutils
import tables

type
  NiConnection* = object
    ## Network connection state
    socket*: Socket
    isOpen*: bool
    isListening*: bool

  NetworkManager* = object
    ## Manages network connections
    connections*: Table[int, NiConnection]
    nextId*: int

proc newNetworkManager*(): NetworkManager =
  result.connections = initTable[int, NiConnection]()
  result.nextId = 100

proc niopen*(nm: var NetworkManager, protocol: string, host: string, port: int): int =
  ## Open a network connection
  ## Returns connection ID or -1 on error
  
  if protocol.toLowerAscii() == "tcp":
    let sock = newSocket()
    try:
      sock.connect(host, Port(port))
      let id = nm.nextId
      inc nm.nextId
      nm.connections[id] = NiConnection(
        socket: sock,
        isOpen: true,
        isListening: false
      )
      return id
    except:
      sock.close()
      return -1
  else:
    return -1

proc nilisten*(nm: var NetworkManager, port: int): int =
  ## Listen for connections on a port
  ## Returns listener ID or -1 on error
  
  let sock = newSocket()
  try:
    sock.setSockOpt(OptReuseAddr, true)
    sock.bindAddr(Port(port))
    sock.listen()
    
    let id = nm.nextId
    inc nm.nextId
    nm.connections[id] = NiConnection(
      socket: sock,
      isOpen: true,
      isListening: true
    )
    return id
  except:
    sock.close()
    return -1

proc niaccept*(nm: var NetworkManager, listenerId: int): int =
  ## Accept a connection on a listener
  ## Returns new connection ID or -1 on error
  
  if listenerId notin nm.connections:
    return -1
  
  let listener = nm.connections[listenerId]
  if not listener.isListening:
    return -1
  
  var clientSocket: Socket
  try:
    listener.socket.accept(clientSocket)
    let id = nm.nextId
    inc nm.nextId
    nm.connections[id] = NiConnection(
      socket: clientSocket,
      isOpen: true,
      isListening: false
    )
    return id
  except:
    return -1

proc niread*(nm: NetworkManager, connId: int, size: int = 4096): string =
  ## Read data from a connection (blocking)
  
  if size <= 0:
    return ""
  
  if connId notin nm.connections:
    return ""
  
  let conn = nm.connections[connId]
  if not conn.isOpen:
    return ""
  
  try:
    var data = newString(size)
    let bytesRead = conn.socket.recv(data, size)
    if bytesRead > 0:
      return data[0..<bytesRead]
    return ""
  except:
    return ""

proc niwrite*(nm: NetworkManager, connId: int, data: string): bool =
  ## Write data to a connection
  
  if connId notin nm.connections:
    return false
  
  let conn = nm.connections[connId]
  if not conn.isOpen:
    return false
  
  try:
    conn.socket.send(data)
    return true
  except:
    return false

proc niclose*(nm: var NetworkManager, connId: int): bool =
  ## Close a connection
  
  if connId notin nm.connections:
    return false
  
  let conn = nm.connections[connId]
  conn.socket.close()
  nm.connections.del(connId)
  return true

proc isConnected*(nm: NetworkManager, connId: int): bool =
  ## Check if connection is open
  if connId notin nm.connections:
    return false
  return nm.connections[connId].isOpen

proc getConnectionCount*(nm: NetworkManager): int =
  ## Get number of active connections
  return nm.connections.len

proc closeAll*(nm: var NetworkManager) =
  ## Close all connections
  for id, conn in nm.connections:
    conn.socket.close()
  nm.connections.clear()
