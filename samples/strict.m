STRICT ; Strict ANSI/ISO M sample - runs unchanged on RSM, RFC and NimM.
 ; FizzBuzz 1..15 tallied into a global and reported via $ORDER,
 ; followed by a short string-function tour.
 ;
 ; Run:  rsm -x 'DO ^STRICT'      (after importing the routine)
 ;       rfc -x 'DO ^STRICT'      (after importing the routine)
 ;       nimm -r strict.m -x 'DO STRICT'
 NEW I,W,N,CNT,S
 KILL ^BUZZ
 SET CNT=0
 FOR I=1:1:15 DO
 . SET W=""
 . IF I#3=0 SET W="Fizz"
 . IF I#5=0 SET W=W_"Buzz"
 . IF W="" SET W=I
 . SET ^BUZZ(W)=$GET(^BUZZ(W))+1
 . IF CNT>0 WRITE ","
 . SET CNT=CNT+1
 . WRITE W
 WRITE !
 SET N="",CNT=0
 FOR  SET N=$ORDER(^BUZZ(N)) QUIT:N=""  DO
 . IF CNT>0 WRITE ","
 . SET CNT=CNT+1
 . WRITE N,"=",$GET(^BUZZ(N))
 WRITE !
 SET S="ANSI ISO M standard"
 WRITE $EXTRACT(S,1,4),"|",$PIECE(S," ",3),"|",$LENGTH(S),"|",$REVERSE($EXTRACT(S,1,4)),!
 QUIT
