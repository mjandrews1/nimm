#!/usr/bin/env nimm
; eric_loader.m — Load ERIC data into nimm NI_MAP structures
;
; Usage: nimm -x 'DO LOAD^ERICLOADER "/path/to/eric_staging"'
;
; Data structures:
;   eric_thesaurus — Term name → "recType|scopeNote|groupCode|addDate"
;   eric_citations — ED number → "title|creator|date|description"
;   eric_term_to_cite — Term name → "ED1,ED2,..."
;   eric_cite_to_term — ED number → "term1,term2,..."
;   eric_bt — Term name → "broaderTerm1,broaderTerm2,..."
;   eric_rt — Term name → "relatedTerm1,relatedTerm2,..."
;   eric_synonyms — Synonym → "mainTerm"

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
    WRITE "Loading data from: ",%1,!
    
    ; Load thesaurus
    DO LOADTH^ERICLOADER(%1)
    
    ; Load citations
    DO LOADCI^ERICLOADER(%1)
    
    ; Build link tables
    DO BUILDLINKS^ERICLOADER(%1)
    
    WRITE "=== Load Complete ===",!
    QUIT

LOADTH(DIR) ;
    ; Load ERIC thesaurus from pipe-delimited file
    WRITE !,"--- Loading Thesaurus ---",!
    
    SET FILE=DIR_"/eric_staging/eric_thesaurus.txt"
    OPEN FILE:(READONLY)
    USE FILE
    
    ; Skip header
    READ LINE
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET NAME=$PIECE(LINE,"|",1)
    . SET RECTYPE=$PIECE(LINE,"|",2)
    . SET SCOPENOTE=$PIECE(LINE,"|",3)
    . SET GROUPCODE=$PIECE(LINE,"|",4)
    . SET ADDDATE=$PIECE(LINE,"|",5)
    . 
    . ; Store in thesaurus map
    . SET DATA=RECTYPE_"|"_SCOPENOTE_"|"_GROUPCODE_"|"_ADDDATE
    . SET X=$NI_MAP("set","eric_thesaurus",NAME,DATA)
    . 
    . SET COUNT=COUNT+1
    . IF COUNT#1000=0 WRITE "Loaded ",COUNT," terms...",!
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," thesaurus terms.",!
    QUIT

LOADCI(DIR) ;
    ; Load ERIC citations from pipe-delimited file
    WRITE !,"--- Loading Citations ---",!
    
    SET FILE=DIR_"/eric_staging/eric_citations.txt"
    OPEN FILE:(READONLY)
    USE FILE
    
    ; Skip header
    READ LINE
    
    SET COUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET EDNUM=$PIECE(LINE,"|",1)
    . SET TITLE=$PIECE(LINE,"|",2)
    . SET CREATOR=$PIECE(LINE,"|",3)
    . SET DATE=$PIECE(LINE,"|",4)
    . SET DESC=$PIECE(LINE,"|",5)
    . 
    . ; Store in citations map
    . SET DATA=TITLE_"|"_CREATOR_"|"_DATE_"|"_DESC
    . SET X=$NI_MAP("set","eric_citations",EDNUM,DATA)
    . 
    . SET COUNT=COUNT+1
    . IF COUNT#1000=0 WRITE "Loaded ",COUNT," citations...",!
    
    CLOSE FILE
    WRITE "Loaded ",COUNT," citations.",!
    QUIT

BUILDLINKS(DIR) ;
    ; Build link tables from subject data
    WRITE !,"--- Building Link Tables ---",!
    
    ; Load citation-to-subject links
    SET FILE=DIR_"/eric_staging/eric_citation_subjects.txt"
    OPEN FILE:(READONLY)
    USE FILE
    
    ; Skip header
    READ LINE
    
    SET LINKCOUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET EDNUM=$PIECE(LINE,"|",1)
    . SET SUBJECT=$PIECE(LINE,"|",2)
    . 
    . ; Update citation-to-term link
    . SET OLDCT=$NI_MAP("get","eric_cite_to_term",EDNUM)
    . IF OLDCT="" SET NEWCT=SUBJECT
    . ELSE  SET NEWCT=OLDCT_","_SUBJECT
    . SET X=$NI_MAP("set","eric_cite_to_term",EDNUM,NEWCT)
    . 
    . ; Update term-to-citation link
    . SET OLDTC=$NI_MAP("get","eric_term_to_cite",SUBJECT)
    . IF OLDTC="" SET NEWTC=EDNUM
    . ELSE  SET NEWTC=OLDTC_","_EDNUM
    . SET X=$NI_MAP("set","eric_term_to_cite",SUBJECT,NEWTC)
    . 
    . SET LINKCOUNT=LINKCOUNT+1
    . IF LINKCOUNT#1000=0 WRITE "Built ",LINKCOUNT," links...",!
    
    CLOSE FILE
    WRITE "Built ",LINKCOUNT," links.",!
    
    ; Load broader term relationships
    WRITE !,"--- Loading Broader Terms ---",!
    SET FILE=DIR_"/eric_staging/eric_thesaurus_bt.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET BTCOUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET TERM=$PIECE(LINE,"|",1)
    . SET BT=$PIECE(LINE,"|",2)
    . 
    . SET OLDBT=$NI_MAP("get","eric_bt",TERM)
    . IF OLDBT="" SET NEWBT=BT
    . ELSE  SET NEWBT=OLDBT_","_BT
    . SET X=$NI_MAP("set","eric_bt",TERM,NEWBT)
    . 
    . SET BTCOUNT=BTCOUNT+1
    
    CLOSE FILE
    WRITE "Loaded ",BTCOUNT," broader term links.",!
    
    ; Load related term relationships
    WRITE !,"--- Loading Related Terms ---",!
    SET FILE=DIR_"/eric_staging/eric_thesaurus_rt.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET RTCOUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET TERM=$PIECE(LINE,"|",1)
    . SET RT=$PIECE(LINE,"|",2)
    . 
    . SET OLDRT=$NI_MAP("get","eric_rt",TERM)
    . IF OLDRT="" SET NEWRT=RT
    . ELSE  SET NEWRT=OLDRT_","_RT
    . SET X=$NI_MAP("set","eric_rt",TERM,NEWRT)
    . 
    . SET RTCOUNT=RTCOUNT+1
    
    CLOSE FILE
    WRITE "Loaded ",RTCOUNT," related term links.",!
    
    ; Load synonym relationships
    WRITE !,"--- Loading Synonyms ---",!
    SET FILE=DIR_"/eric_staging/eric_thesaurus_synonyms.txt"
    OPEN FILE:(READONLY)
    USE FILE
    READ LINE  ; Skip header
    
    SET SYNCOUNT=0
    FOR  READ LINE QUIT:$ZEOF  DO
    . SET SYN=$PIECE(LINE,"|",1)
    . SET MAIN=$PIECE(LINE,"|",2)
    . 
    . SET X=$NI_MAP("set","eric_synonyms",SYN,MAIN)
    . 
    . SET SYNCOUNT=SYNCOUNT+1
    
    CLOSE FILE
    WRITE "Loaded ",SYNCOUNT," synonym links.",!
    
    QUIT

QUERY ;
    ; Query ERIC data
    ; Usage: nimm -x 'DO QUERY^ERICLOADER "term name"'
    
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
