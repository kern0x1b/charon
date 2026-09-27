# CoreImage's constant names, carried for iOS 6

**156 of the 160** constant rows the ledger lists as missing, measured 2026-09-27: 136 names that are
strings and the 20 `kCIFormat*` that the 16.4 header declares as exported constants.

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

`tests/backports/host/ciimage/constvalues.m` is generated from the ledger's own list of the rows
and references each name **strongly**, so a name the host does not declare is a link error and the
run cannot pass over it; the names that fail to link are the ones the host does not have, and they
are dropped and the run repeated until it links. Every name that links prints the string its own
exported symbol holds. **136 strings carried, 0 differing from the host**, plus the 20 formats, whose values are read the same way. That includes the iOS 11 to 26
names - `kCIDynamicRange*`, `kCIImageContentHeadroom`, the `kCIImageAuxiliary*` and
`kCIImageRepresentation*` families, the iOS 13 and 26 `kCIInput*` - because macOS 27's CoreImage
exports them, and the values are the strings Apple's own symbols hold.

## The four rows that are not carried, and why

`kCIFormatRGB10`, `kCIFormatRGBX16`, `kCIFormatRGBXf` and `kCIFormatRGBXh` arrived in iOS 17.0 and
14.2, and the 16.4 header this port is written against does not declare them, so they are named in
`CIConstants10.m` with their measured values beside them rather than smuggled in under a header that
has not got them. The other twenty are carried as `CIFormat`, with the value each one holds - which
is a four-character code, `kCIFormatA8` being 257, and that is not an enum case: the header declares
each as an exported constant, so an application that names one needs the symbol and iOS 6 does not
export it.

## The control

The same run resolves 136 names to 136 strings, every one of which matches the spelling Apple's own
header gives the key (`kCIInputAngleKey` -> `inputAngle`, `kCISupportedDecoderVersionsKey` ->
`CISupportedDecoderVersions`, `kCIAttributeFilterAvailable_iOS` -> `CIAttributeFilterAvailable_iOS`).
A run that resolved nothing would link nothing and say so.
