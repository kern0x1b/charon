# CoreImage's constant names, carried for iOS 6

**136 of the 160** constant rows the ledger lists as missing, measured 2026-09-27: every one of them
except the 24 `kCIFormat*`.

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

## How all 136 were read

`tests/backports/host/ciimage/constvalues.m` is generated from the ledger's own list of the 160 rows
and references each name **strongly**, so a name the host does not declare is a link error and the
run cannot pass over it; the names that fail to link are the ones the host does not have, and they
are dropped and the run repeated until it links. Every name that links prints the string its own
exported symbol holds. **136 carried, 0 differing from the host.** That includes the iOS 11 to 26
names - `kCIDynamicRange*`, `kCIImageContentHeadroom`, the `kCIImageAuxiliary*` and
`kCIImageRepresentation*` families, the iOS 13 and 26 `kCIInput*` - because macOS 27's CoreImage
exports them, and the values are the strings Apple's own symbols hold.

## The 24 rows that are not carried, and why

`kCIFormat*` is **not a string constant**: the header declares it as `const CIFormat`, an `int`, and
the probe's own compile said so - `redeclaration of 'kCIFormatA16' with a different type: 'NSString
*const' vs 'const CIFormat'`. They are enum-shaped header values, the whole of which is the
`CIFormat` enum, and the lift lowers an enum when the availability is lowered. The ledger lists them
as `missing` only because it found no runtime symbol for them, which is what a header-only row looks
like. They are not carried as strings, because a string there would be a value of the wrong type -
and they are not a gap in this pass either, because there is nothing at run time to carry.

## The control

The same run resolves 136 names to 136 strings, every one of which matches the spelling Apple's own
header gives the key (`kCIInputAngleKey` -> `inputAngle`, `kCISupportedDecoderVersionsKey` ->
`CISupportedDecoderVersions`, `kCIAttributeFilterAvailable_iOS` -> `CIAttributeFilterAvailable_iOS`).
A run that resolved nothing would link nothing and say so.
