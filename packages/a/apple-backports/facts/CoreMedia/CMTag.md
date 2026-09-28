# `CMTag` on a release whose SDK has no `CMTag`

`CMTag` arrived at iOS 17. The SDK the toolchain resolves is 16.4, where
`ls iPhoneOS16.4.sdk/.../CoreMedia.framework/Headers/ | grep -c Tag` is **0**, so the type and all
twenty-five functions that take or return it are transcribed in `CharonCMTag26.h` alongside the tag
collection's. The corpus lists twenty-five functions and forty-eight constants in this header as missing.

This file records the host's answers, measured by `.agent-work/runs/cmtag/measure.m` and
`m2.m` on the host's own CoreMedia, which is what the port has to reproduce.

## The value

`CMTag` is three machine words: a `CMTagCategory` (four characters, `0` for Undefined), a `CMTagDataType`
(0 invalid, 2 SInt64, 3 Float64, 5 OSType, 7 Flags) and a 64-bit value. `CMTagIsValid` is exactly
`dataType != kCMTagDataType_Invalid`, and `kCMTagInvalid` and the "empty" tag — category 0, type 0, value 0 —
are the same thing, hash for hash.

## Make

| call | answer |
| --- | --- |
| `CMTagMakeWithOSTypeValue(cat, 'vide')` | `'vide'` in the value, type OSType |
| `CMTagMakeWithSInt64Value(cat, 7)` | 7 in the value, type SInt64 |
| `CMTagMakeWithFlagsValue(cat, 3)` | 3, type Flags |
| `CMTagMakeWithFloat64Value(cat, 1.5)` | the value's 64 bits, type Float64 — and 0.0 is still type Float64 and still valid |

## Equality and order

`CMTagEqualToTag` is the three fields equal. `CMTagCompare` orders by category, then data type, then
value — `'mdia'`/OSType before `'trak'`/SInt64 gives -1, and the reverse gives 1 — and answers **0 for
an invalid tag against anything**, including another invalid one, so it never returns `kCFCompareEqualTo`
for one. `CMTagCategoryEqualToTagCategory` and `CMTagCategoryValueEqualToValue` are both exactly that
predicate on the pair, per the host's own header. `CMTagHash` is CFHash of the three fields: 930911443662
for the `'vide'` tag, 175247351123 for SInt64 7, and 242338807774 for the invalid tag.

## Has and get

Each `CMTagHas…Value` is `dataType == that type`, so every one of the five the probe asked answered
true for the tag of its own type. The getters **do not check the type**: `CMTagGetOSTypeValue` of an
SInt64 tag is 7 and `CMTagGetSInt64Value` of an OSType tag is 1986618469 — both the same 64-bit value,
read the same way. `CMTagGetValue` is the raw field for every type, and on an invalid tag it is 0.

## The description

`{category:'<four characters>' value:<v> <type>}` — the same shape as the group's and the collection's,
and with the same oddity: the invalid tag's description is `{category:''` with **no closing brace**, its
length measured byte by byte. Values are `'xxxx'` for OSType, `0x…` for Flags, decimal for SInt64 and
`%.2f` for Float64, so 1.5 prints as `1.50`. Type names are `OSType`, `int64`, `flags`, `Flt64`.

## The dictionary

`CMTagCopyAsDictionary` is one entry per tag with three CFNumbers, unsigned: `category` is the four
characters, `flags` is the **data type**, `value` is the value — and for a Float64 tag the value is the
double's **bit pattern in a 64-bit integer** (1.5 → 4609434218613702656), which `CMTagMakeFromDictionary`
turns back into a Float64 tag. That is what makes a float round trip comparable across the two
implementations at all: the comparison is on the bit pattern, so it is exact. An invalid tag's dictionary
is all three keys zero, and it reads back invalid.

`CMTagMakeFromDictionary` on a dictionary that is not one, or with the keys missing, gives an invalid tag.

## The twenty-five rows, read off both headers

`grep -n -E 'CF_EXPORT|CM_INLINE|CF_INLINE'` and `grep -n -E '^CM_INLINE|^CM_EXPORT'` on
`CMTag.h`, in the 26.2 iOS SDK and in the host's macOS SDK. **The two headers are identical** — the same
six inlines at the same line numbers and the same nineteen exports — so the object follows 26.2 and the
host is the oracle for all of them without a single divergence to name.

| name | 26.2 | line | host |
| --- | --- | --- | --- |
| `CMTagIsValid` | `CM_INLINE` | 127 | `CM_INLINE` 127 |
| `CMTagGetValueDataType` | `CM_EXPORT` | 135 | `CM_EXPORT` 135 |
| `CMTagGetCategory` | `CM_INLINE` | 331 | `CM_INLINE` 331 |
| `CMTagCategoryEqualToTagCategory` | `CM_INLINE` | 341 | `CM_INLINE` 341 |
| `CMTagGetValue` | `CM_INLINE` | 350 | `CM_INLINE` 350 |
| `CMTagHasCategory` | `CM_INLINE` | 359 | `CM_INLINE` 359 |
| `CMTagHasSInt64Value` | `CM_EXPORT` | 367 | `CM_EXPORT` 367 |
| `CMTagGetSInt64Value` | `CM_EXPORT` | 376 | `CM_EXPORT` 376 |
| `CMTagHasFloat64Value` | `CM_EXPORT` | 384 | `CM_EXPORT` 384 |
| `CMTagGetFloat64Value` | `CM_EXPORT` | 393 | `CM_EXPORT` 393 |
| `CMTagHasOSTypeValue` | `CM_EXPORT` | 401 | `CM_EXPORT` 401 |
| `CMTagGetOSTypeValue` | `CM_EXPORT` | 410 | `CM_EXPORT` 410 |
| `CMTagHasFlagsValue` | `CM_EXPORT` | 418 | `CM_EXPORT` 418 |
| `CMTagGetFlagsValue` | `CM_EXPORT` | 427 | `CM_EXPORT` 427 |
| `CMTagMakeWithSInt64Value` | `CM_EXPORT` | 439 | `CM_EXPORT` 439 |
| `CMTagMakeWithFloat64Value` | `CM_EXPORT` | 449 | `CM_EXPORT` 449 |
| `CMTagMakeWithOSTypeValue` | `CM_EXPORT` | 459 | `CM_EXPORT` 459 |
| `CMTagMakeWithFlagsValue` | `CM_EXPORT` | 470 | `CM_EXPORT` 470 |
| `CMTagEqualToTag` | `CM_EXPORT` | 486 | `CM_EXPORT` 486 |
| `CMTagCompare` | `CM_EXPORT` | 496 | `CM_EXPORT` 496 |
| `CMTagCategoryValueEqualToValue` | `CM_INLINE` | 506 | `CM_INLINE` 506 |
| `CMTagHash` | `CM_EXPORT` | 514 | `CM_EXPORT` 514 |
| `CMTagCopyDescription` | `CM_EXPORT` | 524 | `CM_EXPORT` 524 |
| `CMTagCopyAsDictionary` | `CM_EXPORT` | 539 | `CM_EXPORT` 539 |
| `CMTagMakeFromDictionary` | `CM_EXPORT` | 550 | `CM_EXPORT` 550 |

The six inlines carry their bodies again at 589, 594, 599, 604, 609 and 614, which is how 26.2 spells an
inline. **The package therefore defines nineteen** of the twenty-five: the six inlines are the header's,
so the object exports nothing for them, the differential cannot and must not compare them, and they need
no registry row.

And a defect this table found in what is committed: `CMTagGetValueDataType` is an **export**, and
`CharonCMTag26.h` was inlining it — so the object was defining **eighteen**, not nineteen. The inline is
removed and the function is defined in the object.


## Two divergences, measured, and one of them is a defect that is fixed

**`CMTagCompare` — fixed.** My first pass returned "equal" whenever either tag was invalid, from reading
two measurements of *two invalid tags*. The host's own matrix over five tags (invalid, a zero category
with no data type, 'mdia' with no data type, the 'vide' tag, and 'trak'/SInt64 7) is a **total order with
validity first**: two invalid tags are equal, an invalid tag is less than a valid one whatever its
category, and beyond that it is category, then data type, then value. `'vide'` against `kCMTagInvalid` is
1, not 0. The differential found it and the implementation follows the matrix.

**`CMTagHash` — open, and a named divergence.** The host's values are about forty bits — 242338807774
for `kCMTagInvalid`, 242339364781 for `'mdia'` with no data type, 930911443662 for the `'vide'` tag,
175247351123 for `'trak'`/SInt64 7 — and the port's is a `CFHash` of the three decimal fields, which for
the `'vide'` tag is 11562196563089929323. The port's is a *consistent* hash: equal tags hash equal and
the measured tags do not collide, and the differential now checks exactly that rather than comparing
the host's mixing to ours. The five samples above are not enough to identify the host's mixing function,
and guessing one would be an invention, so the divergence is recorded here as `-12894` is, and the
values are here for whoever identifies it with a wider sample set.


## What the differential now finds, all three of them mine, none of them fixed

The probe runs to completion — **405 checks, 8 different** — and every difference is a defect in what I
wrote, not in the port's host. The family is therefore not deliverable and nothing is registered.

**1. `CMTagCopyDictionary` handed `CFDictionaryCreate` the addresses of three integers.**
`CFDictionaryCreate` retains every key and value, so it retained the address of a stack slot holding the
tag's own bytes — `objc_retain` on `0x76696480`, the ASCII of the tag. That was the segfault, and
lldb named the frame in one command: `#0 objc_retain`, one frame, no callers, address ASCII. The values
are `CFNumber`s now, built and released here. **Fixed.**

**2. `CMTagCopyDescription` does not reproduce the host's invalid-tag text.** My facts said the
description of an invalid tag has "no closing brace", from reading a truncated print. The host's actual
text is `{category:''{INVALID}` — a literal `{INVALID}` suffix, not a missing brace. Mine emits
`{category:''`. The facts were wrong and so is the code. **Not fixed.**

**3. `CMTagCompare` is still not the host's order.** With validity first — which the five-tag matrix
established — the host ranks a **valid** tag whose category is 0 *above* one whose category is `'mdia'`:
`'mdia'`/OSType against `0`/OSType is 1, where a numeric category comparison says less. So the order is
validity first and then the category, but the Undefined category does not sort first among the valid
ones. I do not have the samples to say what it does sort by, and an ordering guessed from three
comparisons is how `CreateDifference` and the two export inventions happened, so it is not written. **Not
fixed.**

The hash remains open as recorded above: non-linear in every field, one field's low bits changing the
whole answer, which is a string hash, and five samples do not identify it.
