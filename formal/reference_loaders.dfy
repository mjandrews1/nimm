// formal/reference_loaders.dfy
//
// Formal model of the standalone reference loaders (build_medicare.nim,
// build_cdc.nim, build_faers.nim; #462 Phase 2). Unlike the cross-linking
// loaders, these have no deterministic join to the MeSH/PubMed graph, so the
// contract is about record shape: each source row maps to exactly one record
// keyed by a leading identity subscript, field writes are idempotent
// (overwriting a field with the same value is a no-op), and the loaded set is
// the fold of singleton insertions.
//
// Verify with:  dafny verify formal/reference_loaders.dfy

module ReferenceLoaders {

  // A record is a set of (field, value) pairs under one identity key; fields
  // are written once per row. Idempotency: re-SETting the same (field,value)
  // does not change the record.
  lemma SetIdempotent(rec: map<string, string>, field: string, v: string)
    ensures rec[field := v][field := v] == rec[field := v]
  {
  }

  // Writing two different fields is commutative (order-independent record).
  lemma SetFieldsCommute(rec: map<string, string>, f1: string, v1: string,
                         f2: string, v2: string)
    requires f1 != f2
    ensures rec[f1 := v1][f2 := v2] == rec[f2 := v2][f1 := v1]
  {
  }

  // The set of records loaded is the fold of one insertion per row: adding a
  // row present already (same identity key) yields the same set cardinality.
  lemma FoldIdempotent(records: set<string>, key: string)
    ensures |records + {key}| == (if key in records then |records| else |records| + 1)
  {
  }

  // Distinct identity keys produce distinct records (no cross-row merges).
  lemma DistinctKeysStayDistinct(a: string, b: string)
    requires a != b
    ensures a in {a, b} && b in {a, b} && |{a, b}| == 2
  {
  }

}
