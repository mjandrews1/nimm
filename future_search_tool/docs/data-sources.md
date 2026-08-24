# FST Data Sources

## Bibliographic
| Source | URL | Format | Size | License |
|---|---|---|---|---|
| OpenLibrary | openlibrary.org/developers/dumps | JSON, CSV | ~2GB dump | CC0 |
| arXiv | arxiv.org/help/api | JSON, XML | ~2M papers | CC0 |
| Crossref | api.crossref.org | JSON | ~150M records | CC0 |
| PubMed | ncbi.nlm.nih.gov/pubmed | XML, JSON | ~36M abstracts | Public domain |
| Semantic Scholar | api.semanticscholar.org | JSON | ~200M papers | ODC-By |

## Authority/Thesaurus
| Source | URL | Format | Size | License |
|---|---|---|---|---|
| Library of Congress | loc.gov/standards | MARC, JSON | ~20M records | Public domain |
| VIAF | viaf.org | JSON, XML | ~40M records | ODC-By |
| Wikidata | wikidata.org/wiki/Wikidata:Database_download | JSON, RDF | ~100GB | CC0 |
| MeSH | nlm.nih.gov/mesh | JSON, XML | ~30K descriptors | Public domain |

## Citation
| Source | URL | Format | Size | License |
|---|---|---|---|---|
| OpenCitations | opencitations.net | JSON, CSV | ~1B citations | CC0 |
| Crossref | api.crossref.org | JSON | ~150M records | CC0 |

## Full Text
| Source | URL | Format | Size | License |
|---|---|---|---|---|
| Project Gutenberg | gutenberg.org/ebooks | Plain text, HTML | ~60K books | Public domain |
| arXiv | arxiv.org/help/api | PDF, HTML | ~2M papers | CC0 |
| PubMed Central | ncbi.nlm.nih.gov/pmc | XML, PDF | ~8M articles | Public domain |
| DOAJ | doaj.org/api | JSON, CSV | ~19M articles | CC0 |

## Data Sets
| Source | URL | Format | Size | License |
|---|---|---|---|---|
| Kaggle | kaggle.com/datasets | CSV, JSON, Parquet | Varies | Varies |
| data.gov | data.gov | CSV, JSON | Varies | Public domain |
| UCI ML Repository | archive.ics.uci.edu | CSV | Varies | CC0 |
| Hugging Face | huggingface.co/datasets | CSV, JSON, Parquet | Varies | Varies |

## Time Series
| Source | URL | Format | Size | License |
|---|---|---|---|---|
| FRED | fred.stlouisfed.org | CSV, JSON | ~800K series | Public domain |
| World Bank | data.worldbank.org | CSV, JSON | ~20K indicators | CC0 |
| NOAA | ncdc.noaa.gov | CSV, JSON | Varies | Public domain |
| Yahoo Finance | finance.yahoo.com | CSV | Varies | Fair use |

## US Federal Government (focused subset)
| Agency | Data | URL | Format | License |
|---|---|---|---|---|
| HHS/CDC | Health statistics, disease data, drug labels | data.gov, cdc.gov | CSV, JSON | Public domain |
| NIH/PubMed | Biomedical literature, clinical trials | pubmed.gov, clinicaltrials.gov | XML, JSON | Public domain |
| Census | Demographics, housing, economic surveys | census.gov | CSV, JSON | Public domain |
| BLS | Employment, wages, inflation | bls.gov | CSV, JSON | Public domain |
| FRED | Economic time series | fred.stlouisfed.org | CSV, JSON | Public domain |
| Library of Congress | Bibliographic records, authority files | loc.gov | MARC, JSON | Public domain |
| NASA | Technical reports, datasets | nasa.gov | Various | Public domain |

**Notes:**
- All US Federal Government data is public domain (no licensing restrictions)
- data.gov is the central portal but has thousands of datasets — focus on the subset above
- API rate limits may apply for some services
- Some datasets are very large (Census, BLS) — consider incremental loading

## Notes
- All sources listed are free and publicly accessible
- Sizes are approximate
- Licenses may vary by dataset within a source
- API rate limits may apply

## Supplementary/Complementary Sources

These sources enhance the NLM data by adding cross-references, identifiers, and related domain data.

### Citation & Author Linking
| Source | URL | Enhances | License |
|---|---|---|---|
| Crossref | api.crossref.org | PubMed (DOI linking, citation counts) | CC0 |
| OpenCitations | opencitations.net | PubMed (citation graph) | CC0 |
| Semantic Scholar | api.semanticscholar.org | PubMed (abstracts, citations) | ODC-By |
| ORCID | orcid.org | PubMed/CatLine (author disambiguation) | CC0 |
| ROR | ror.org | PubMed/CatLine (institution identifiers) | CC0 |

### Clinical & Drug Data
| Source | URL | Enhances | License |
|---|---|---|---|
| ClinicalTrials.gov | clinicaltrials.gov | PubMed (trial→paper links) | Public domain |
| DrugBank | drugbank.com | MeSH (drug→disease links) | CC BY-NC 4.0 |
| RxNorm | nlm.nih.gov/research/umls/rxnorm | MeSH (drug name normalization) | Public domain |

### Terminology & Classification
| Source | URL | Enhances | License |
|---|---|---|---|
| ICD-10 | who.int/classifications | MeSH (disease classification cross-ref) | Public domain |
| SNOMED CT | snomed.org | MeSH (clinical terminology) | SNOMED license |
| LOINC | loinc.org | MeSH (lab observation codes) | CC BY 4.0 |
| Gene Ontology | geneontology.org | PubMed (gene/protein annotations) | CC BY 4.0 |

### Entity Linking
| Source | URL | Enhances | License |
|---|---|---|---|
| Wikidata | wikidata.org | All (entity cross-references) | CC0 |
| VIAF | viaf.org | CatLine/SerLine (authority control) | ODC-By |

### Why These Matter

| Enhancement | Without | With |
|---|---|---|
| Author search | Name strings only | ORCID disambiguation |
| Citation graph | None | Crossref + OpenCitations links |
| Drug-disease links | MeSH terms only | DrugBank + MeSH cross-ref |
| Trial-paper links | None | ClinicalTrials.gov + PubMed |
| Disease classification | MeSH only | MeSH + ICD-10 + SNOMED CT |
| Institution search | Text matching | ROR identifiers |
