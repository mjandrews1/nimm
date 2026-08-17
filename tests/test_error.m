; test_error.m — Test error handling
;
ENTRY
 WRITE "=== Error Handling Test ===",!
 SET $ETRAP = "WRITE ""Error caught: "",$ECODE,!"
 WRITE "Before error",!
 SET X = $NI_ARRAY("invalid","test")
 WRITE "After error",!
 WRITE "$ECODE: ",$ECODE,!
 WRITE "=== Done ===",!
 QUIT
