; test_special.m — Test special variables
;
ENTRY
 WRITE "=== Special Variables ===",!
 WRITE "$HOROLOG: ",$HOROLOG,!
 WRITE "$JOB: ",$JOB,!
 WRITE "$SYSTEM: ",$SYSTEM,!
 WRITE "$IO: ",$IO,!
 WRITE "$PRINCIPAL: ",$PRINCIPAL,!
 WRITE "$STORAGE: ",$STORAGE,!
 WRITE "$STACK: ",$STACK,!
 SET $X = 10
 SET $Y = 20
 WRITE "$X: ",$X,!
 WRITE "$Y: ",$Y,!
 WRITE "$TEST: ",$TEST,!
 WRITE "=== Done ===",!
 QUIT
