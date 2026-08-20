; eric_load_routine.m — ERIC Data Loader Routine
;
; Usage: nimm -r eric_load_routine.m -e 'DO LOAD'

LOAD ;
    ; Initialize data structures
    WRITE "=== ERIC Data Loader ===",!
    WRITE "Creating data structures...",!
    
    SET TH=$NI_MAP("create","eric_thesaurus")
    SET CI=$NI_MAP("create","eric_citations")
    SET TC=$NI_MAP("create","eric_term_to_cite")
    SET CT=$NI_MAP("create","eric_cite_to_term")
    SET BT=$NI_MAP("create","eric_bt")
    SET RT=$NI_MAP("create","eric_rt")
    SET SY=$NI_MAP("create","eric_synonyms")
    
    WRITE "Data structures created.",!
    
    ; Load thesaurus terms
    WRITE !,"--- Loading Thesaurus Terms ---",!
    SET FILE="/tmp/eric_staging/eric_thesaurus.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET NAME=$PIECE(LINE,"|",1)
    . SET DATA=$PIECE(LINE,"|",2,99)
    . SET X=$NI_MAP("set","eric_thesaurus",NAME,DATA)
    . SET COUNT=COUNT+1
    . IF COUNT#1000=0 WRITE "Loaded ",COUNT," terms...",!
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," thesaurus terms.",!
    
    ; Load citations
    WRITE !,"--- Loading Citations ---",!
    SET FILE="/tmp/eric_staging/eric_citations.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET EDNUM=$PIECE(LINE,"|",1)
    . SET DATA=$PIECE(LINE,"|",2,99)
    . SET X=$NI_MAP("set","eric_citations",EDNUM,DATA)
    . SET COUNT=COUNT+1
    . IF COUNT#1000=0 WRITE "Loaded ",COUNT," citations...",!
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," citations.",!
    
    ; Load broader term relationships
    WRITE !,"--- Loading Broader Terms ---",!
    SET FILE="/tmp/eric_staging/eric_thesaurus_bt.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET TERM=$PIECE(LINE,"|",1)
    . SET BT=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_bt",TERM,BT)
    . SET COUNT=COUNT+1
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," broader term links.",!
    
    ; Load related term relationships
    WRITE !,"--- Loading Related Terms ---",!
    SET FILE="/tmp/eric_staging/eric_thesaurus_rt.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET TERM=$PIECE(LINE,"|",1)
    . SET RT=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_rt",TERM,RT)
    . SET COUNT=COUNT+1
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," related term links.",!
    
    ; Load synonym relationships
    WRITE !,"--- Loading Synonyms ---",!
    SET FILE="/tmp/eric_staging/eric_thesaurus_synonyms.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET SYN=$PIECE(LINE,"|",1)
    . SET MAIN=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_synonyms",SYN,MAIN)
    . SET COUNT=COUNT+1
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," synonym links.",!
    
    ; Load citation-to-subject links
    WRITE !,"--- Building Citation-Subject Links ---",!
    SET FILE="/tmp/eric_staging/eric_citation_subjects.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET EDNUM=$PIECE(LINE,"|",1)
    . SET SUBJECT=$PIECE(LINE,"|",2)
    . SET X=$NI_MAP("set","eric_cite_to_term",EDNUM,SUBJECT)
    . SET X=$NI_MAP("set","eric_term_to_cite",SUBJECT,EDNUM)
    . SET COUNT=COUNT+1
    . IF COUNT#10000=0 WRITE "Built ",COUNT," links...",!
    
    CLOSE FILE
    WRITE "Built ",COUNT," links.",!
    
    ; Summary
    WRITE !,"--- Summary ---",!
    WRITE "Thesaurus terms: ",$NI_MAP("len","eric_thesaurus"),!
    WRITE "Citations: ",$NI_MAP("len","eric_citations"),!
    WRITE "Broader terms: ",$NI_MAP("len","eric_bt"),!
    WRITE "Related terms: ",$NI_MAP("len","eric_rt"),!
    WRITE "Synonyms: ",$NI_MAP("len","eric_synonyms"),!
    WRITE "Term-to-cite links: ",$NI_MAP("len","eric_term_to_cite"),!
    WRITE "Cite-to-term links: ",$NI_MAP("len","eric_cite_to_term"),!
    WRITE !,"=== Load Complete ===",!
    QUIT

QUERY ;
    ; Query ERIC data
    ; Usage: nimm -r eric_load_routine.m -e 'DO QUERY^ERICLOAD "term name"'
    
    SET TERM=%1
    
    WRITE "=== Querying: ",TERM," ===",!
    
    ; Check thesaurus
    SET DATA=$NI_MAP("get","eric_thesaurus",TERM)
    IF DATA'="" DO
    . WRITE "Thesaurus: ",DATA,!
    
    ; Check synonyms
    SET SYN=$NI_MAP("get","eric_synonyms",TERM)
    IF SYN'="" DO
    . WRITE "Synonym of: ",SYN,!
    
    ; Get broader terms
    SET BT=$NI_MAP("get","eric_bt",TERM)
    IF BT'="" DO
    . WRITE "Broader terms: ",BT,!
    
    ; Get related terms
    SET RT=$NI_MAP("get","eric_rt",TERM)
    IF RT'="" DO
    . WRITE "Related terms: ",RT,!
    
    ; Get citations
    SET CITES=$NI_MAP("get","eric_term_to_cite",TERM)
    IF CITES'="" DO
    . WRITE "Citations: ",CITES,!
    
    QUIT
