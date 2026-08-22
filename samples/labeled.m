LABELED ; Regression test for #283/#287/#288: labeled block openers,
 ; GOTO walk-forward, and cross-routine DO.
 ;
 ; Run:  nimm -r labeled.m -x 'DO LABELED'
 NEW I,SUM
 SET SUM=0
LOOP FOR I=1:1:5 DO
 . SET SUM=SUM+I
 . WRITE I
 WRITE !,"SUM=",SUM,!
 I SUM=15 WRITE "PASS-LOOP",!
 E  WRITE "FAIL-LOOP: expected 15 got ",SUM,!
 ; GOTO walk-forward test (#287)
 WRITE "A"
 GOTO SKIP
 WRITE "B"
SKIP WRITE "C",!
 ; Cross-routine DO test (#288) — calls HELLO^LABELED below
 D SUB
 QUIT
SUB ; Subroutine in the same routine
 W "PASS-XROUTINE",!
 QUIT
