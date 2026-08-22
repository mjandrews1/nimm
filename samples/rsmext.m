RSMEXT ; RSM-extension sample - runs on RSM, RFC and NimM.
 ; NimM implements the RSM extensions used here: scientific notation
 ; enabled by default, and numeric-before-string subscript collation.
 ;
 ; Run:  rsm -x 'DO ^RSMEXT'      (after importing the routine)
 ;       rfc -x 'DO ^RSMEXT'      (after importing the routine)
 ;       nimm -r rsm_ext.m -x 'DO RSMEXT'
 NEW N,CNT
 ; Exponent notation: uppercase E only; lowercase e stops the number.
 WRITE +"2E3"," ","1E2"+0," ",2E3*2," ",-"2E3"," ",+"1e2",!
 ; Canonical numeric subscripts collate numerically, ahead of strings.
 KILL ^C
 SET ^C(30)=1 SET ^C(2)=1 SET ^C("A")=1 SET ^C(10)=1
 SET N="",CNT=0
 FOR  SET N=$ORDER(^C(N)) QUIT:N=""  DO
 . IF CNT>0 WRITE ","
 . SET CNT=CNT+1
 . WRITE N
 WRITE !
 QUIT
