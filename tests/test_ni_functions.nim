# test_ni_functions.nim — Test $NI functions

import ../ni_functions
import strutils
import times

proc main() =
  echo "Testing $NI functions..."
  
  # Test $NI_UUID
  let uuid1 = niUuid()
  let uuid2 = niUuid()
  assert uuid1.len == 36, "UUID length should be 36, got " & $uuid1.len
  assert uuid1[8] == '-', "UUID should have dash at position 8"
  assert uuid1[13] == '-', "UUID should have dash at position 13"
  assert uuid1[18] == '-', "UUID should have dash at position 18"
  assert uuid1[23] == '-', "UUID should have dash at position 23"
  assert uuid1 != uuid2, "UUIDs should be unique"
  echo "✓ $NI_UUID: " & uuid1
  
  # Test $NI_JSON stringify
  let jsonStr = niJson("stringify", "{\"key\":\"value\"}")
  assert jsonStr.contains("key"), "Should contain key"
  assert jsonStr.contains("value"), "Should contain value"
  echo "✓ $NI_JSON stringify: " & jsonStr
  
  # Test $NI_JSON parse
  let parsed = niJson("parse", "{\"name\":\"Alice\",\"age\":30}")
  assert parsed.contains("Alice"), "Should contain Alice"
  assert parsed.contains("30"), "Should contain 30"
  echo "✓ $NI_JSON parse: " & parsed
  
  # Test $NI_JSON with simple string
  let simpleStr = niJson("stringify", "hello")
  assert simpleStr == "\"hello\"", "Should be quoted string, got " & simpleStr
  echo "✓ $NI_JSON simple stringify: " & simpleStr
  
  # Test $NI_SLEEP (just verify it doesn't crash)
  let t0 = epochTime()
  niSleep(0.1)  # 100ms
  let elapsed = epochTime() - t0
  assert elapsed >= 0.05, "Should sleep at least 50ms"
  echo "✓ $NI_SLEEP: " & $(elapsed * 1000).int & "ms"
  
  # Test $NI_HTTP (will fail gracefully since no server)
  let httpResult = niHttp("GET", "http://localhost:99999/test")
  assert httpResult == "", "Should return empty for unreachable"
  echo "✓ $NI_HTTP: graceful failure"
  
  # Test $NI_SYSTEM
  let hostname = niSystem("hostname")
  assert hostname.len > 0, "hostname should be non-empty"
  echo "✓ $NI_SYSTEM hostname: " & hostname
  let pid = niSystem("pid")
  assert parseInt(pid) > 0, "pid should be positive"
  echo "✓ $NI_SYSTEM pid: " & pid
  let cwd = niSystem("cwd")
  assert cwd.len > 0, "cwd should be non-empty"
  echo "✓ $NI_SYSTEM cwd: " & cwd
  let arch = niSystem("arch")
  assert arch.len > 0, "arch should be non-empty"
  echo "✓ $NI_SYSTEM arch: " & arch
  let osName = niSystem("os")
  assert osName.len > 0, "os should be non-empty"
  echo "✓ $NI_SYSTEM os: " & osName
  let unknown = niSystem("does_not_exist")
  assert unknown == "", "unknown subscript should be empty"
  echo "✓ $NI_SYSTEM unknown: empty"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
