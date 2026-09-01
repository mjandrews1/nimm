BM25IDX ; entry-term dictionary lookup for FST (#359)
 ; The BM25 index build (BUILDMESH/BUILDCAT/BUILDSER/BUILDPUB/COMMON) has been
 ; superseded by global_bm25.nim buildIndex (run via future_search_tool/src/
 ; build_bm25.nim). This routine retains only DICT, the entry-term expansion
 ; over ^MESHTERM (the query-time dictionary, distinct from index building).
 ; Globals:
 ;   ^MESHTERM(term,ui)="1" for exact descriptor name, "0" for entry synonym.
 ; Usage: nimm -r bm25idx.m -d db.lmdb -e 'DO DICT^BM25IDX'
 QUIT
 ;
DICT ; entry-term dictionary lookup: reads ^TMP("BM25","terms"); WRITEs UIs
 ; ^MESHTERM(term,ui)="1" for exact descriptor name, "0" for entry synonym.
 ; Emits exact-name matches first, then synonym matches.
 SET Q=$GET(^TMP("BM25","terms"))
 SET Q=$TRANSLATE(Q,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz")
 SET UI=""
 FOR  SET UI=$ORDER(^MESHTERM(Q,UI)) QUIT:UI=""  DO
 . IF $GET(^MESHTERM(Q,UI))="1" WRITE UI,!
 SET UI=""
 FOR  SET UI=$ORDER(^MESHTERM(Q,UI)) QUIT:UI=""  DO
 . IF $GET(^MESHTERM(Q,UI))'="1" WRITE UI,!
 QUIT
