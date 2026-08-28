BM25IDX ; BM25 index builder for FST (#359)
 ; Fully parameterless (#370 workaround): select source via entry point;
 ; config inlined per entry. Batching via VIEW BATCH* (#371 workaround).
 ; Globals:
 ;   ^BM25(term,type,id)=tf   ^BM25DF(term,type)=df
 ;   ^BM25LEN(type,id)=len    ^BM25META(type,"N"/"avgdl")
 ; Query: SET ^TMP("BM25","type")=".." ,^TMP("BM25","id")=".."
 ;        ,^TMP("BM25","terms")=".."  then W $$SCORE^BM25IDX
 ; Usage: nimm -r bm25idx.m -d db.lmdb -e 'DO BUILDMESH^BM25IDX'
 QUIT
 ;
BUILDMESH ;
 SET ^TMP("BM25CFG","src")="MESH"
 SET ^TMP("BM25CFG","glob")="^MESH"
 SET ^TMP("BM25CFG","flist")="name^scopeNote"
 DO COMMON
 QUIT
 ;
BUILDCAT ;
 SET ^TMP("BM25CFG","src")="CATLINE"
 SET ^TMP("BM25CFG","glob")="^CATLINE"
 SET ^TMP("BM25CFG","flist")="title"
 DO COMMON
 QUIT
 ;
BUILDSER ;
 SET ^TMP("BM25CFG","src")="SERLINE"
 SET ^TMP("BM25CFG","glob")="^SERLINE"
 SET ^TMP("BM25CFG","flist")="title"
 DO COMMON
 QUIT
 ;
BUILDPUB ;
 SET ^TMP("BM25CFG","src")="PUBMED"
 SET ^TMP("BM25CFG","glob")="^PUBMED"
 SET ^TMP("BM25CFG","flist")="title^abstract^journal"
 DO COMMON
 QUIT
 ;
ALL ;
 DO BUILDMESH
 DO BUILDCAT
 DO BUILDSER
 DO BUILDPUB
 QUIT
 ;
COMMON ; main build
 ; No ^TMP("BM25L") accumulator - KILL doesn't work on LMDB globals.
 ; Instead write ^BM25(tf) directly and check first-occurrence for DF.
 SET SRC=$GET(^TMP("BM25CFG","src"))
 SET GLOB=$GET(^TMP("BM25CFG","glob"))
 SET FLIST=$GET(^TMP("BM25CFG","flist"))
 SET P=$CHAR(34)_$CHAR(126)_$CHAR(33)_$CHAR(64)_$CHAR(35)
 SET P=P_$CHAR(36)_$CHAR(37)_$CHAR(94)_$CHAR(38)_$CHAR(42)
 SET P=P_$CHAR(40)_$CHAR(41)_$CHAR(95)_$CHAR(45)_$CHAR(43)
 SET P=P_$CHAR(61)_$CHAR(91)_$CHAR(93)_$CHAR(123)_$CHAR(125)
 SET P=P_$CHAR(124)_$CHAR(59)_$CHAR(59)_$CHAR(58)_$CHAR(39)
 SET P=P_$CHAR(34)_$CHAR(44)_$CHAR(46)_$CHAR(60)_$CHAR(62)
 SET P=P_$CHAR(47)_$CHAR(63)_$CHAR(32)_$CHAR(96)_$CHAR(9)
 SET P=P_$CHAR(92)
 SET SP=$JUSTIFY("",$LENGTH(P))
 VIEW "BATCHON"
 SET ID="",CNT=0
 FOR  SET ID=$ORDER(@GLOB@(ID)) QUIT:ID=""  D
 . IF '$DATA(^BM25LEN(SRC,ID)) D
 .. SET DL=0
 .. SET FI=1
 .. FOR  SET FNAME=$PIECE(FLIST,"^",FI) QUIT:FNAME=""  D
 ... SET TXT=$GET(@GLOB@(ID,FNAME))
 ... SET TXT=$TR(TXT,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz")
 ... SET TXT=$TRANSLATE(TXT,P,SP)
 ... SET NP=$LENGTH(TXT," ")
 ... FOR TI=1:1:NP D
 .... SET W=$PIECE(TXT," ",TI)
  .... IF W'="" D
  ..... SET OLD=+$GET(^BM25(W,SRC,ID))
  ..... SET ^BM25(W,SRC,ID)=OLD+1
  ..... IF OLD=0 SET ^BM25DF(W,SRC)=$GET(^BM25DF(W,SRC))+1
  ..... SET DL=DL+1
 ... SET FI=FI+1
 .. IF DL>0 D
 ... SET ^BM25LEN(SRC,ID)=DL
 ... SET CNT=CNT+1
 ... IF CNT#500=0 D
 .... WRITE "  [",SRC,"] ",CNT," docs @",$HOROLOG,!
 VIEW "BATCHCOMMIT"
 SET SUM=0 SET N=0 SET ID=""
 FOR  SET ID=$ORDER(^BM25LEN(SRC,ID)) QUIT:ID=""  SET SUM=SUM+^BM25LEN(SRC,ID),N=N+1
 SET AVG=$SELECT(N>0:SUM/N,1:0)
 SET ^BM25META(SRC,"N")=N
 SET ^BM25META(SRC,"avgdl")=$JUSTIFY(AVG,0,2)
 WRITE "BM25IDX DONE ",SRC," docs=",N," tokens=",SUM," avgdl=",$JUSTIFY(AVG,0,2),!
 QUIT
 ;
SCORE ; reads ^TMP("BM25","type"/"id"/"terms"); writes BM25 score
 ; NEW removed: hangs in nimm when called via DO (#scoping bug)
 ; IF>DO block flattened: nested . . hangs cross-routine (#nimm scoping)
 SET TYPE=$GET(^TMP("BM25","type"))
 SET QID=$GET(^TMP("BM25","id"))
 SET QTERMS=$GET(^TMP("BM25","terms"))
 SET K1=1.5 SET B=0.75
 SET NN=+$GET(^BM25META(TYPE,"N"))
 SET AVG=+$GET(^BM25META(TYPE,"avgdl"))
 SET SC=0 SET TI=1
 FOR  SET T=$PIECE(QTERMS," ",TI) QUIT:T=""  D
 . SET TF=+$GET(^BM25(T,TYPE,QID))
 . IF TF>0 SET DF=+$GET(^BM25DF(T,TYPE)),IDF=$ZLN((NN-DF+0.5)/(DF+0.5)+1),DEN=TF+(K1*(1-B+(B*(+$GET(^BM25LEN(TYPE,QID))/AVG)))),SC=SC+IDF*TF/DEN*(K1+1)
 . SET TI=TI+1
 WRITE SC
 QUIT
 ;
SEARCH ; top-K retrieval: reads ^TMP("BM25","type"/"terms"/"k"); WRITEs "id<TAB>score"
 ; Tokenizes the query identically to COMMON, scores every doc, ranks by
 ; descending score via ^TMP("RANK", -score, id), and prints top-K.
 SET TYPE=$GET(^TMP("BM25","type"))
 SET Q=$GET(^TMP("BM25","terms"))
 SET K=$GET(^TMP("BM25","k")) SET:K="" K=10
 SET P=$CHAR(34)_$CHAR(126)_$CHAR(33)_$CHAR(64)_$CHAR(35)
 SET P=P_$CHAR(36)_$CHAR(37)_$CHAR(94)_$CHAR(38)_$CHAR(42)
 SET P=P_$CHAR(40)_$CHAR(41)_$CHAR(95)_$CHAR(45)_$CHAR(43)
 SET P=P_$CHAR(61)_$CHAR(91)_$CHAR(93)_$CHAR(123)_$CHAR(125)
 SET P=P_$CHAR(124)_$CHAR(59)_$CHAR(59)_$CHAR(58)_$CHAR(39)
 SET P=P_$CHAR(34)_$CHAR(44)_$CHAR(46)_$CHAR(60)_$CHAR(62)
 SET P=P_$CHAR(47)_$CHAR(63)_$CHAR(32)_$CHAR(96)_$CHAR(9)
 SET P=P_$CHAR(92)
 SET SP=$JUSTIFY("",$LENGTH(P))
 SET Q=$TRANSLATE(Q,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz")
 SET Q=$TRANSLATE(Q,P,SP)
 SET K1=1.5 SET B=0.75
 SET NN=+$GET(^BM25META(TYPE,"N"))
 SET AVG=+$GET(^BM25META(TYPE,"avgdl"))
 KILL ^TMP("RANK")
 VIEW "BATCHON"
 SET ID=""
 FOR  SET ID=$ORDER(^BM25LEN(TYPE,ID)) QUIT:ID=""  DO
 . SET SC=0 SET TI=1
 . FOR  SET T=$PIECE(Q," ",TI) QUIT:T=""  DO
 .. SET TF=+$GET(^BM25(T,TYPE,ID))
 .. IF TF>0 SET DF=+$GET(^BM25DF(T,TYPE)),IDF=$ZLN((NN-DF+0.5)/(DF+0.5)+1),DEN=TF+(K1*(1-B+(B*(+$GET(^BM25LEN(TYPE,ID))/AVG)))),SC=SC+IDF*TF/DEN*(K1+1)
 .. SET TI=TI+1
 . IF SC>0 SET ^TMP("RANK",-SC,ID)=""
 VIEW "BATCHCOMMIT"
 ; read back in ascending -score (= descending score); dump all, caller caps K
 SET SCK=""
 FOR  SET SCK=$ORDER(^TMP("RANK",SCK)) QUIT:SCK=""  DO
 . SET ID2=""
 . FOR  SET ID2=$ORDER(^TMP("RANK",SCK,ID2)) QUIT:ID2=""  DO
 .. WRITE ID2,$CHAR(9),-SCK,!
 QUIT
