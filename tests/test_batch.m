; test_batch.m — Test batch mode
;
ENTRY
 WRITE "=== Batch Mode Test ===",!
 SET X = 10
 SET Y = 20
 WRITE "X + Y = ",X + Y,!
 WRITE "=== Success ===",!
 QUIT

ERROR
 WRITE "This is an error",!
 QUIT
