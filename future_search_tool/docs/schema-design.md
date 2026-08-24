# FST Schema Design — NLM Data

## Data Model

### Record Types

| Type | Source | Identifier | Example |
|---|---|---|---|
| MeSH Descriptor | desc2026.xml | DescriptorUI | D000001 |
| MeSH Qualifier | qual2026.xml | QualifierUI | Q000001 |
| MeSH Supplement | supp2026 | SCR_ID | C000001 |
| CatLine (CatPlus) | catplusbase*.marcxml.xml | NLMID | 1234567 |
| SerLine | serfilebase.marcxml.xml | NLMID | 7654321 |
| PubMed Citation | pubmed*.xml | PMID | 12345678 |

### Global Schema

```
^MESH(descUI, field) = value
  "name" = "Hypertension"
  "scopeNote" = "Persistently high arterial blood pressure..."
  "treeNumber" = "C14.907.489"
  "qualifier", qualUI = "Q000276"  ; related qualifier

^QUAL(qualUI, field) = value
  "name" = "drug therapy"
  "abbreviation" = "DT"

^SUPPLEMENT(scrID, field) = value
  "name" = "COVID-19"
  "mappedTo" = "D000001"  ; mapped descriptor

^CATLINE(nlmID, field) = value
  "title" = "Journal of hypertension"
  "issn" = "0263-6352"
  "mesh", descUI = "D000001"  ; subject heading link
  "publisher" = "Lippincott Williams & Wilkins"

^SERLINE(nlmID, field) = value
  "title" = "Journal of hypertension"
  "issn" = "0263-6352"
  "holdings" = "v1 (1983)-"
  "catlineID" = "1234567"  ; link to CatLine

^PUBMED(pmid, field) = value
  "title" = "Hypertension treatment guidelines"
  "authors" = "Smith J, Jones A"
  "journal" = "J Hypertens"
  "mesh", descUI = "D000001"  ; MeSH term link
  "catlineID" = "1234567"  ; journal link

^LINK(fromType, fromId, toType, toId) = relationshipType
  "MESH", "D000001", "CATLINE", "1234567" = "subject"
  "MESH", "D000001", "PUBMED", "12345678" = "mesh_term"
  "CATLINE", "1234567", "SERLINE", "7654321" = "serial"
  "PUBMED", "12345678", "CATLINE", "1234567" = "journal"
```

### Upsert Semantics

Each record type has a unique identifier. On import:
- If the record exists (same ID), update all fields in place
- If the record is new, insert it
- Links are deduplicated (same from→to = same relationship)

| Record Type | Unique ID | Upsert Key |
|---|---|---|
| MeSH Descriptor | DescriptorUI | ^MESH(descUI) |
| MeSH Qualifier | QualifierUI | ^QUAL(qualUI) |
| MeSH Supplement | SCR_ID | ^SUPPLEMENT(scrID) |
| CatLine | NLMID | ^CATLINE(nlmID) |
| SerLine | NLMID | ^SERLINE(nlmID) |
| PubMed Citation | PMID | ^PUBMED(pmid) |
| Link | from+to pair | ^LINK(fromType,fromId,toType,toId) |

**Implementation:** M's natural upsert — `SET ^MESH("D000001","name")="Hypertension"` overwrites if exists, creates if not. No special logic needed.

### Query Patterns

| Query | Path | Example |
|---|---|---|
| Find MeSH by name | ^MESH by "name" field | "hypertension" → D000001 |
| Find citations by MeSH | ^PUBMED by "mesh" subscript | D000001 → all PMIDs |
| Find journals by MeSH | ^CATLINE by "mesh" subscript | D000001 → all NLMIDs |
| Find serial holdings | ^SERLINE by "catlineID" | NLMID → holdings |
| Find related records | ^LINK by fromType+fromId | D000001 → all linked records |

### Index Strategy

**BM25 Index:**
- Index all text fields (name, title, scopeNote, authors, etc.)
- Separate indexes per record type (for faster search)
- Combined index for cross-type search

**HNSW Index (future):**
- Embed text fields with a local model
- Store vectors in ^VECTOR(recType, recId)
- Search by similarity

### Import Pipeline

```
NLM XML/JSON files
  → Record Loader (parse XML/JSON)
    → LMDB globals (^MESH, ^CATLINE, ^SERLINE, ^PUBMED)
    → Link builder (^LINK)
    → BM25 indexer (keyword search)
    → HNSW indexer (vector search, future)
```

### Value Proposition

**Before FST:**
- MeSH data: XML files, hard to search
- CatLine/SerLine: MARC XML, requires specialized tools
- PubMed: XML dumps, no unified search
- Relationships: implicit in data, not explicit

**After FST:**
- All data in one LMDB database
- Unified keyword search across all record types
- Explicit relationships via ^LINK
- Accessible from M code, MCP tools, or CLI
- No specialized tools needed

### Example Queries

```
; Find MeSH descriptor for "hypertension"
W $NI_SEARCH("hypertension", "MESH")

; Find all PubMed citations about hypertension
W $NI_SEARCH("hypertension", "PUBMED")

; Find journals that publish about hypertension
W $NI_SEARCH("hypertension", "CATLINE")

; Find all records linked to MeSH D000001
W $NI_LINKS("MESH", "D000001")
```
