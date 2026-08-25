#!/bin/bash
# fst_load_m.sh — Load MeSH XML using NimM's M string parser
# Parses XML with $FIND/$EXTRACT/$PIECE, writes to LMDB via nimm
# Usage: ./fst_load_m.sh <db_path> <xml_path>

set -e

DB="$1"
XML="$2"

if [ -z "$DB" ] || [ -z "$XML" ]; then
    echo "Usage: fst_load_m.sh <db_path> <xml_path>"
    exit 1
fi

echo "Loading MeSH from $XML into $DB"

# Parse XML using M string functions
./nimm -d "$DB" -x "
K ^MESH,^FST,^TMP
S ^FST(\"status\")=\"loading\"
O 1:(\"$XML\":\"R\")
S count=0
S ui=\"\",name=\"\",scope=\"\"
S inUI=0,inName=0,inScope=0
F  U 1 R line Q:\$ZEOF  U 0 D
. ; DescriptorUI
. I line[\"<DescriptorUI>\" S inUI=1,ui=\"\"
. I inUI D
. . S chunk=\$TR(\$P(\$P(line,\"</DescriptorUI>\",1),\"<DescriptorUI>\",2),\" \",\"\")
. . I chunk]\"\" S ui=ui_chunk
. . I line[\"</DescriptorUI>\" S inUI=0
. ; DescriptorName/String
. I line[\"<String>\",inName=0 S inName=1,name=\"\"
. I inName D
. . S chunk=\$P(\$P(line,\"</String>\",1),\"<String>\",2)
. . I chunk]\"\" S name=name_chunk
. . I line[\"</String>\" S inName=0
. ; ScopeNote
. I line[\"<ScopeNote>\" S inScope=1,scope=\"\"
. I inScope D
. . S chunk=\$P(\$P(line,\"</ScopeNote>\",1),\"<ScopeNote>\",2)
. . I chunk]\"\" S scope=scope_chunk
. . I line[\"</ScopeNote>\" S inScope=0
. ; TreeNumber
. I line[\"<TreeNumber>\" D
. . S tree=\$P(\$P(line,\"</TreeNumber>\",1),\"<TreeNumber>\",2)
. . I tree]\"\" S ^TMP(\"tree\",tree)=\"1\"
. ; QualifierUI
. I line[\"<QualifierUI>\" D
. . S qual=\$P(\$P(line,\"</QualifierUI>\",1),\"<QualifierUI>\",2)
. . I qual]\"\" S ^TMP(\"qual\",qual)=\"1\"
. ; End of DescriptorRecord
. I line[\"</DescriptorRecord>\" D
. . I ui]\"\" D
. . . S ^MESH(ui,\"name\")=name
. . . I scope]\"\" S ^MESH(ui,\"scopeNote\")=scope
. . . S t=\"\"
. . . F  S t=\$O(^TMP(\"tree\",t)) Q:t=\"\"  S ^MESH(ui,\"treeNumber\",t)=\"1\"
. . . S q=\"\"
. . . F  S q=\$O(^TMP(\"qual\",q)) Q:q=\"\"  S ^MESH(ui,\"qualifier\",q)=\"1\"
. . . S count=count+1
. . . I count#500=0 U 0 W \"  Loaded \",count,\" descriptors\",! U 1
. . . K ^TMP
. . S ui=\"\",name=\"\",scope=\"\"
C 1
U 0
W \"Loaded \",count,\" descriptors\",!
S ^FST(\"records\")=count
S ^FST(\"status\")=\"loaded\"
" 2>&1

echo "Done!"
