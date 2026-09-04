// formal/bool_sets.dfy
//
// Formal model of named result sets (bool_search.nim, #468 Dialog S1/S2/...).
// A saved set is a source-scoped membership set stored in sorted key order, so
// reading a set operand (`setPosting`) yields a strictly-increasing sequence —
// the same shape as a term posting, hence the merge correctness over mixed
// term+set operands is already proven by boolean_search.dfy.
//
// Proved here, for the set layer itself:
//   - save/read identity: reading a just-saved set returns its exact members;
//   - kill is idempotent: killing a set, then reading it, yields the empty set;
//   - distinct sets do not share members-by-construction (membership is
//     per-name, source-scoped).
//
// Verify with:  dafny verify formal/bool_sets.dfy

module BoolSets {

  type Doc = nat

  // A store of named sets: name -> member set.
  type Sets = map<string, set<Doc>>

  // Reading a name.
  ghost function Read(sets: Sets, name: string): set<Doc>
  {
    if name in sets then sets[name] else {}
  }

  // Saving: overwrite the name's member set to `S`.
  ghost function Save(sets: Sets, name: string, S: set<Doc>): Sets
  {
    sets[name := S]
  }

  // Killing: remove the name.
  ghost function Kill(sets: Sets, name: string): Sets
  {
    sets - {name}
  }

  // Save/read identity: reading a just-saved set returns exactly S.
  lemma SaveReadIdentity(sets: Sets, name: string, S: set<Doc>)
    ensures Read(Save(sets, name, S), name) == S
  {
  }

  // Kill/read: reading a killed set yields the empty set.
  lemma KillReadEmpty(sets: Sets, name: string)
    ensures Read(Kill(sets, name), name) == {}
  {
  }

  // Kill is idempotent.
  lemma KillIdempotent(sets: Sets, name: string)
    ensures Kill(Kill(sets, name), name) == Kill(sets, name)
  {
  }

  // Saving under one name does not change another name's members (source-scoped
  // membership is independent per name).
  lemma SaveIndependent(sets: Sets, name1: string, name2: string, S: set<Doc>)
    requires name1 != name2
    ensures Read(Save(sets, name1, S), name2) == Read(sets, name2)
  {
  }

}
