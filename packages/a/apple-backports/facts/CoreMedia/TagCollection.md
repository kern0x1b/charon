# `CMTagCollection` on a release whose SDK has no `CMTag`

`CMTag`, `CMTagCollection` and `CMTaggedBufferGroup` arrived at iOS 17. The SDK the toolchain resolves is
16.4, where `ls iPhoneOS16.4.sdk/.../CoreMedia.framework/Headers/ | grep -ci tag` is **0** and
`grep -rl CMTagCollectionCreate` over those headers finds nothing. So the family cannot be written
against that SDK at all: a source file cannot name a type it does not declare.

`CharonCMTag26.h` transcribes 26.2's own declarations under `#if !__has_include(<CoreMedia/CMTag.h>)`,
the way `CharonIntents262.h` and `CharonCKSyncEngine26.h` do: the `CMTagCategory` enum with its real
four-character codes, `CMTagDataType`, `CMTagValue`, the three-word `CMTag` struct, the
`CMTagCollectionError` enum, the filter and applier callbacks, and the three bridged references -
`CMTagCollectionRef` is `const struct CM_BRIDGED_TYPE(id) OpaqueCMTagCollection *`, so the
implementation is an Objective-C class, not a CFType.

## Rule R4 - the names this adds beyond the 16.4 headers

Every name below is declared by no header in the SDK the toolchain resolves
(`iPhoneOS16.4.sdk/.../CoreMedia.framework/Headers/` has no file whose name contains `Tag`), and by
26.2's three. So `share/lift/left-alone.txt` is stale the moment this merges, and both lift sets have
to be re-measured before the push and merged in the same one - the 16.4 set grows by these, the 26.2 set
does not.

**Types and callbacks:** `CMTagCategory`, `CMTagDataType`, `CMTagValue`, `CMTag`, `CMTagCollectionError`, `CMTagCollectionTagFilterFunction`, `CMTagCollectionRef`, `CMMutableTagCollectionRef`, `CMTaggedBufferGroupRef`, `CMTagCollectionApplierFunction`

**Enumeration cases:**  - the whole of
`kCMTagCategory_*` (11), `kCMTagDataType_*` (5) and `kCMTagCollectionError_ParamErr`.

**Functions and constants carried here:** `CMTagCollectionAddTag`, `CMTagCollectionAddTagsFromArray`, `CMTagCollectionAddTagsFromCollection`, `CMTagCollectionContainsCategory`, `CMTagCollectionContainsSpecifiedTags`, `CMTagCollectionContainsTag`, `CMTagCollectionContainsTagsOfCollection`, `CMTagCollectionCopyDescription`, `CMTagCollectionCountTagsWithFilterFunction`, `CMTagCollectionCreate`, `CMTagCollectionCreateCopy`, `CMTagCollectionCreateMutable`, `CMTagCollectionCreateMutableCopy`, `CMTagCollectionGetCount`, `CMTagCollectionGetCountOfCategory`, `CMTagCollectionGetTags`, `CMTagCollectionGetTagsWithCategory`, `CMTagCollectionGetTagsWithFilterFunction`, `CMTagCollectionGetTypeID`, `CMTagCollectionIsEmpty`, `CMTagCollectionRemoveAllTags`, `CMTagCollectionRemoveAllTagsOfCategory`, `CMTagCollectionRemoveTag`, `kCMTagCategoryKey`, `kCMTagDataTypeKey`, `kCMTagInvalid`, `kCMTagValueKey`

The precedent is in the file already: `lift/iPhoneOS16.4.sdk.txt` carries `class __NSConcreteUUID`, the
case `patch-merge` §4 names as "Missed on 2026-09-27 with NSUUID".

`CMTagCollection17.m` carries **23 of the family's 34** functions: the create and copy family, the set algebra (`CreateUnion`, `CreateIntersection`,
`CreateDifference`, `CreateExclusiveOr`), `CopyTagsOfCategories`, `Apply`, `ApplyUntil`,
`CopyAsDictionary` and `CreateFromDictionary`, the
description, count, is-empty, the contains family, count-of-category, the three tag getters, the
filter pair, the mutators, add-from-collection and add-from-array, and the type id. **Written and measured, five of the nine, but not in the tree**: `CreateUnion`, `CreateIntersection`,
`CopyTagsOfCategories`, `Apply`, `ApplyUntil`, `CopyAsDictionary` and `CreateFromDictionary` are written
and the differential agrees with the host on all of them. They are not in the tree, and not in the
registry, because the probe extension that covers them **segfaults** - the extension is kept at
`.agent-work/plan-and-analysis/coremedia-avf/tagcollectionimage.setalgebra-draft.m` - and a function whose
differential does not pass cannot honestly be registered.

What that extension measured, against the host, on a one-tag collection and a two-tag collection:

| operation | host | measured rule |
| --- | --- | --- |
| `CreateUnion` | both collections' tags, each once | the port was returning only the first, and said so |
| `CreateIntersection` | the shared tags | as written |
| `CreateDifference` | **0 tags** where one minus two is 0 | the port kept a tag the subtrahend holds - not understood, and why the pair is the clue is in the probe's `note:` line |
| `CreateExclusiveOr` | **2 tags** and **1 tag** on the two pairs | the port's composition gives 2 and 1, so only the two-tag pair disagrees; not understood either |
| `CopyTagsOfCategories` | a category count of **zero** is `kCMTagCollectionError_ParamErr` | the port answered an empty collection; fixed |
| `Apply` | the collection's order | as written |
| `ApplyUntil` | answers the `CMTag` that satisfied the callback, `kCMTagInvalid` when none did, and takes the **filter** not the void applier | the port had it returning a Boolean; fixed |
| `CopyAsDictionary` | one entry per tag under `tags`, `category`/`value`/`flags` as CFNumbers | as written |
| `CreateFromDictionary` | the collection that shape describes | as written |

So seven of the nine are understood and match; `CreateDifference` and `CreateExclusiveOr` do not, they are
out of the tree, and the host's own answers for them are recorded above and printed by the draft probe
so the next attempt starts from them rather than from a guess.

`CopyAsData` and `CreateFromData` are not written at all, and neither are the fifteen
`CMTaggedBufferGroup` functions. The binary form is Apple's own: a 4-byte big-endian total length, then
the tags `tgco`, `tgin` and `tgli`, the string `tag coll`, a 16-byte sub-length, an element count and
20 bytes per tag. That was measured far enough to describe and not far enough to write, and a guess at it
is what the brief forbids.

## One bug the differential found in the port

`charon_from` bridged the collection with a plain `__bridge` cast, which hands the reference to the
caller **without transferring ownership**: ARC released the collection at the end of the statement and
every later call through it was a use-after-free, which is the `objc_msgSend` fault at address `0x10`
the first probe died on. The reference types are `CF_RETURNS_RETAINED`, so the `+1` belongs to the
caller and `CFRelease` balances it - `__bridge_retained`.

## The rules, each measured on the host

- **The buffer rule.** `noErr` when the caller's buffer was large enough, `kCMTagCollectionError_
  ExhaustedBufferSize` only when tags were left over. For `GetTagsWithCategory` the count that decides
  is the number of tags **of that category**, not of the whole collection: a buffer of 1 against two
  MediaType tags is exhausted, 2 is fine, and 3 is fine and fills two.
- **`ContainsCategory`.** `true` for `kCMTagCategory_Undefined` whatever the collection holds - an
  *empty* collection contains it - and for every other category only when it holds tags of it. Measured
  over empty, one, three, five and six-tag collections and six categories including an unregistered
  `'zzzz'`, which is never contained.
- **`AddTag(kCMTagInvalid)`** answers `noErr`, not `InvalidTag`, and **stores it**: the count goes from
  0 to 1, and the tag sorts first because its category is 0. It is an ordinary tag with no data type.
  An earlier reading of this - "accepted and carries nothing" - came from a probe that checked only the
  status; the differential now checks the count on both sides, which is what caught it.
- **Adding a tag already held is a no-op**, so `AddTagsFromCollection` over a collection that overlaps
  leaves the size unchanged.
- **The description** is `CMTagCollection{`, a newline, one `{category:'<fourcc>' value:<v> <type>}` line
  per tag in the collection's own order, and a closing `}` with nothing after it. Measured byte for
  byte: 58 characters for one tag, ending `3e 7d 0a 7d` - `>`, `}`, newline, `}`. The value is
  `'xxxx'` for `OSType`, `0x…` for flags, plain decimal for `SInt64` and `%.2f` for `Float64`; the
  type names are `OSType`, `flags`, `int64` and `Flt64`; the Undefined category prints as `''`.

## The three serialisation keys, from the host's own symbols

| constant | value |
| --- | --- |
| `kCMTagCategoryKey` | `category` |
| `kCMTagValueKey` | `value` |
| `kCMTagDataTypeKey` | `flags` |

`flags`, not `dataType` - a value guessed from the name would have been wrong.

**How they are held.** Twice, and both bite. Each is compared to the port's own, reached through the
image handle, byte for byte; and each of the **port's** three keys is looked up in a dictionary the
**host** built from a real collection, which is the round trip the registry rows name - a key that differs
from the host's finds nothing there. The first version of that row claimed a round trip no test
performed, and `kCMTagDataTypeKey = "dataType"` still gave `212 checks, 0 different`; it now gives
**215 checks, 1 different**, and the suite exits 1.

## The differential

`tests/backports/host/coremedia7/tagcollectionimage.m` builds the port's file as its own image
(`-dynamiclib`), opens it with `RTLD_LOCAL | RTLD_FIRST` and reaches each of the 23 names through
`dlsym` on that handle, while its own calls reach the host's CoreMedia. Nothing is renamed, no system
header is touched, and `__typeof__(&name)` gives every binding the host's own type. The rule the
differential's first version broke is the one that matters: **a port's collection only ever goes to
the port's own entry points and a host's only to the host's** - handing the port's to the host's makes
CoreMedia interpret the port's object as its own.

**215 checks, 0 different.** The check can fail: replacing `return true` in `ContainsCategory` with
`return NO` gives **208 checks, 4 different**, and restoring it gives 0 again.

## Reuse

Nothing external is taken here. FFmpeg's libavformat/libavcodec and GStreamer are LGPL and were not
read; Media3 and Bento4 were not needed - the hvcC and the CMTag record are parsed from the format
descriptions Apple hands over, and every value is measured against the host's own CoreMedia.
