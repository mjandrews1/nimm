#!/usr/bin/env python3
"""
FST NLM Data Loader — Load NLM data via NimM -x commands.
Uses NimM's own LMDB for compatibility.

Usage:
  python3 fst_loader.py --db /path/to/fst.lmdb [--data-dir /path/to/data]
"""

import argparse
import gzip
import os
import subprocess
import sys
import xml.etree.ElementTree as ET


def run_mcode(db, code):
    """Execute M code via nimm and return output."""
    result = subprocess.run(
        ["./bin/nimm", "-d", db, "-x", code],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()


def load_mesh_descriptors(db, path):
    print(f"Loading MeSH descriptors from {path}...")
    count = 0
    tree = ET.parse(path)
    root = tree.getroot()
    
    # Batch writes: collect all SET commands, execute in chunks
    batch = []
    for record in root.findall(".//DescriptorRecord"):
        desc_ui = record.findtext("DescriptorUI", "")
        desc_name = record.findtext("DescriptorName/String", "")
        scope_note = record.findtext("ScopeNote", "")
        
        if not desc_ui:
            continue
        
        # Escape quotes in values
        desc_name = desc_name.replace('"', '""')
        scope_note = scope_note.replace('"', '""')
        
        batch.append(f'SET ^MESH("{desc_ui}","name")="{desc_name}"')
        if scope_note:
            batch.append(f'SET ^MESH("{desc_ui}","scopeNote")="{scope_note}"')
        
        for tree_num in record.findall(".//TreeNumber"):
            tn = tree_num.text
            if tn:
                batch.append(f'SET ^MESH("{desc_ui}","treeNumber","{tn}")="1"')
        
        for aq in record.findall(".//AllowableQualifier"):
            qual_ui = aq.findtext("QualifierReferredTo/QualifierUI", "")
            if qual_ui:
                batch.append(f'SET ^MESH("{desc_ui}","qualifier","{qual_ui}")="1"')
        
        count += 1
        
        # Execute batch every 100 records
        if len(batch) >= 500:
            code = " ".join(batch)
            run_mcode(db, code)
            batch = []
            if count % 1000 == 0:
                print(f"  Loaded {count} descriptors...")
    
    # Execute remaining batch
    if batch:
        code = " ".join(batch)
        run_mcode(db, code)
    
    print(f"  Loaded {count} MeSH descriptors")
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
        
        qual_name = qual_name.replace('"', '""')
        abbrev = abbrev.replace('"', '""')
        
        batch.append(f'SET ^QUAL("{qual_ui}","name")="{qual_name}"')
        if abbrev:
            batch.append(f'SET ^QUAL("{qual_ui}","abbreviation")="{abbrev}"')
        
        count += 1
    
    if batch:
        code = " ".join(batch)
        run_mcode(db, code)
    
    print(f"  Loaded {count} MeSH qualifiers")
    return count


def load_mesh_supplements(db, path):
    print(f"Loading MeSH supplements from {path}...")
    count = 0
    
    if os.path.isdir(path):
        files = [os.path.join(path, f) for f in os.listdir(path) if f.endswith('.xml')]
    else:
        files = [path]
    
    for fpath in files:
        tree = ET.parse(fpath)
        root = tree.getroot()
        
        batch = []
        for record in root.findall(".//SupplementalRecord"):
            scr_id = record.findtext("SupplementalRecordUI", "")
            scr_name = record.findtext("SupplementalRecordName/String", "")
            
            if not scr_id:
                continue
            
            scr_name = scr_name.replace('"', '""')
            batch.append(f'SET ^SUPPLEMENT("{scr_id}","name")="{scr_name}"')
            
            for mapped in record.findall(".//HeadingMappedTo"):
                desc_ui = mapped.findtext("DescriptorUI", "")
                if desc_ui:
                    batch.append(f'SET ^SUPPLEMENT("{scr_id}","mappedTo")="{desc_ui}"')
                    batch.append(f'SET ^LINK("SUPPLEMENT","{scr_id}","MESH","{desc_ui}")="mapped"')
            
            count += 1
            
            if len(batch) >= 500:
                code = " ".join(batch)
                run_mcode(db, code)
                batch = []
                if count % 1000 == 0:
                    print(f"  Loaded {count} supplements...")
        
        if batch:
            code = " ".join(batch)
            run_mcode(db, code)
    
    print(f"  Loaded {count} MeSH supplements")
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
        
        title = title.replace('"', '""')
        issn = issn.replace('"', '""')
        publisher = publisher.replace('"', '""')
        
        if title:
            batch.append(f'SET ^CATLINE("{nlm_id}","title")="{title}"')
        if issn:
            batch.append(f'SET ^CATLINE("{nlm_id}","issn")="{issn}"')
        if publisher:
            batch.append(f'SET ^CATLINE("{nlm_id}","publisher")="{publisher}"')
        
        count += 1
        
        if len(batch) >= 500:
            code = " ".join(batch)
            run_mcode(db, code)
            batch = []
            if count % 1000 == 0:
                print(f"  Loaded {count} CatLine records...")
    
    if batch:
        code = " ".join(batch)
        run_mcode(db, code)
    
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
        
        title = title.replace('"', '""')
        issn = issn.replace('"', '""')
        holdings = holdings.replace('"', '""')
        
        if title:
            batch.append(f'SET ^SERLINE("{nlm_id}","title")="{title}"')
        if issn:
            batch.append(f'SET ^SERLINE("{nlm_id}","issn")="{issn}"')
        if holdings:
            batch.append(f'SET ^SERLINE("{nlm_id}","holdings")="{holdings}"')
        
        count += 1
        
        if len(batch) >= 500:
            code = " ".join(batch)
            run_mcode(db, code)
            batch = []
            if count % 1000 == 0:
                print(f"  Loaded {count} SerLine records...")
    
    if batch:
        code = " ".join(batch)
        run_mcode(db, code)
    
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
                
                title = title.replace('"', '""')
                journal = journal.replace('"', '""')
                abstract = abstract.replace('"', '""')
                
                if title:
                    batch.append(f'SET ^PUBMED("{pmid}","title")="{title}"')
                if authors:
                    batch.append(f'SET ^PUBMED("{pmid}","authors")="{",".join(authors)}"')
                if journal:
                    batch.append(f'SET ^PUBMED("{pmid}","journal")="{journal}"')
                if abstract:
                    if len(abstract) > 500:
                        abstract = abstract[:500] + "..."
                    batch.append(f'SET ^PUBMED("{pmid}","abstract")="{abstract}"')
                
                for term in mesh_terms:
                    batch.append(f'SET ^PUBMED("{pmid}","mesh","{term}")="1"')
                
                count += 1
                
                if len(batch) >= 500:
                    code = " ".join(batch)
                    run_mcode(db, code)
                    batch = []
                    if count % 1000 == 0:
                        print(f"    Loaded {count} citations...")
                
                if max_records > 0 and count >= max_records:
                    break
        
        if batch:
            code = " ".join(batch)
            run_mcode(db, code)
        
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

    # Initialize database
    run_mcode(db, 'SET ^FST("status")="loading"')

    total = 0

    if "mesh" not in args.skip:
        mesh_dir = os.path.join(data_dir, "mesh-staging", "xml")
        if os.path.exists(mesh_dir):
            desc_path = os.path.join(mesh_dir, "desc2026.xml")
            qual_path = os.path.join(mesh_dir, "qual2026.xml")
            supp_path = os.path.join(mesh_dir, "supp2026")
            if os.path.exists(desc_path):
                total += load_mesh_descriptors(db, desc_path)
            if os.path.exists(qual_path):
                total += load_mesh_qualifiers(db, qual_path)
            if os.path.exists(supp_path):
                total += load_mesh_supplements(db, supp_path)

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

    # Mark as loaded
    run_mcode(db, 'SET ^FST("status")="loaded"')
    run_mcode(db, f'SET ^FST("records")="{total}"')

    print()
    print(f"Total records loaded: {total}")
    print("Done!")


if __name__ == "__main__":
    main()
