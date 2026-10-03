# CIFilter's convenience constructors: the 239 class methods of CIFilterBuiltins.h

iOS 16.0's SDK added a header of its own — `CIFilterBuiltins.h` — that declares, for every built-in filter, a
protocol naming it and a class method on `CIFilter` that takes nothing and answers a filter of that name:
`+ (CIFilter<CISepiaTone*> *) sepiaToneFilter`. Later releases added more of them, and the SDK of 26.2
declares 239. iOS 6 carries none of them: the 6.1.3 armv7 cache's selector table has neither
`sepiaToneFilter` nor `filterWithName:`'s neighbours of that family.

Source: the host's own CoreImage, over every one of the 239, by `tests/backports/host/ciimagefilter`. The test
builds the port's seven objects with their selectors prefixed, links them into one process and asks both
there, so the object compared is the port's own compiled code and not the host's.

## What they are

Each is exactly one call. Measured on the host for all 239:

    compared 478 of 239 port constructors against the host's own, 57 rendered and compared, 0 different

Two comparisons per constructor: the filter the host's `+[CIFilter <selector>]` answers, and the filter the
port's `+charonHost_<selector>` answers. For each pair the class, the `name`, the `inputKeys`, the `outputKeys`
and the whole `attributes` dictionary are equal, and for the 57 whose only declared input is an image the
rendered RGBA bytes over a fixed 32×32 window at the origin are equal too. The window is fixed because a
filter whose output is infinite — every blur — has no extent to render over.

So:

    + (CIFilter *)sepiaToneFilter  { return [CIFilter filterWithName:@"CISepiaTone"]; }

The filter name is not spelled here from a rule. It was read out of the host's own answers, one selector at a
time, by `tests/backports/host/ciimagefilter`'s enumeration of `CIFilter`'s metaclass at run time, and it is
not always the obvious one: `+colorMatrixFilter` answers `CIColorMatrix` and not `CIColorMatrixFilter`, and
`+CMYKHalftone` and `+KMeansFilter` carry no `Filter` at all.

The filter's own arithmetic is the release's, not the port's: `+filterWithName:` is exported from iOS 3.0
(`tools/cache-index/first-rung.py 'filterWithName:'` → 3.0), and it answers nil for a name the running system
has no filter of, which is what Apple documents for a filter that does not exist
(`facts/CoreImage/ImageApplyingFilter.md`). So a constructor for a filter the release does not carry answers
nil, on this port and on a real iOS 16, in the same way.

## Why seven objects and not one

An object carries the API of one release, so the objects are cut by the release each selector itself first
appears at, measured over the 50 held rungs with `tools/cache-index/first-rung.py`:

| object | selectors | the release that exports them |
| --- | --- | --- |
| `CIFilterBuiltins7.m` | 1 | iOS 7.0 |
| `CIFilterBuiltins80.m` | 2 | iOS 8.0 |
| `CIFilterBuiltins841.m` | 1 | iOS 8.4.1 |
| `CIFilterBuiltins11.m` | 1 | iOS 11.0 |
| `CIFilterBuiltins16.m` | 220 | iOS 16.0 |
| `CIFilterBuiltins18.m` | 8 | iOS 18.0 |
| `CIFilterBuiltins26.m` | 6 | no held rung: the ladder ends at 10.3.4, so their SDK availability places them at iOS 26.0 |

`CIFilter` itself is the release's own class from iOS 5.0 (`first-rung.py _OBJC_CLASS_$_CIFilter` → 5.0), so
these are a category on it and not a second definition of it. `charon_collect` installs a category method only
where the class does not answer the selector, so a band at or above the release in the table gets the
release's own constructor and a band below it gets this one; the band needs no `maximum` in the registry for
that, and none is written.

## A caveat on the numbers, and it is not a small one

`release-split.lua` and `check_releases` cannot see any of this: a category's method implementations compile
to no exported symbol, so `nm -gU` on these seven objects reports nothing and both checks read them as empty.
The table above is therefore not what relcheck measured — relcheck measured nothing here — it is
`first-rung.py` over the selectors, and the split by hand is what makes each object single-release *true*
rather than merely unchecked.

The six in the last row are placed by their SDK availability and by nothing else. The SDK of 26.2 writes
`+ (CIFilter<CISystemToneMap*> *) systemToneMapFilter NS_AVAILABLE(16_0, 19_0)` while the corpus records the
row at iOS 26.0; no held rung carries the selector either way, so nothing measurable separates 19.0 from
26.0, and the corpus's number is the one the registry takes.

## What is not here

`CIFilterBuiltins.h` also declares a protocol per filter (`@protocol CISepiaTone <CIFilter>`, 192 of them) and
the input properties of each. Those are not rows of the ledger for this band and are not carried: an
application that adopts a filter protocol names properties on a `CIFilter`, which the release's own
key-value coding already answers for any key the filter declares (`facts/CoreImage/ImageApplyingFilter.md`).