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
