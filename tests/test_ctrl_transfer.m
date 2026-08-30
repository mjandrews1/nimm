; test_ctrl_transfer.m — control-transfer commands (DO/GOTO/QUIT) for
; test_bytecode_conformance.sh (command_bisim.dfy runtime mirror).
GO
 SET X=1
 GOTO SKIP
 SET X=99
SKIP
 WRITE X,!
 QUIT
DOIT
 SET X=5
 DO ADDONE
 WRITE X,!
 QUIT
ADDONE
 SET X=X+1
 QUIT
