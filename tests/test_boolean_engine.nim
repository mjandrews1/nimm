# test_boolean_engine.nim — behavioral test of bool_search.nim (#468).
#
# Exercises the lexer/parser (AND/OR/NOT precedence, parens, phrases) and the
# evaluator (zig-zag merge soundness/completeness/commutativity, NOT-as-
# difference, phrase adjacency via ^BMPOS) over an in-memory store.
#
# Run: nim c -r tests/test_boolean_engine.nim

import ../globals
import ../future_search_tool/src/bool_search

proc seed(g: var Globals) =
  # docs d1..d3 with terms heart/lung/bone; phrases for myasthenia gravis
  g.set("^BM25", @["heart", "MESH", "d1"], "1")
  g.set("^BM25", @["lung", "MESH", "d1"], "1")
  g.set("^BM25", @["heart", "MESH", "d2"], "1")
  g.set("^BM25", @["bone", "MESH", "d2"], "1")
  g.set("^BM25", @["heart", "MESH", "d3"], "1")
  g.set("^BM25LEN", @["MESH", "d1"], "10")
  g.set("^BM25LEN", @["MESH", "d2"], "10")
  g.set("^BM25LEN", @["MESH", "d3"], "10")
  g.set("^BM25DF", @["heart", "MESH"], "3")
  g.set("^BM25DF", @["lung", "MESH"], "1")
  g.set("^BM25DF", @["bone", "MESH"], "1")

proc main() =
  echo "boolean_engine test..."
  var g = newGlobals("")

  # --- parser only ---
  let e1 = parseBool("heart AND lung OR bone")
  assert e1.kind == eOr, "OR is outermost (lowest precedence)"
  assert e1.left.kind == eAnd, "left of OR is an AND"
  assert e1.left.left.kind == eTerm and e1.left.left.term == "heart", "heart"
  assert e1.left.right.kind == eTerm and e1.left.right.term == "lung", "lung"
  assert e1.right.kind == eTerm and e1.right.term == "bone", "bone"

  let e2 = parseBool("(heart OR bone) AND NOT lung")
  assert e2.kind == eAnd, "parens make AND outermost"
  assert e2.left.kind == eOr, "left is (heart OR bone)"
  assert e2.right.kind == eNot, "right is NOT lung"
  assert e2.right.inner.kind == eTerm and e2.right.inner.term == "lung", "inner"

  let e3 = parseBool("""heart AND "myasthenia gravis"""")
  assert e3.kind == eAnd, "AND with phrase"
  assert e3.right.kind == ePhrase, "right is a phrase"
  assert e3.right.words == @["myasthenia", "gravis"], "phrase words tokenized"

  echo "  parser precedence + parens hold"

  # --- evaluator ---
  seed(g)
  proc q(query: string): seq[string] = boolSearch(g, "MESH", query)

  assert q("heart") == @["d1", "d2", "d3"], "heart posting"
  assert q("heart AND lung") == @["d1"], "AND"
  assert q("heart OR bone") == @["d1", "d2", "d3"], "OR (union)"
  assert q("heart AND NOT lung") == @["d2", "d3"], "AND NOT"
  assert q("(heart OR bone) AND NOT lung") == @["d2", "d3"], "parens + NOT"
  assert q("heart AND heart") == @["d1", "d2", "d3"], "idempotent AND"
  assert q("bones") == @[], "absent term -> empty"

  # commutativity of AND/OR
  assert q("heart AND lung") == q("lung AND heart"), "AND commutative"
  assert q("heart OR bone") == q("bone OR heart"), "OR commutative"

  # --- phrases ---
  g.set("^BM25", @["myasthenia", "MESH", "p1"], "1")
  g.set("^BM25", @["gravis", "MESH", "p1"], "1")
  g.set("^BMPOS", @["MESH", "p1", "myasthenia"], "7")
  g.set("^BMPOS", @["MESH", "p1", "gravis"], "8")
  g.set("^BM25", @["myasthenia", "MESH", "p2"], "1")
  g.set("^BM25", @["gravis", "MESH", "p2"], "1")
  g.set("^BMPOS", @["MESH", "p2", "myasthenia"], "1")
  g.set("^BMPOS", @["MESH", "p2", "gravis"], "9")
  g.set("^BM25LEN", @["MESH", "p1"], "10")
  g.set("^BM25LEN", @["MESH", "p2"], "10")
  g.set("^BM25DF", @["myasthenia", "MESH"], "2")
  g.set("^BM25DF", @["gravis", "MESH"], "2")

  assert q("myasthenia AND gravis") == @["p1", "p2"], "AND finds both docs"
  let phraseQuery = "\"myasthenia gravis\""
  assert q(phraseQuery) == @["p1"], "phrase: only adjacent p1"

  echo "  evaluator + phrases hold"

  # --- named result sets (bool_sets.dfy mirror) ---
  echo "--- set tests ---"
  # SaveReadIdentity: save then setPosting returns exactly the saved ids.
  saveSet(g, "MESH", "S10", @["d1", "d2"])
  assert setPosting(g, "MESH", "S10") == @["d1", "d2"], "save/read identity"

  # Set operand = term posting: S10 AND lung == {d1}.
  assert boolSearch(g, "MESH", "S10 AND lung") == @["d1"], "set AND term"

  # nextSetName is fresh (never an existing live name).
  let before = listSets(g, "MESH")
  let nxt = nextSetName(g, "MESH")
  for (name, _) in before:
    assert name != nxt, "next name is fresh"
  saveSet(g, "MESH", nxt, @["d1"])
  assert setPosting(g, "MESH", nxt) == @["d1"], "new set saved under fresh name"

  # KillReadEmpty + KillIdempotent.
  killSet(g, "MESH", "S10")
  assert setPosting(g, "MESH", "S10") == @[], "kill/read empty"
  killSet(g, "MESH", "S10")  # idempotent
  assert setPosting(g, "MESH", "S10") == @[], "kill idempotent"

  # SaveIndependent: saving under one name leaves another intact.
  saveSet(g, "MESH", "SA", @["d1"])
  saveSet(g, "MESH", "SB", @["d2", "d3"])
  assert setPosting(g, "MESH", "SA") == @["d1"], "SA intact after SB save"
  assert setPosting(g, "MESH", "SB") == @["d2", "d3"], "SB saved"

  echo "  save/read, kill, freshness, independence hold"
  echo "boolean_engine test passed!"

main()
