LABELED ; Regression test for #283/#287: labeled block openers + GOTO walk-forward.
 ; A label sharing its line with a block opener (FOR/IF/DO) must
 ; execute the block, not silently skip it (#283). GOTO must continue
 ; forward from the target label until QUIT (#287).
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
 QUIT
