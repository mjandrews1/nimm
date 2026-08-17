# test_network.nim — Test network commands (NIOPEN/NILISTEN/NIREAD/NIWRITE/NICLOSE)

import ../network

proc main() =
  echo "Testing network commands..."
  
  var nm = newNetworkManager()
  
  # Test NILISTEN
  let listenerId = nm.nilisten(12345)
  assert listenerId > 0, "NILISTEN failed"
  echo "✓ NILISTEN: listening on port 12345 (id=" & $listenerId & ")"
  
  # Test NIOPEN
  let connId = nm.niopen("tcp", "127.0.0.1", 12345)
  assert connId > 0, "NIOPEN failed"
  echo "✓ NIOPEN: connected (id=" & $connId & ")"
  
  # Test NIACCEPT
  let clientId = nm.niaccept(listenerId)
  assert clientId > 0, "NIACCEPT failed"
  echo "✓ NIACCEPT: accepted connection (id=" & $clientId & ")"
  
  # Test NIWRITE
  let writeOk = nm.niwrite(clientId, "hello")
  assert writeOk, "NIWRITE failed"
  echo "✓ NIWRITE: sent 'hello'"
  
  # Test NICLOSE
  discard nm.niclose(connId)
  discard nm.niclose(clientId)
  discard nm.niclose(listenerId)
  echo "✓ NICLOSE: all connections closed"
  
  # Test isConnected
  assert nm.isConnected(connId) == false
  echo "✓ isConnected: false after close"
  
  # Test getConnectionCount
  assert nm.getConnectionCount() == 0
  echo "✓ getConnectionCount: 0"
  
  # Test closeAll
  let l2 = nm.nilisten(12346)
  let c2 = nm.niopen("tcp", "127.0.0.1", 12346)
  let cl2 = nm.niaccept(l2)
  assert nm.getConnectionCount() == 3
  nm.closeAll()
  assert nm.getConnectionCount() == 0
  echo "✓ closeAll: clears all connections"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
