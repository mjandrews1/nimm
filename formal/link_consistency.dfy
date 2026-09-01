// formal/link_consistency.dfy
//
// Formal model of the FST ^LINK cross-reference design (#459):
//   MeSH-outbound links between a descriptor and the three record types
//   (PUBMED/CATLINE/SERLINE), with reverse lookups kept on per-record
//   "mesh" subscripts rather than a second (bi-directional) link table.
//
// The loaders maintain TWO physical encodings of ONE logical relation:
//   fwd  ^LINK("MESH", dui, type, id)     — MeSH-outbound table
//   rev  ^TYPE(id, "mesh", dui)           — per-record subscripts
// The core invariant is that they encode the same set of links (fwd == rev),
// so the two query directions — "records for a descriptor" and "descriptors
// for a record" — never diverge.
//
// Proved here:
//   1. A joint link/unlink operation preserves fwd == rev (no one-sided write).
//   2. Linking is idempotent (dedup: re-linking an existing pair is a no-op).
//   3. Soundness: a link built by resolving MeSH-heading *names* via the
//      dictionary references a known descriptor — no dangling links.
//   4. Duality: the forward and reverse queries are equivalent views of the
//      shared set (so bi-directional storage is unnecessary).
//
// Verify with:  dafny verify formal/link_consistency.dfy

module LinkConsistency {

  type DUI = string
  type RecId = string

  // The three record types that a MeSH descriptor can point at.
  datatype Target = PUBMED | CATLINE | SERLINE

  // A link is MeSH-outbound by construction: the descriptor UI is the source
  // and the (targetType, recordId) is the destination. There is no record→MeSH
  // link shape, so a bi-directional link table cannot even be expressed.
  datatype Link = Link(dui: DUI, t: Target, id: RecId)

  // ============ 1. forward/reverse consistency ============

  // Link a (dui, type, id) triple into BOTH encodings at once.
  function LinkBoth(fwd: set<Link>, rev: set<Link>, l: Link): (set<Link>, set<Link>)
  {
    (fwd + {l}, rev + {l})
  }

  // Unlink a triple from BOTH encodings at once.
  function UnlinkBoth(fwd: set<Link>, rev: set<Link>, l: Link): (set<Link>, set<Link>)
  {
    (fwd - {l}, rev - {l})
  }

  // A one-sided write (only fwd or only rev) would break fwd == rev; the joint
  // operation preserves it.
  lemma LinkBothPreservesConsistency(fwd: set<Link>, rev: set<Link>, l: Link)
    requires fwd == rev
    ensures var r := LinkBoth(fwd, rev, l); r.0 == r.1
  {
  }

  lemma UnlinkBothPreservesConsistency(fwd: set<Link>, rev: set<Link>, l: Link)
    requires fwd == rev
    ensures var r := UnlinkBoth(fwd, rev, l); r.0 == r.1
  {
  }

  // ============ 2. idempotent dedup ============

  // Re-linking a pair that already exists leaves both encodings unchanged.
  lemma LinkBothIdempotent(fwd: set<Link>, rev: set<Link>, l: Link)
    requires fwd == rev
    requires l in fwd
    ensures var r := LinkBoth(fwd, rev, l); r.0 == fwd && r.1 == rev
  {
  }

  // ============ 3. name→UI resolution soundness ============

  datatype Option<T> = None | Some(value: T)

  // The ^MESHTERM dictionary maps a MeSH-heading *name* to at most one
  // descriptor UI. Names not in the dictionary resolve to None.
  function resolve(name: string): Option<DUI>

  // A "known" descriptor is one that some heading name resolves to.
  ghost predicate Known(dui: DUI)
  {
    exists n :: resolve(n) == Some(dui)
  }

  // Build the links for one record from its list of MeSH-heading names:
  // only names that actually resolve to a descriptor UI produce a link.
  function BuildLinks(t: Target, id: RecId, names: seq<string>): set<Link>
    decreases |names|
  {
    if |names| == 0 then {}
    else
      (if resolve(names[0]).Some? then {Link(resolve(names[0]).value, t, id)} else {})
      + BuildLinks(t, id, names[1..])
  }

  // Soundness: every link built by name resolution references a known
  // descriptor — no dangling link to a non-existent UI.
  lemma BuildLinksKnownOnly(t: Target, id: RecId, names: seq<string>)
    ensures forall l | l in BuildLinks(t, id, names) :: Known(l.dui)
    decreases |names|
  {
    if |names| == 0 {
    } else {
      BuildLinksKnownOnly(t, id, names[1..]);
    }
  }

  // ============ 4. query duality ============

  // Forward query: records of type t linked from descriptor dui.
  function RecordsOf(links: set<Link>, t: Target, dui: DUI): set<RecId>
  {
    set l <- links | l.t == t && l.dui == dui :: l.id
  }

  // Reverse query: descriptors linked to record (t, id).
  function DescriptorsOf(links: set<Link>, t: Target, id: RecId): set<DUI>
  {
    set l <- links | l.t == t && l.id == id :: l.dui
  }

  // A record id is linked from dui iff dui is linked to that record: the two
  // query directions are dual views of the single link set, so no second
  // (bi-directional) table is needed.
  lemma QueryDuality(links: set<Link>, t: Target, dui: DUI, id: RecId)
    ensures id in RecordsOf(links, t, dui) <==> dui in DescriptorsOf(links, t, id)
  {
    assert id in RecordsOf(links, t, dui) <==> (exists l :: l in links && l.t == t && l.dui == dui && l.id == id);
    assert dui in DescriptorsOf(links, t, id) <==> (exists l :: l in links && l.t == t && l.dui == dui && l.id == id);
  }

}
