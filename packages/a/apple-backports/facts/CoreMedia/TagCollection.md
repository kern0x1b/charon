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
filter pair, the mutators, add-from-collection and add-from-array, and the type id. **The set algebra, the category filter, the two appliers and the dictionary form are in the tree**,
held by 268 answers with none different, under AddressSanitizer. Three things the extension found, all
in the port:

- **`CMTagCollectionCopyAsDictionary` retained integers on the stack.** `CFDictionaryCreate` retains
  every key and value, and the values were `int` locals, so the release's own `objc_retain` was handed a
  stack address. That was the extension's segfault, and ASan named it:
  `#0 objc_retain`, `#1 CFDictionaryCreate`, `#2 CMTagCollectionCopyAsDictionary`,
  `#3 main tagcollectionimage.m:341`, `SUMMARY: SEGV … in objc_retain`. The values are `CFNumber`s now.
- **`CMTagCollectionCreateMutableCopy` made an empty collection**, discarding the source's tags, which
  is what made a union built on it lose the first collection entirely. The probe had a case for the
  mutable copy and never looked at its contents; it does now.
- **`CMTagCollectionCreateExclusiveOr` stacked the two differences**, which answers two tags where one
  of them is in both. The host answers the **symmetric difference**: a tag in one and not the other,
  counted once. Measured on a one-tag collection against a two-tag one sharing a tag with it, the host
  answers 0 for `Difference` and 1 for `ExclusiveOr`, and the port now agrees.

And two rules the host has that the header does not: a **category count of zero** is
`kCMTagCollectionError_ParamErr` rather than an empty collection, and **`ApplyUntil` takes the filter
function, not the void applier**, and answers the `CMTag` that satisfied the callback.

The mutation: taking the containment test out of `ExclusiveOr`'s second side gives
`268 checks, 3 different` and the suite exits 1; restoring it gives 0.

`CopyAsData` and `CreateFromData` are **measured completely and not yet in the tree**; the drafts are
`CMTagCollection17.binaryform-draft.m` and `tagcollectionimage.binaryform-draft.m`, and the probe they
reach is `.agent-work/runs/tagdata/`.

**The layout**, from the host's own bytes for collections of 0, 1, 2 and 3 tags and every data type:
a 44-byte header and **16 bytes per tag**.

```
uint32  the whole record's length, big endian
char4   "tgco"          - not compared by the host
uint32  20
char4   "tgin"          - not compared by the host
uint32  0              - must be zero
char8   "tag coll"
uint32  16 * (count + 1)
char4   "tgli"          - not compared by the host
uint32  0              - must be zero
uint32  the number of tags
per tag: uint32 the category as four characters, uint32 the data type, uint64 the value
```

The value is a plain big-endian 64-bit field: an `OSType` sits in its low 32 bits (`'vide'` is
`00000000 76696465`), a `Float64` is a big-endian double in all eight (`1.5` is `3ff8000000000000`),
and `0x0102030405060708` survives whole. Every collection round-trips through the host's own reader with
`0`.

**The answers, every one measured** over a whole record, eight truncations of it and each of its eleven
header fields flipped:

| record | host |
| --- | --- |
| shorter than the 44-byte header | `-15740` `kCMTagCollectionError_ParamErr` |
| the length field, the sub-length field, or the 20 | **`-12894`, which no SDK on this machine names** |
| either zero field non-zero | `-15747` `kCMTagCollectionError_InvalidTagCollectionDataVersion` |
| `tag coll` altered, or a count the length does not fit | `-15745` `kCMTagCollectionError_InvalidTagCollectionData` |
| the first byte of `tgco`, `tgin` or `tgli` flipped | **0 — the host does not compare the three magic tags** |

That last row is the one a port gets wrong by being careful: refusing a record whose magic does not match
would refuse records the host reads.

**Where the draft stands: 356 checks, 20 different.** The error map is implemented and reproduces the
table above; two things are not, and I ran out of turn before finding them. The port's own round trip
loses the value (`1835297121/5/0` where the host answers `…/5/1986618469`), and one header-flip case
answers `-15745` where the port says `-12894` - the order of the count check against the length check.
The bytes the port writes are byte-identical to the host's, so the fault is in the reader's offsets or
its check order, not in the layout.

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
