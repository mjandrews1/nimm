LABELED ; Regression test for #283: labeled lines that open dot-blocks.
 ; A label sharing its line with a block opener (FOR/IF/DO) must
 ; execute the block, not silently skip it.
 ;
 ; Run:  nimm -r labeled.m -x 'DO LABELED'
 NEW I,SUM
 SET SUM=0
LOOP FOR I=1:1:5 DO
 . SET SUM=SUM+I
 . WRITE I
 WRITE !,"SUM=",SUM,!
 I SUM=15 WRITE "PASS",!
 E  WRITE "FAIL: expected 15 got ",SUM,!
 QUIT
