# test_unicode.nim — Test Unicode UTF-8 support

import ../unicode_utils

proc main() =
  echo "Testing Unicode UTF-8 support..."
  
  # Test isValidUtf8
  assert isValidUtf8("hello") == true
  assert isValidUtf8("café") == true
  assert isValidUtf8("日本語") == true
  assert isValidUtf8("emoji: 😀") == true
  echo "✓ isValidUtf8"
  
  # Test utf8Len
  assert utf8Len("hello") == 5
  assert utf8Len("café") == 4
  assert utf8Len("日本語") == 3
  assert utf8Len("😀") == 1
  echo "✓ utf8Len"
  
  # Test utf8Substring
  assert utf8Substring("hello world", 0, 5) == "hello"
  assert utf8Substring("café au lait", 0, 4) == "café"
  assert utf8Substring("日本語テスト", 0, 3) == "日本語"
  assert utf8Substring("hello", 2, 3) == "llo"
  echo "✓ utf8Substring"
  
  # Test utf8Reverse
  assert utf8Reverse("hello") == "olleh"
  assert utf8Reverse("café") == "éfac"
  assert utf8Reverse("日本語") == "語本日"
  echo "✓ utf8Reverse"
  
  # Test utf8ToUpper (ASCII only)
  assert utf8ToUpper("hello") == "HELLO"
  assert utf8ToUpper("world") == "WORLD"
  echo "✓ utf8ToUpper"
  
  # Test utf8ToLower (ASCII only)
  assert utf8ToLower("HELLO") == "hello"
  assert utf8ToLower("WORLD") == "world"
  echo "✓ utf8ToLower"
  
  # Test utf8IsAlpha
  assert utf8IsAlpha("hello", 0) == true
  assert utf8IsAlpha("123", 0) == false
  assert utf8IsAlpha("café", 0) == true
  echo "✓ utf8IsAlpha"
  
  # Test utf8IsDigit
  assert utf8IsDigit("123", 0) == true
  assert utf8IsDigit("hello", 0) == false
  echo "✓ utf8IsDigit"
  
  # Test utf8IsAlphaNum
  assert utf8IsAlphaNum("h", 0) == true
  assert utf8IsAlphaNum("1", 0) == true
  assert utf8IsAlphaNum("!", 0) == false
  echo "✓ utf8IsAlphaNum"
  
  # Test utf8CodePointAt
  assert utf8CodePointAt("A", 0) == 65
  assert utf8CodePointAt("a", 0) == 97
  assert utf8CodePointAt("日本語", 0) == 0x65E5  # 日
  echo "✓ utf8CodePointAt"
  
  # Test utf8FromCodePoint
  assert utf8FromCodePoint(65) == "A"
  assert utf8FromCodePoint(0x65E5) == "日"
  echo "✓ utf8FromCodePoint"
  
  echo "\nAll tests passed!"

when isMainModule:
  main()
