# build_orangebook.nim — load the FDA Orange Book into ^ORANGEBOOK (#462, Phase 2).
#
# The Orange Book ships as three ~-delimited tables (products/patents/exclusivity)
# keyed by (Appl_Type, Appl_No, Product_No). Loads:
#   ^ORANGEBOOK(applType, applNo, product, "ingredient"|"trade"|"strength"
#               |"te_code"|"type") = value
#   ^ORANGEBOOK(applType, applNo, product, "patent", patentNo) = expireDate
#   ^ORANGEBOOK(applType, applNo, product, "exclusivity", code) = date
#
# Each product's ingredient is cross-linked to a MeSH SCR by exact (case-
# insensitive) name via ^SUPPNAME: ^LINK("ORANGEBOOK", productKey, "SUPP",
# scrui) = "ingredient", plus the reverse ^SUPP(scrui,"orangebook",productKey).
#
# Usage: nim c -d:release --path:. -o:bin/build_orangebook \
#          future_search_tool/src/build_orangebook.nim
#        ./bin/build_orangebook <db> <dir>

import os
import sets
import strutils
import tables
import ../../globals

proc productKey*(f: seq[string]): seq[string] =
  # products.txt columns: 0=Ingredient 1=DF;Route 2=Trade_Name 3=Applicant
  # 4=Strength 5=Appl_Type 6=Appl_No 7=Product_No ... 12=Type 13=ApplFullName.
  return @[f[5], f[6], f[7]]  # applType, applNo, productNo

proc productKeyPatent(f: seq[string]): seq[string] =
  # patent.txt / exclusivity.txt columns: 0=Appl_Type 1=Appl_No 2=Product_No ...
  return @[f[0], f[1], f[2]]

proc main() =
  let p = commandLineParams()
  if p.len < 2:
    echo "usage: build_orangebook <db> <dir>"
    quit(1)
  let db = p[0]
  let dir = p[1]

  var g = newGlobals(db)
  var products = 0
  var patents = 0
  var exclusivities = 0
  var ingredients = 0
  var linkedIngredients = 0
  var scrCache = initTable[string, string]()

  # Resolve an ingredient name to a single SCR UI via ^SUPPNAME. Returns ""
  # when zero or multiple SCRs share the name (deterministic, no fuzzy match).
  # Memoized: 48k products share a small ~2k-name ingredient vocabulary, and a
  # per-product $ORDER walk over ^SUPPNAME on a 100GB map is the does-nothing-
  # but-slow path this fixes (#457/#462 batching lesson).
  proc resolveScr(g: var Globals, name: string): string =
    let key = name.toLowerAscii
    if key in scrCache:
      return scrCache[key]
    var uis = g.order("^SUPPNAME", @[key, ""], forward = true)
    let first = uis
    var res = ""
    if first.len > 0 and g.order("^SUPPNAME", @[key, first], forward = true).len == 0:
      res = first
    scrCache[key] = res
    return res

  g.beginWriteBatch()

  # products.txt
  for line in lines(dir & "/products.txt"):
    let f = line.strip(leading = false, trailing = true).split('~')
    if f.len < 14 or f[0] == "Ingredient":
      continue
    let key = productKey(f)
    g.set("^ORANGEBOOK", key & @["ingredient"], f[0])
    g.set("^ORANGEBOOK", key & @["route"], f[1])
    g.set("^ORANGEBOOK", key & @["trade"], f[2])
    g.set("^ORANGEBOOK", key & @["applicant"], f[3])
    g.set("^ORANGEBOOK", key & @["strength"], f[4])
    g.set("^ORANGEBOOK", key & @["te_code"], f[8])
    g.set("^ORANGEBOOK", key & @["approval_date"], f[9])
    g.set("^ORANGEBOOK", key & @["type"], f[12])
    g.set("^ORANGEBOOK", key & @["applicant_full"], f[13])
    inc products
    # ingredient -> SCR exact-name cross-link (many ingredients, one product)
    var seen = initHashSet[string]()
    for ing in f[0].split(';'):
      let s = ing.strip().toLowerAscii
      if s.len == 0 or s in seen:
        continue
      seen.incl(s)
      inc ingredients
      let scrui = resolveScr(g, s)
      if scrui.len > 0:
        # product identity = (applType, applNo, productNo); keep as discrete
        # subscripts in ^LINK so the key framing stays unambiguous (#356 rule).
        g.set("^LINK", @["ORANGEBOOK", key[0], key[1], key[2], "SUPP", scrui], "ingredient")
        g.set("^SUPP", @[scrui, "orangebook", key[0], key[1], key[2]], "1")
        inc linkedIngredients
    if products mod 5000 == 0:
      g.endWriteBatch()
      g.beginWriteBatch()
      stderr.writeLine("  [products] ", products)

  # patent.txt
  for line in lines(dir & "/patent.txt"):
    let f = line.strip(leading = false, trailing = true).split('~')
    if f.len < 4 or f[0] == "Appl_Type":
      continue
    let key = productKeyPatent(f)
    g.set("^ORANGEBOOK", key & @["patent", f[3]], f[4])
    inc patents

  # exclusivity.txt
  for line in lines(dir & "/exclusivity.txt"):
    let f = line.strip(leading = false, trailing = true).split('~')
    if f.len < 5 or f[0] == "Appl_Type":
      continue
    let key = productKeyPatent(f)
    g.set("^ORANGEBOOK", key & @["exclusivity", f[3]], f[4])
    inc exclusivities

  g.endWriteBatch()

  echo "orangebook DONE products=", products,
       " patents=", patents,
       " exclusivities=", exclusivities,
       " ingredients=", ingredients,
       " linked_ingredients=", linkedIngredients
  g.markUpdated("orangebook")
  g.close()

when isMainModule:
  main()
