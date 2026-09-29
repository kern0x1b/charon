# NSBatchInsertRequest

The batch INSERT of Core Data, which the release does not have. Its delete and update siblings are
in this package — `NSBatchDeleteRequest.m` and `NSBatchUpdateRequest.m`, from the iOS 9.0 backports
— and the insert arrived at iOS 13.0 with nothing carrying it.

**The 6.1.3 cache reads 0 for the class**, beside a control of 2
(`setNaturalLanguageQuery:`), and the whole class is therefore the port's own. The search is
`facts/CoreData/cache-6.1.3.tsv`, which holds all 274 CoreData rows against that cache with the
control: 15 names are present, every one of them a method selector, and not one class.

## What the class is, and where the version comes from

The 16.4 header the port lifts **declares the class** (`NSBatchInsertRequest.h:17`) with an empty
ivar block and **six** properties it has nowhere to keep — `:20 entityName`, `:21 entity`,
`:23 objectsToInsert`, `:24 dictionaryHandler`, `:25 managedObjectHandler`, `:28 resultType`. So the
storage is a class extension in `NSBatchInsertRequest.m` and not a redeclaration in
`CharonCoreData.h`: an ivar block may only appear in a class's one interface, the SDK has it, and a
second `@interface` for this class is a duplicate definition — which is exactly what the shared
header produced before it moved.

The version per row is the **header's** `API_AVAILABLE`, not the corpus's price:
`ios13.json` carries the class and fifteen members at 13.0, and `ios14.json` the two handler
properties at 14.0, because `:24` and `:25` are the two the header gates later than the rest.

## What it does, and the boundary

A batch insert runs **inside the store**: `-executeRequest:` hands the request to the persistent
store coordinator, which is a C function over a store this port does not have. The handlers are
called once per row **by the store**, so with no store they are not called at all. So the class is
the request as a value — the entity, the name, the rows, the handler, the result type — and a
caller that needs its rows written uses the store's own path. A program that reads this should not
expect the rows to appear.

## What the host measured, and the two things the differential found

`tests/backports/host/coredata-batchinsert/per-initializer.m` asks all ten of the header's
initialisers and constructors, each inside `@try`/`@catch` with valid arguments, and prints
`<selector> raised=<0|1> answer=… reason=…`; the two answers, the framework's own and the port's,
are diffed. The reference is `reference-host.tsv`, generated on the host at build time with the
versions it came from in `reference-host.OS.txt` (macOS 27.0, CoreData 120). Nothing is persisted:
`NSInMemoryStoreType`, and no CloudKit.

**`-init` raises and the other nine construct.** Measured:

```
init  raised=1  answer=nil  reason=-init results in undefined behavior for NSBatchInsertRequest
```

so `-init` raises `NSInternalInconsistencyException` with that reason, and the reason is a **string
literal** rather than `NSStringFromClass([self class])`: the port binary renames the class with
`-DNSBatchInsertRequest=CharonBatchInsertRequest`, because it links `-framework CoreData` and the
runtime otherwise answers *"Class NSBatchInsertRequest is implemented in both CoreData and …"*. A
class-name substitution would spell the renamed class where Apple spells `NSBatchInsertRequest`,
which the diff caught as a divergence that was not one.

**`initWithEntity:objects:` sets `entityName`** from the entity's name — the host's answer is
`entityName=Row  entity=Row  objects=2  resultType=0` — and so do the two handler forms with an
entity, which route through it.

**The two handler forms had both handler ivars set.** Each carried three consecutive
`if (self)` blocks, and the first of the three put the handler in the **other** ivar, so a request
built by either had a dictionary handler *and* a managed-object handler and nothing said so. A store
finds two and picks one, and if it picks the other form the rows are never inserted. The listing
could not see it, because it printed one handler key for exactly those two forms; it now prints
**both**, and the defect is red against the old source and green against the fixed one.

## The mutation

`mutant-init.py` replaces the one statement in `-init` that raises, asserts there is exactly one,
and prints the text and its diff. `mutant-init.sh` mutates a **copy** under `.agent-work/runs/`,
touches no tracked file, and **checks the compile's exit code**: a mutant that does not build is a
broken mutant and is reported as a failure, not as a red.
