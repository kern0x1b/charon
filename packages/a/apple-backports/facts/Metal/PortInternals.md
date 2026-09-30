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

THEY ARE NOT ROWS ANY MORE, and the check this page now feeds is backports.lua:1950, "built, but no
entry in registry/". A CharonMetal object is built by the port, is hidden, and can never appear in any
release inventory - so while a row existed for it, that check was answering about a name the ledger has
no business holding, and the row was doing nothing except stopping the check reporting its seventeen
port-internal neighbours. That is the whole failure: a row that suppressed a diagnostic.

The fix is one line in the unlisted computation at :1867, using release-split.lua:100's own prefix rule -
bare:startswith("charon_") or bare:startswith("Charon") - so a built port-internal object is no longer
reported as an unlisted build, and every OTHER unlisted build still is. The check keeps its teeth: a
non-Charon object that is built and unlisted is still named.

They were also never `ignored`, which means the release carries the name and the port declines to, and no
release ever exported CharonMetalDevice. And they were never `implemented`, which needs a definition the
band EXPORTS, and hidden visibility rules that out however many methods the class has. There was no
status available to these rows, which is the reviewer's point and it is right: an SDK ledger carries SDK
API. The port's answer to "what does the GPU-less case look like" belongs here, in prose a reader can
check, and not in a row whose every field has to be true of a release.

This page is deliberately NOT one of those. It describes port machinery, and it says so in its title.
