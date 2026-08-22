NIMMEXT ; NimM-extension sample - $NI_* data structures. NimM only.
 ; Tallies a raw array of items into a multiset (bag), reports the
 ; unique items in sorted order with counts, and round-trips JSON.
 ;
 ; Run:  nimm -r nimm_ext.m -x 'DO NIMMEXT'
 NEW I,J,K,U,ITEM,LN,CNT,A,B,T,N
 SET A=$NI_ARRAY("create","nx_arr")
 SET B=$NI_BAG("create","nx_bag")
 SET T=$NI_SORTED("create","nx_srt")
 SET N=$NI_ARRAY("add","nx_arr","apple")
 SET N=$NI_ARRAY("add","nx_arr","banana")
 SET N=$NI_ARRAY("add","nx_arr","apple")
 SET N=$NI_ARRAY("add","nx_arr","cherry")
 SET LN=$NI_ARRAY("len","nx_arr")
 FOR I=0:1:LN-1 DO
 . SET ITEM=$NI_ARRAY("get","nx_arr",I)
 . SET J=$NI_BAG("add","nx_bag",ITEM)
 . IF $NI_SORTED("has","nx_srt",ITEM)=0 DO
 .. SET J=$NI_SORTED("add","nx_srt",ITEM)
 ; sorted unique items with their counts
 SET U=$NI_SORTED("toseq","nx_srt")
 SET CNT=0
 FOR K=1:1:$LENGTH(U,",") DO
 . SET ITEM=$PIECE(U,",",K)
 . IF CNT>0 WRITE ","
 . SET CNT=CNT+1
 . WRITE ITEM,":",$NI_BAG("count","nx_bag",ITEM)
 WRITE !
 WRITE "total=",$NI_BAG("len","nx_bag")," raw=",$NI_ARRAY("len","nx_arr"),!
 WRITE $CASE("b","a":1,"b":2,"c":3)," ",$NI_JSON("stringify",$NI_JSON("parse","[1,2,3]")),!
 QUIT
