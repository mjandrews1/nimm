# FST Implementation — Algorithms + Data Structures + Data Sources

## Core Principle

Each data source has a natural representation in M's hierarchical globals.
Relationships between sources are explicit links. Search algorithms (BM25, HNSW)
operate over the stored data. The result is a unified, searchable knowledge graph.

## Data Source → Global Schema Mapping

### Primary Records (NLM)

| Source | Global | Key | Fields |
|---|---|---|---|
| MeSH Descriptors | ^MESH(descUI) | D000001 | name, scopeNote, treeNumber |
| MeSH Qualifiers | ^QUAL(qualUI) | Q000001 | name, abbreviation |
| MeSH Supplements | ^SUPPLEMENT(scrID) | C000001 | name, mappedTo |
| CatLine | ^CATLINE(nlmID) | 1234567 | title, issn, publisher |
| SerLine | ^SERLINE(nlmID) | 7654321 | title, issn, holdings |
| PubMed | ^PUBMED(pmid) | 12345678 | title, authors, journal, abstract |

### Supplementary Records

| Source | Global | Key | Fields |
|---|---|---|---|
| Crossref | ^CROSSREF(doi) | 10.1234/... | title, authors, citations |
| ORCID | ^ORCID(orcid) | 0000-0001-... | name, institution, papers |
| ROR | ^ROR(rorID) | 03yrm5j26 | name, country, type |
| ClinicalTrials | ^TRIAL(nctId) | NCT12345678 | title, status, conditions |
| DrugBank | ^DRUG(drugId) | DB00001 | name, description, interactions |
| ICD-10 | ^ICD(code) | I10 | name, description |
| SNOMED CT | ^SNOMED(sctId) | 38341003 | name, description |
| LOINC | ^LOINC(loincCode) | 2345-7 | name, units |
| Gene Ontology | ^GO(goId) | GO:0006915 | name, namespace |
| Wikidata | ^WIKI(qid) | Q42 | label, description |
| VIAF | ^VIAF(viafId) | 1234567 | name, sources |

### Relationship Links

| From | To | Global | Relationship |
|---|---|---|---|
| MeSH | CatLine | ^LINK("MESH",descUI,"CATLINE",nlmID) | "subject" |
| MeSH | PubMed | ^LINK("MESH",descUI,"PUBMED",pmid) | "mesh_term" |
| CatLine | SerLine | ^LINK("CATLINE",nlmID,"SERLINE",nlmID) | "serial" |
| PubMed | CatLine | ^LINK("PUBMED",pmid,"CATLINE",nlmID) | "journal" |
| PubMed | Crossref | ^LINK("PUBMED",pmid,"CROSSREF",doi) | "doi" |
| PubMed | ORCID | ^LINK("PUBMED",pmid,"ORCID",orcid) | "author" |
| PubMed | ClinicalTrials | ^LINK("PUBMED",pmid,"TRIAL",nctId) | "trial" |
| MeSH | ICD-10 | ^LINK("MESH",descUI,"ICD",code) | "disease_class" |
| MeSH | SNOMED | ^LINK("MESH",descUI,"SNOMED",sctId) | "clinical_term" |
| MeSH | DrugBank | ^LINK("MESH",descUI,"DRUG",drugId) | "drug" |
| MeSH | Gene Ontology | ^LINK("MESH",descUI,"GO",goId) | "gene" |
| ORCID | ROR | ^LINK("ORCID",orcid,"ROR",rorID) | "institution" |
| Wikidata | MeSH | ^LINK("WIKI",qid,"MESH",descUI) | "entity" |
| VIAF | CatLine | ^LINK("VIAF",viafId,"CATLINE",nlmID) | "authority" |

## Algorithm ↔ Data Source Mapping

### BM25 Keyword Search

```
For each record type:
  For each text field:
    tokenize(field) → terms
    For each term:
      ^BM25(term, recordType, recordId) = frequency
```

**Indexed fields:**
| Record | Fields | Example |
|---|---|---|
| MeSH | name, scopeNote | "hypertension", "Persistently high..." |
| CatLine | title, publisher | "Journal of hypertension", "Lippincott..." |
| PubMed | title, authors, abstract | "Hypertension treatment...", "Smith J..." |
| Crossref | title, authors | "Hypertension guidelines...", "Jones A..." |
| ORCID | name, institution | "John Smith", "Harvard Medical School" |
| ClinicalTrials | title, conditions | "Hypertension Study", "Hypertension" |
| DrugBank | name, description | "Lisinopril", "ACE inhibitor used for..." |

### HNSW Vector Search

```
For each record with text:
  embed(text) → vector
  ^VECTOR(recordType, recordId) = vector
  hnsw.insert(id, vector)
```

**Embeddable fields:**
| Record | Field | Purpose |
|---|---|---|
| MeSH | scopeNote | Semantic similarity of descriptors |
| PubMed | abstract | Semantic similarity of papers |
| DrugBank | description | Semantic similarity of drugs |
| ClinicalTrials | title+conditions | Semantic similarity of trials |

### Link Traversal

```
findRelated(recordType, recordId):
  results = []
  for link in ^LINK(recordType, recordId, *, *):
    results.add(link)
  return results
```

**Traversal patterns:**
| Query | Path | Result |
|---|---|---|
| "Find all papers about hypertension" | ^MESH → ^LINK → ^PUBMED | Paper list |
| "Find drugs for hypertension" | ^MESH → ^LINK → ^DRUG | Drug list |
| "Find clinical trials for hypertension" | ^MESH → ^LINK → ^TRIAL | Trial list |
| "Find journals publishing about hypertension" | ^MESH → ^LINK → ^CATLINE | Journal list |
| "Find author's papers" | ^ORCID → ^LINK → ^PUBMED | Paper list |
| "Find disease classification" | ^MESH → ^LINK → ^ICD | ICD codes |

### Pattern Matching (M native)

```
; Filter results by pattern
FOR I=1:1:N SET R=$ORDER(^PUBMED("")) QUIT:R=""  DO
 . I ^PUBMED(R,"title")?1.A1"Hypertension" W R,!
```

### Transaction Atomicity

```
; Atomic index update
TSTART
  ; Add document to BM25 index
  SET ^BM25("hypertension","PUBMED","12345678")=3
  SET ^BM25("treatment","PUBMED","12345678")=2
  ; Add to HNSW index
  ; Add links
  SET ^LINK("PUBMED","12345678","MESH","D000001")="mesh_term"
TCOMMIT
```

## Search Query Flow

```
User query: "hypertension treatment drugs"

1. Tokenize: ["hypertension", "treatment", "drugs"]

2. BM25 search:
   - Look up ^BM25("hypertension", *, *) → scored results
   - Look up ^BM25("treatment", *, *) → scored results
   - Look up ^BM25("drugs", *, *) → scored results
   - Combine scores (RRF or weighted sum)

3. Link traversal:
   - For each MeSH result: find linked drugs via ^LINK
   - For each PubMed result: find linked trials via ^LINK

4. Rank and return:
   - Sort by BM25 score
   - Return top-K results with links
```

## Implementation Priority

| Phase | Data Sources | Algorithms | Effort |
|---|---|---|---|
| 1 | MeSH, CatLine, SerLine, PubMed | BM25 | 2-3 days |
| 2 | + Crossref, ORCID | BM25 + links | 1-2 days |
| 3 | + ClinicalTrials, DrugBank | BM25 + HNSW | 2-3 days |
| 4 | + ICD-10, SNOMED, LOINC, GO | Full search | 1-2 days |
| 5 | + Wikidata, VIAF | Entity linking | 1 week |

## Value Proposition

**Before FST:**
- Each data source is separate
- No cross-references between sources
- Requires specialized tools for each source
- Hard to find related information

**After FST:**
- All data in one LMDB database
- Explicit relationships via ^LINK
- Unified keyword + semantic search
- Accessible from M code, MCP tools, or CLI
- No specialized tools needed

**Example workflow:**
```
; Search for hypertension
W $NI_SEARCH("hypertension")
; Returns: MeSH D000001, PubMed papers, CatLine journals

; Find related drugs
W $NI_LINKS("MESH", "D000001", "DRUG")
; Returns: Lisinopril, Amlodipine, etc.

; Find clinical trials
W $NI_LINKS("MESH", "D000001", "TRIAL")
; Returns: NCT12345678, etc.
```
