; test_functions.m — Test intrinsic functions
;
ENTRY
 WRITE "=== Intrinsic Functions ===",!
 WRITE "$ASCII: ",$ASCII("A"),!
 WRITE "$CHAR: ",$CHAR(72,101,108,108,111),!
 WRITE "$DATA (undef): ",$DATA(UNDEF),!
 SET X = 42
 WRITE "$DATA (def): ",$DATA(X),!
 WRITE "$EXTRACT: ",$EXTRACT("Hello",2,4),!
 WRITE "$FIND: ",$FIND("Hello","l"),!
 WRITE "$GET (undef): ",$GET(UNDEF,"default"),!
 WRITE "$GET (def): ",$GET(X),!
 SET CTR = 0
 WRITE "$INCR: ",$INCREMENT(CTR,5),!
 WRITE "CTR: ",CTR,!
 WRITE "$JUSTIFY: ",$JUSTIFY(42,10),!
 WRITE "$LENGTH: ",$LENGTH("Hello"),!
 WRITE "$PIECE: ",$PIECE("a^b^c","^",2),!
 WRITE "$RANDOM: ",$RANDOM(100),!
 WRITE "$REVERSE: ",$REVERSE("Hello"),!
 WRITE "$SELECT: ",$SELECT(0:"no",1:"yes"),!
 WRITE "$TRANSLATE: ",$TRANSLATE("Hello","el","EL"),!
 WRITE "$CASE: ",$CASE(2,1:"one",2:"two",3:"three",:other),!
 WRITE "$FNUMBER: ",$FNUMBER(1234.567,",",2),!
 WRITE "=== Done ===",!
 QUIT
