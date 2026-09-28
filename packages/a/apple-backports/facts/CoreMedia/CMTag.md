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
