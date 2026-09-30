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

Sixteen of the twenty-three were in one file, which is what made the earlier count of "nineteen rows
name a CharonMetal-prefixed class" wrong twice over: nineteen is right for the CharonMetal prefix across
the Metal files, and sixteen is right for the file that held most of them. All of them are gone from the
ledger now, and this page is what a reader has instead.

They were the port's own. One page says so for all of them because it is one fact about all of them,
and rows that each pointed at a page about something else would have been claims to look somewhere that
does not answer them.

## What they are

Stand-ins for the `MTL` types. The port needs an object to hand back where an application asks Metal
for a device, a buffer or a command queue, and on a release with no GPU to ask, these are what it
hands back. Each is an `@implementation` in `packages/a/apple-backports/Metal/`, and each answers: a
device that reports a registry ID and a name, a buffer with a length, a queue that runs what it is
given.

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
