#!/usr/bin/env python3
"""
FST Data Loader — Parse NLM XML, generate M commands for NimM.
Uses NimM's own LMDB via -x flag for compatibility.

Usage:
  python3 fst_load.py --db /path/to/fst.lmdb [--data-dir /path/to/data] [--max N]
"""

import argparse
import gzip
import os
import subprocess
import sys
import xml.etree.ElementTree as ET


def run_mcode(db, code):
    """Execute M code via nimm -x."""
    result = subprocess.run(
        ["./nimm", "-d", db, "-x", code],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        print(f"ERROR: {result.stderr.strip()}", file=sys.stderr)
        return False
    return True


def escape_m(s):
    """Escape string for M literal."""
    return s.replace('"', '""')


def load_mesh_descriptors(db, path, max_records=0):
    print(f"Loading MeSH descriptors from {path}...")
    count = 0
    errors = 0
    
    tree = ET.parse(path)
    root = tree.getroot()
    
    batch = []
    for record in root.findall(".//DescriptorRecord"):
        desc_ui = record.findtext("DescriptorUI", "")
        desc_name = record.findtext("DescriptorName/String", "")
        scope_note = record.findtext("ScopeNote", "")
        
        if not desc_ui:
            continue
        
        batch.append(f'SET ^MESH("{escape_m(desc_ui)}","name")="{escape_m(desc_name)}"')
        if scope_note:
            batch.append(f'SET ^MESH("{escape_m(desc_ui)}","scopeNote")="{escape_m(scope_note[:500])}"')
        
        for tree_num in record.findall(".//TreeNumber"):
            tn = tree_num.text
            if tn:
                batch.append(f'SET ^MESH("{escape_m(desc_ui)}","treeNumber","{escape_m(tn)}")="1"')
        
        for aq in record.findall(".//AllowableQualifier"):
            qual_ui = aq.findtext("QualifierReferredTo/QualifierUI", "")
            if qual_ui:
                batch.append(f'SET ^MESH("{escape_m(desc_ui)}","qualifier","{escape_m(qual_ui)}")="1"')
        
        count += 1
        
        if len(batch) >= 200:
            code = " ".join(batch)
            if not run_mcode(db, code):
                errors += 1
            batch = []
            if count % 500 == 0:
                print(f"  Loaded {count} descriptors...")
        
        if max_records > 0 and count >= max_records:
            break
    
    if batch:
        code = " ".join(batch)
        if not run_mcode(db, code):
            errors += 1
    
    print(f"  Loaded {count} MeSH descriptors ({errors} errors)")
    return count


def load_mesh_qualifiers(db, path):
    print(f"Loading MeSH qualifiers from {path}...")
    count = 0
    tree = ET.parse(path)
    root = tree.getroot()
    
    batch = []
    for record in root.findall(".//QualifierRecord"):
        qual_ui = record.findtext("QualifierUI", "")
        qual_name = record.findtext("QualifierName/String", "")
        abbrev = record.findtext("Abbreviation", "")
        
        if not qual_ui:
            continue
        
        batch.append(f'SET ^QUAL("{escape_m(qual_ui)}","name")="{escape_m(qual_name)}"')
        if abbrev:
            batch.append(f'SET ^QUAL("{escape_m(qual_ui)}","abbreviation")="{escape_m(abbrev)}"')
        
        count += 1
    
    if batch:
        run_mcode(db, " ".join(batch))
    
    print(f"  Loaded {count} MeSH qualifiers")
    return count


def load_catline(db, path):
    print(f"Loading CatLine from {path}...")
    count = 0
    
    tree = ET.parse(path)
    root = tree.getroot()
    ns = {"marc": "http://www.loc.gov/MARC21/slim"}
    
    batch = []
    for record in root.findall(".//marc:record", ns):
        nlm_id = ""
        for cf in record.findall("marc:controlfield", ns):
            if cf.get("tag") == "001":
                nlm_id = cf.text.strip() if cf.text else ""
                break
        
        if not nlm_id:
            continue
        
        title = ""
        issn = ""
        publisher = ""
        
        for df in record.findall("marc:datafield", ns):
            tag = df.get("tag", "")
            if tag == "245":
                for sf in df.findall("marc:subfield", ns):
                    if sf.get("code") == "a":
                        title = sf.text.strip() if sf.text else ""
            elif tag == "022":
                for sf in df.findall("marc:subfield", ns):
                    if sf.get("code") == "a":
                        issn = sf.text.strip() if sf.text else ""
            elif tag == "260":
                for sf in df.findall("marc:subfield", ns):
                    if sf.get("code") == "b":
                        publisher = sf.text.strip() if sf.text else ""
        
        if title:
            batch.append(f'SET ^CATLINE("{escape_m(nlm_id)}","title")="{escape_m(title)}"')
        if issn:
            batch.append(f'SET ^CATLINE("{escape_m(nlm_id)}","issn")="{escape_m(issn)}"')
        if publisher:
            batch.append(f'SET ^CATLINE("{escape_m(nlm_id)}","publisher")="{escape_m(publisher)}"')
        
        count += 1
        
        if len(batch) >= 200:
            run_mcode(db, " ".join(batch))
            batch = []
            if count % 500 == 0:
                print(f"  Loaded {count} CatLine records...")
    
    if batch:
        run_mcode(db, " ".join(batch))
    
    print(f"  Loaded {count} CatLine records")
    return count


def load_serline(db, path):
    print(f"Loading SerLine from {path}...")
    count = 0
    
    tree = ET.parse(path)
    root = tree.getroot()
    ns = {"marc": "http://www.loc.gov/MARC21/slim"}
    
    batch = []
    for record in root.findall(".//marc:record", ns):
        nlm_id = ""
        for cf in record.findall("marc:controlfield", ns):
            if cf.get("tag") == "001":
                nlm_id = cf.text.strip() if cf.text else ""
                break
        
        if not nlm_id:
            continue
        
        title = ""
        issn = ""
        holdings = ""
        
        for df in record.findall("marc:datafield", ns):
            tag = df.get("tag", "")
            if tag == "245":
                for sf in df.findall("marc:subfield", ns):
                    if sf.get("code") == "a":
                        title = sf.text.strip() if sf.text else ""
            elif tag == "022":
                for sf in df.findall("marc:subfield", ns):
                    if sf.get("code") == "a":
                        issn = sf.text.strip() if sf.text else ""
            elif tag == "853":
                for sf in df.findall("marc:subfield", ns):
                    if sf.get("code") == "a":
                        holdings = sf.text.strip() if sf.text else ""
        
        if title:
            batch.append(f'SET ^SERLINE("{escape_m(nlm_id)}","title")="{escape_m(title)}"')
        if issn:
            batch.append(f'SET ^SERLINE("{escape_m(nlm_id)}","issn")="{escape_m(issn)}"')
        if holdings:
            batch.append(f'SET ^SERLINE("{escape_m(nlm_id)}","holdings")="{escape_m(holdings)}"')
        
        count += 1
        
        if len(batch) >= 200:
            run_mcode(db, " ".join(batch))
            batch = []
            if count % 500 == 0:
                print(f"  Loaded {count} SerLine records...")
    
    if batch:
        run_mcode(db, " ".join(batch))
    
    print(f"  Loaded {count} SerLine records")
    return count


def load_pubmed(db, path, max_records=0):
    print(f"Loading PubMed from {path}...")
    count = 0
    
    if os.path.isdir(path):
        files = sorted([os.path.join(path, f) for f in os.listdir(path) if f.endswith('.xml.gz')])
    else:
        files = [path]
    
    for fpath in files:
        print(f"  Processing {os.path.basename(fpath)}...")
        
        batch = []
        with gzip.open(fpath, 'rt') as f:
            tree = ET.parse(f)
            root = tree.getroot()
            
            for article in root.findall(".//PubmedArticle"):
                pmid = article.findtext(".//PMID", "")
                if not pmid:
                    continue
                
                title = article.findtext(".//ArticleTitle", "")
                authors = []
                for author in article.findall(".//Author"):
                    last = author.findtext("LastName", "")
                    first = author.findtext("ForeName", "")
                    if last:
                        authors.append(f"{last} {first}".strip())
                
                journal = article.findtext(".//Title", "")
                abstract = article.findtext(".//AbstractText", "")
                
                mesh_terms = []
                for mesh in article.findall(".//MeshHeading/DescriptorName"):
                    if mesh.text:
                        mesh_terms.append(mesh.text)
                
                if title:
                    batch.append(f'SET ^PUBMED("{escape_m(pmid)}","title")="{escape_m(title[:300])}"')
                if authors:
                    batch.append(f'SET ^PUBMED("{escape_m(pmid)}","authors")="{escape_m(",".join(authors[:5]))}"')
                if journal:
                    batch.append(f'SET ^PUBMED("{escape_m(pmid)}","journal")="{escape_m(journal[:200])}"')
                if abstract:
                    batch.append(f'SET ^PUBMED("{escape_m(pmid)}","abstract")="{escape_m(abstract[:500])}"')
                
                for term in mesh_terms[:10]:
                    batch.append(f'SET ^PUBMED("{escape_m(pmid)}","mesh","{escape_m(term)}")="1"')
                
                count += 1
                
                if len(batch) >= 200:
                    run_mcode(db, " ".join(batch))
                    batch = []
                    if count % 1000 == 0:
                        print(f"    Loaded {count} citations...")
                
                if max_records > 0 and count >= max_records:
                    break
        
        if batch:
            run_mcode(db, " ".join(batch))
        
        if max_records > 0 and count >= max_records:
            break
    
    print(f"  Loaded {count} PubMed citations")
    return count


def main():
    parser = argparse.ArgumentParser(description="FST NLM Data Loader")
    parser.add_argument("--db", required=True, help="LMDB database path")
    parser.add_argument("--data-dir", default="/Users/mark/_diary-data", help="Data directory")
    parser.add_argument("--max-records", type=int, default=0, help="Max records per type (0=all)")
    parser.add_argument("--skip", nargs="*", default=[], help="Skip data types: mesh, catline, serline, pubmed")
    args = parser.parse_args()

    db = args.db
    data_dir = args.data_dir

    print(f"Loading NLM data into {db}")
    print(f"Data directory: {data_dir}")
    print()

    run_mcode(db, 'SET ^FST("status")="loading"')

    total = 0

    if "mesh" not in args.skip:
        mesh_dir = os.path.join(data_dir, "mesh-staging", "xml")
        if os.path.exists(mesh_dir):
            desc_path = os.path.join(mesh_dir, "desc2026.xml")
            qual_path = os.path.join(mesh_dir, "qual2026.xml")
            if os.path.exists(desc_path):
                total += load_mesh_descriptors(db, desc_path, args.max_records)
            if os.path.exists(qual_path):
                total += load_mesh_qualifiers(db, qual_path)

    if "catline" not in args.skip:
        catline_dir = os.path.join(data_dir, "nlm-staging", "catplus-marcxml")
        if os.path.exists(catline_dir):
            for f in sorted(os.listdir(catline_dir)):
                if f.endswith('.xml'):
                    total += load_catline(db, os.path.join(catline_dir, f))

    if "serline" not in args.skip:
        serline_dir = os.path.join(data_dir, "nlm-staging", "serfile-marcxml")
        if os.path.exists(serline_dir):
            for f in sorted(os.listdir(serline_dir)):
                if f.endswith('.xml'):
                    total += load_serline(db, os.path.join(serline_dir, f))

    if "pubmed" not in args.skip:
        pubmed_dir = os.path.join(data_dir, "pubmed-baseline")
        if os.path.exists(pubmed_dir):
            total += load_pubmed(db, pubmed_dir, args.max_records)

    run_mcode(db, f'SET ^FST("status")="loaded"')
    run_mcode(db, f'SET ^FST("records")="{total}"')

    # Build index file for search (workaround for $ORDER bug #355)
    import json
    index = {}
    if "mesh" not in args.skip:
        mesh_dir = os.path.join(data_dir, "mesh-staging", "xml")
        if os.path.exists(mesh_dir):
            desc_path = os.path.join(mesh_dir, "desc2026.xml")
            if os.path.exists(desc_path):
                tree = ET.parse(desc_path)
                root = tree.getroot()
                mesh_index = {}
                for record in root.findall(".//DescriptorRecord"):
                    desc_ui = record.findtext("DescriptorUI", "")
                    desc_name = record.findtext("DescriptorName/String", "")
                    if desc_ui and desc_name:
                        mesh_index[desc_ui] = desc_name
                index["MESH"] = mesh_index
    
    index_file = db + ".index.json"
    with open(index_file, "w") as f:
        json.dump(index, f)
    print(f"Index written to {index_file}")

    print()
    print(f"Total records loaded: {total}")
    print("Done!")


if __name__ == "__main__":
    main()
