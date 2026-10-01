# The CharonMetal objects, which are the port's and not Apple's

Across the SDK ledger there were 23 rows whose api was a `Charon`-prefixed name, and they were not
confined to one file:

  Metal/ios80classes.json            16   the object model below
  Metal/ios120classes.json            1   CharonMetalEventState
  Metal/ios10heap.json                1   CharonMetalHeap
  Metal/ios12sharedevent.json         1   CharonMetalSharedEvent
  UIKit/ios17-18.json                 1   CharonEdgeList
  Foundation/nz-private-classes.json  3   CharonPersonNameParts, CharonPresentationIntentState,
                                           CharonTermOfAddressState

The count in this family's commit subjects moved as the question got sharper - 16, then 19, then 23 -
with no commit saying why, so here it is for a reader counting subjects rather than rows:

  16  the Charon-prefixed rows in Metal/ios80classes.json, which is where I started looking
  19  the CharonMetal-PREFIXED rows across the Metal files, adding CharonMetalEventState,
      CharonMetalHeap and CharonMetalSharedEvent from three files I had not opened
  23  the Charon-prefixed rows across the WHOLE registry, adding CharonEdgeList in
      UIKit/ios17-18.json and three in Foundation/nz-private-classes.json

Each was true of its own set and none was a miscount; using one number for all three was the error. The
23 over six files is the form worth having, because it says the pattern was never confined to one
registry.

## What they are

Stand-ins for the `MTL` types. The port needs an object to hand back where an application asks Metal
for a device, a buffer or a command queue, and on a release with no GPU to ask, these are what it
hands back. Each is an `@implementation` in `packages/a/apple-backports/Metal/`, and each answers: a
device that reports a registry ID and a name, a buffer with a length, a queue that runs what it is
given.

## Why the rows exist, which is not what they look like

A row here is the PLACEMENT RECORD for every band that carries the object, whatever its status claims.
backports.lua:2014 is the whole of it:

    local entry = entry_of(listed, name)
    local minimum = entry.minimum or ""

`minimums()` reads `entry_of` and takes `entry.minimum` for every name an object carries, and it never
reads `entry.status`. `in_range()` likewise reads only `minimum` and `maximum`. So the status on these
rows says nothing to the band checker - `absent` is a claim about the RELEASE - and the minimum is what
actually places the object.

That is why deleting them looked clean and was not. Five objects every band carries read their minimum
from these rows - CharonMetalLibrary.o, MTLBlitCommandEncoder10.o, MTLHeap11.o, MTLHeap13.o,
MTLSharedEvent15.o - and with the rows gone the 4.3 band cannot place or link them while 6.1.3 stays
green, because everything those five name is also carried at 6.0. **A row that looks like a redundant API
entry may be the only record of when a symbol becomes linkable.** This paragraph is here so the next band
does not "tidy" these the way this one nearly did.

## The one-line rule in backports.lua, and its empty set

That rule - `bare:startswith("charon_") or bare:startswith("Charon")` on the unlisted computation, taken
from release-split.lua:100 - guards a DIFFERENT set from these rows, and that set is presently EMPTY.
There are 342 `Charon*` classes in the tree and 23 rows; the other 319 never appear as unlisted builds
because `-fvisibility=` keeps them out of the export list the check reads, so the rule cannot fire for
them. It is insurance for the day someone drops `-fvisibility=` on one object, which is the honest
description of a guard whose triggering set is nil today - and it keeps its teeth, since it is an extra
conjunct on the existing condition and every other unlisted build is still named.

## Why the ledger says nothing about them

Three separate facts, each checkable:

1. **No SDK header declares any of them.** They are not in `Metal.framework`'s headers, and
   `grep -c CharonMetalDevice coordination/corpus/sdk-26.2-surface.tsv` returns **0**.
2. **The band exports nothing under these names.** They are compiled with hidden visibility -
   `packages/a/apple-backports/xmake.lua:15` sets the package's `-fvisibility=` - so they do not appear
   in the dylib's export list. This is why no row can say `implemented`: that status means the port
   defines the name *and* the band exports it, and a hidden class cannot reach it however many methods
   it defines. `CharonMetalDevice` defines 32 of them, `CharonMetalQueue` 20, `CharonMetalBuffer` 18, and
   the gate still answers "nothing of that name is built" for every one, because it asks the band.
3. **There is no Apple implementation to read.** No dyld cache holds a `CharonMetalDevice`, so there is
   no branch structure, no constant and no return value to port. What these objects answer is the port's
   own model of the GPU-less case, and a row in an SDK ledger has no business claiming to describe it.

THE ROWS CAME BACK, and the reason is the best thing in this page. Deleting them fixed a real
diagnostic and broke the 4.3 band in the same commit, and the second failure is the one that matters:
backports.lua:2014 `minimums()` reads `entry_of(listed, name)` and takes `entry.minimum` for every name
an object carries - and it never reads `entry.status`. So a row whose api is a port-internal name is
perfectly legal, and its minimum is the only thing it is read for.

Five objects every band carries depend on exactly that:

  CharonMetalLibrary.o        names _CharonAttributesFromFunction  -> CharonMetalLibrary      minimum 6.0
  MTLBlitCommandEncoder10.o   names _OBJC_CLASS_$_CharonMetalSharedEvent -> CharonMetalSharedEvent minimum 6.0
  MTLHeap11.o, MTLHeap13.o    name  _OBJC_CLASS_$_CharonMetalHeap   -> CharonMetalHeap          minimum 6.0
  MTLSharedEvent15.o          names _OBJC_CLASS_$_CharonMetalSharedEvent

Without the rows the 4.3 band has no minimum for those five, cannot place them, and cannot link - while
6.1.3 stays GREEN, because everything they name is also carried at 6.0. A band-placement defect is
invisible at the higher rung. That is why both bands run.

So the rows are load-bearing and what made them look like noise is that they read like API. The status
they carry is absent, and it has to be: implemented needs a definition the band EXPORTS and hidden
visibility rules that out, ignored means the release carries the name and it never did, and owed is not
a landing state. absent plus a minimum is the only shape that satisfies minimums() and the registry test
at once.

THE ONE-LINE RULE IN backports.lua STAYS, because it guards a different set: the port objects that have
no row at all. A built Charon-prefixed object with no row is not API of any release and should not be
reported as an unlisted build; every other unlisted build still is, since the guard is an extra conjunct
on the existing condition.

This page is deliberately NOT one of those. It describes port machinery, and it says so in its title.

## The sixteen rows, measured one name at a time (2026-10-02)

Every row of `registry/Metal/ios80classes.json` cited the same command with the same name in it:

    grep -c CharonMetalDevice coordination/corpus/sdk-26.2-surface.tsv is 0

which is a measurement of `CharonMetalDevice`, on fifteen rows about other names. A zero is the answer
for all sixteen, so the conclusion was right and the evidence was not this row's. Each row now names its
own:

    grep -c 'CharonMetalTexture' coordination/corpus/sdk-26.2-surface.tsv

and the CONTROL is in the same run, because a reader who cannot see that the file is being read at all
cannot tell a real zero from a blind one. The same run over the same 145302 rows finds

    2606 rows naming MTL

and zero naming any `CharonMetal`. The `absent` is therefore the surface's, not the reader's.

The method counts were wrong for eight of the sixteen as well, and the correction is what each row now
says - "N method definitions, at FILE (n), FILE (n)", counted from the source over the class's own
`@implementation` and every category written on it, so the reader's command is the one the number came
from:

| row | before | after | where |
| --- | --- | --- | --- |
| CharonMetalBlitEncoder | 4 | 24 | MTLBlitCommandEncoder8.m (14), :9 (2), :10 (2), :12 (4), :13 (2) |
| CharonMetalBuffer | 18 | 18 | CharonMetalBuffer.m |
| CharonMetalCommandBuffer | 20 | 17 | CharonMetalQueue.m |
| CharonMetalComputeEncoder | 11 | 11 | MTLComputeCommandEncoder8.m |
| CharonMetalComputePipeline | 12 | 12 | MTLComputePipeline8.m |
| CharonMetalDepthStencil | 3 | 3 | CharonMetalDepthStencil.m |
| CharonMetalDevice | 33 | 36 | CharonMetalDevice.m (33), MTLHeap10.m (1), MTLSharedEvent12.m (2) |
| CharonMetalDrawable | 10 | 9 | CharonMetalDrawable.m |
| CharonMetalEncoder | 32 | 36 | CharonMetalEncoder.m (32), MTLHeap11.m (2), MTLHeap13.m (2) |
| CharonMetalFunction | 23 | 17 | CharonMetalLibrary.m |
| CharonMetalLayerState | 10 | 1 | CharonMetalDrawable.m |
| CharonMetalLibrary | 23 | 6 | CharonMetalLibrary.m |
| CharonMetalPipeline | 11 | 11 | CharonMetalPipeline.m |
| CharonMetalQueue | 20 | 3 | CharonMetalQueue.m |
| CharonMetalSampler | 53 | 8 | CharonMetalTexture.m |
| CharonMetalTexture | 53 | 45 | CharonMetalTexture.m |

Nothing else moved: status stays `absent` on all sixteen, and api, kind, introduced, minimum, source and
facts are byte-identical to the base revision. `minimum` is the field `minimums()` reads and never
`status`, so it is the placement record for both bands and is not this band's to touch.

`CharonMetalLayerState` is the row where the two counts differ most and it is worth reading: the class
is one method in `CharonMetalDrawable.m`, and the row that claimed ten was counting a neighbour's. That
is the whole failure this section records - a count that belongs to another object, next to a conclusion
that happens to be true.
