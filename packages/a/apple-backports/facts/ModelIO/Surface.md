# The ModelIO surface the 26.2 headers declare

## Where every number here comes from

Clang's own JSON AST of the 26.2 headers, read two ways:

- `tools/corpus/surface-diff-latest.py --rows` for the class, method and property lists with the ios
  availability on each node;
- a direct `xcrun clang -ast-dump=json -ast-dump-filter=MDL` for the property accessor shape, because
  `--rows` flattens a property to `Class.name` and drops both `readwrite` and `getter=`.

No header is parsed by regex. The first attempt did, and it invented selectors from macros, attributed
159 members to macOS through a 400-character lookahead that swallowed the next declaration's availability,
and found 114 methods where the headers declare 283.

## The classes and methods

66 classes and 276 methods across five objects, one per release band, so that release-split never sees a
file whose members first appear in more than one release. `MDIO150` was written and had zero
implementations in it; the generator now writes no file for a band with nothing in it.

**The member list is the AST's `ObjCMethodDecl` list, not `nm` on the generated objects.** Building it
from `nm` measures the compiler, not the framework: it offered to carry `-[MDLMesh .cxx_destruct]` and
`-[MDLObject allocator]`, and a body for `.cxx_destruct` would have overridden the ARC helper clang
emits for a C++ class. Seven methods are dropped by an NSObject-basics rule and every rule prints its count,
so a rule matching nothing is visible.

Every emitted selector was checked byte-for-byte against the AST's own selector string: **283 methods, 0
mismatches**. That check is what a comparison against my own output cannot do.

## The accessors

405 rows: **259 getters** and **146 setters**, from 259 properties of which 146 are `readwrite`. The
`readwrite` flag is read from the node, not guessed, because guessing produces a row for a setter clang
never synthesises. `getter=` appears on none of ModelIO's properties, so every getter is the property name.

## Reconciled against the ledger, and a retraction

313 of the ledger's 314 methods are declared in the headers, and the AST adds ten the ledger does not
list — `MDLVertexDescriptor`, `MDLVertexBufferLayout` and `MDLVertexAttribute`, all 9.0 — which are
carried because the headers declare them.

**I reported once that 39 methods disagreed with the ledger on their band. There are no such
disagreements**: 274 shared names, 274 agreeing, 0 differing. The 39 came from comparing against a
larger earlier parse and were miscounted as band conflicts. Nothing was routed, and there is nothing to
route.

## What these rows answer, and what they do not

The answers are the honest empties — nil, NO, 0 — for a machine with no GPU, no asset library and no
provider. `MDLAsset` and `MDLMesh` are built for real on the CPU in the commit after this one; nothing in
these 747 rows claims to be a loaded asset or a computed mesh.

## Owed, and not verified here

The gate's two lists — built without a row, row without a build — have **not** been computed. An earlier
attempt used `nm`, which is wrong: Objective-C methods are not `nm` symbols, only classes are, so it found
10 of 276 and reported 39 rows as unbuilt that are in fact present. A second attempt parsed `otool -ov`,
whose output my pattern matched not at all, so it printed `BUILT WITHOUT A ROW: 0` over a comparison that
had examined nothing. Neither number means anything and neither is claimed. The coordinator's gate closes
the rest in one round.
