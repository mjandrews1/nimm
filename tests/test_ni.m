; test_ni.m — Test NI functions
;
ENTRY
 WRITE "=== NI Functions ===",!
 WRITE "$NI_UUID: ",$NI_UUID(),!
 WRITE "$NI_JSON stringify: ",$NI_JSON("stringify","hello"),!
 WRITE "$NI_JSON parse array: ",$NI_JSON("parse","[1,2,3]"),!
 WRITE "$NI_SLEEP: sleeping 0.1s...",!
 SET T1 = $HOROLOG
 SET X = $NI_SLEEP(0.1)
 WRITE "done",!
 WRITE "=== Done ===",!
 QUIT
