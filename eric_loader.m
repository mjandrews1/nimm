; eric_loader.m — ERIC Data Loader using nimm file I/O
;
; Loads ERIC thesaurus data into nimm NI_MAP structures
; using channel-based file I/O.
;
; Usage: nimm -r eric_loader.m -e 'DO LOAD "/tmp/eric_staging"'
;
; Data structures:
;   eric_thesaurus — Term name -> metadata
;   eric_bt — Term -> broader terms
;   eric_rt — Term -> related terms
;   eric_synonyms — Synonym -> main term

LOAD ;
    ; Initialize data structures
    WRITE "=== ERIC Data Loader ===",!
    SET TH=$NI_MAP("create","eric_thesaurus")
    SET BT=$NI_MAP("create","eric_bt")
    SET RT=$NI_MAP("create","eric_rt")
    SET SY=$NI_MAP("create","eric_synonyms")
    WRITE "Created data structures.",!
    
    ; Load thesaurus terms
    WRITE !,"--- Loading Thesaurus Terms ---",!
    DO LOADTH
    WRITE "Thesaurus: ",$NI_MAP("len","eric_thesaurus")," terms",!
    
    ; Load broader terms
    WRITE !,"--- Loading Broader Terms ---",!
    DO LOADBT
    WRITE "BT: ",$NI_MAP("len","eric_bt")," links",!
    
    ; Load related terms
    WRITE !,"--- Loading Related Terms ---",!
    DO LOADRT
    WRITE "RT: ",$NI_MAP("len","eric_rt")," links",!
    
    ; Load synonyms
    WRITE !,"--- Loading Synonyms ---",!
    DO LOADSY
    WRITE "Synonyms: ",$NI_MAP("len","eric_synonyms")," links",!
    
    WRITE !,"=== Load Complete ===",!
    QUIT

LOADTH ;
    ; Load thesaurus terms from pipe-delimited file
    OPEN 1:("/tmp/eric_staging/eric_thesaurus.txt":"READ")
    USE 1
    READ HEADER  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET NAME=$PIECE(LINE,"|",1)
    . SET DATA=$PIECE(LINE,"|",2,99)
    . SET X=$NI_MAP("set","eric_thesaurus",NAME,DATA)
    . SET COUNT=COUNT+1
    
    CLOSE 1
    USE 0
    QUIT

LOADBT ;
    ; Load broader term relationships
    OPEN 1:("/tmp/eric_staging/eric_thesaurus_bt.txt":"READ")
    USE 1
    READ HEADER  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET TERM=$PIECE(LINE,"|",1)
    . SET BT=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_bt",TERM,BT)
    . SET COUNT=COUNT+1
    
    CLOSE 1
    USE 0
    QUIT

LOADRT ;
    ; Load related term relationships
    OPEN 1:("/tmp/eric_staging/eric_thesaurus_rt.txt":"READ")
    USE 1
    READ HEADER  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET TERM=$PIECE(LINE,"|",1)
    . SET RT=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_rt",TERM,RT)
    . SET COUNT=COUNT+1
    
    CLOSE 1
    USE 0
    QUIT

LOADSY ;
    ; Load synonym relationships
    OPEN 1:("/tmp/eric_staging/eric_thesaurus_synonyms.txt":"READ")
    USE 1
    READ HEADER  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET SYN=$PIECE(LINE,"|",1)
    . SET MAIN=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_synonyms",SYN,MAIN)
    . SET COUNT=COUNT+1
    
    CLOSE 1
    USE 0
    QUIT

QUERY ;
    ; Query ERIC data
    ; Usage: nimm -r eric_loader.m -e 'DO QUERY "term name"'
    
    SET TERM=%1
    WRITE "=== Querying: ",TERM," ===",!
    
    ; Check thesaurus
    SET DATA=$NI_MAP("get","eric_thesaurus",TERM)
    IF DATA'="" WRITE "Thesaurus: ",DATA,!
    
    ; Check synonyms
    SET SYN=$NI_MAP("get","eric_synonyms",TERM)
    IF SYN'="" WRITE "Synonym of: ",SYN,!
    
    ; Get broader terms
    SET B=$NI_MAP("get","eric_bt",TERM)
    IF B'="" WRITE "Broader: ",B,!
    
    ; Get related terms
    SET R=$NI_MAP("get","eric_rt",TERM)
    IF R'="" WRITE "Related: ",R,!
    
    QUIT
