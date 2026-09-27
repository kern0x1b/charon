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

`CMTagCollection17.m` carries **23 of the family's 34** functions: the create and copy family, the
description, count, is-empty, the contains family, count-of-category, the three tag getters, the
filter pair, the mutators, add-from-collection and add-from-array, and the type id. The set algebra,
`CopyTagsOfCategories`, `Apply`/`ApplyUntil`, the four serialisation entry points and all fifteen
`CMTaggedBufferGroup` functions are not in it.

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
- **`AddTag(kCMTagInvalid)`** answers `noErr`, not `InvalidTag`: a tag with no data type is accepted
  and carries nothing.
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

## The differential

`tests/backports/host/coremedia7/tagcollectionimage.m` builds the port's file as its own image
(`-dynamiclib`), opens it with `RTLD_LOCAL | RTLD_FIRST` and reaches each of the 23 names through
`dlsym` on that handle, while its own calls reach the host's CoreMedia. Nothing is renamed, no system
header is touched, and `__typeof__(&name)` gives every binding the host's own type. The rule the
differential's first version broke is the one that matters: **a port's collection only ever goes to
the port's own entry points and a host's only to the host's** - handing the port's to the host's makes
CoreMedia interpret the port's object as its own.

**208 checks, 0 different.** The check can fail: replacing `return true` in `ContainsCategory` with
`return NO` gives **208 checks, 4 different**, and restoring it gives 0 again.

## Reuse

Nothing external is taken here. FFmpeg's libavformat/libavcodec and GStreamer are LGPL and were not
read; Media3 and Bento4 were not needed - the hvcC and the CMTag record are parsed from the format
descriptions Apple hands over, and every value is measured against the host's own CoreMedia.
