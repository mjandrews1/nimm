# test_network_invariants.nim — network connection-table invariants
# (mirrors formal/network.dfy).
#
# Checks the real NetworkManager:
#   - fresh, monotonic connection ids
#   - niclose removes the id (isConnected false afterwards)
#   - getConnectionCount == number of open connections
#   - niread/niclose on a missing/closed id are no-ops ("" / false)
#   - closeAll empties the table
#
# Uses nilisten on an ephemeral port (no external server needed).
#
# Run: nim c -r tests/test_network_invariants.nim

import ../network

proc main() =
  echo "Network connection-table invariant test (mirrors formal/network.dfy)..."

  var nm = newNetworkManager()
  assert nm.getConnectionCount() == 0, "new manager starts empty"

  # A missing id is not connected; read/close on it are safe no-ops.
  assert not nm.isConnected(999999), "missing id must not be connected"
  assert nm.niread(999999) == "", "niread on missing id must return empty"
  assert nm.niclose(999999) == false, "niclose on missing id must return false"

  # Open two listeners; ids must be fresh and monotonic.
  let id1 = nm.nilisten(0)
  let id2 = nm.nilisten(0)
  assert id1 >= 100, "first id must start at nextId (100), got " & $id1
  assert id2 > id1, "ids must be fresh and monotonic, got " & $id1 & " then " & $id2
  assert nm.isConnected(id1), "id1 must be connected after listen"
  assert nm.isConnected(id2), "id2 must be connected after listen"
  assert nm.getConnectionCount() == 2, "count must be 2, got " & $nm.getConnectionCount()

  # Close one; it must be removed.
  assert nm.niclose(id2) == true, "niclose on an open id must return true"
  assert not nm.isConnected(id2), "closed id must not be connected"
  assert nm.niread(id2) == "", "niread on a closed id must return empty"
  assert nm.getConnectionCount() == 1, "count must drop to 1, got " & $nm.getConnectionCount()

  # closeAll empties the table.
  nm.closeAll()
  assert nm.getConnectionCount() == 0, "closeAll must empty the table"
  assert not nm.isConnected(id1), "id1 must not be connected after closeAll"

  echo "  fresh-id / close-removes / count / closeAll all hold"
  echo "Network invariant test passed!"

main()
