# CoreImage's constant names, carried for iOS 6

65 of the 160 constant rows the ledger lists as missing, measured 2026-09-27.

## What these are

The names CoreImage's own filters, contexts and detectors are given their parameters by, and the names
of the metadata attributes a filter is described by. They are `NSString * const`, so each is a pointer
to a constant string: a strong-imported name the release does not export is a dyld failure at launch
for any application that names it, and an application built for a later SDK names dozens of them.

## How each value was read

Not written out by hand. `tests/backports/host/ciimage/constvalues.m` looks each name up in the host's
own CoreImage with `dlsym`, reads the pointer the symbol holds, and prints the string that pointer
names. The registry entry for each row records that run as its source. The control is that the same
run resolves 65 names to 65 distinct strings that match the spelling of the name itself
(`kCIInputAngleKey` -> `inputAngle`, `kCISupportedDecoderVersionsKey` ->
`CISupportedDecoderVersions`, and so on) and that the names the host does not export are reported as
`not exported` rather than skipped.

## What is not here, and why

- **95 of the 160 rows have no value in this pass.** They are the constants of iOS 11 and later -
  `kCIDynamicRange*`, `kCIImageContentHeadroom`, `kCIImageAuxiliarySemanticSegmentation*`, the
  `kCIInput*` of iOS 13 and 26, the `kCIImageRepresentation*` of iOS 12 to 18 - which the host's
  CoreImage of this machine does not export either. Reading them needs a cache of a release that has
  them, read the way `tools/cfconst.py` reads a 64-bit one; that is the next step and it is not
  guessed in the meantime.
- **The 22 `kCIFormat*` rows are not work at all.** They are `CIFormat` enum cases, not exported
  symbols: the 16.4 header declares them as an enum and the lift lowers an enum when the availability
  is lowered, so the header is the whole of them. They appear in the ledger as `missing` only because
  the ledger found no runtime symbol for them, which is what a header-only row looks like.
