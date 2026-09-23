# Colour spaces and what CoreGraphics of iOS 6 already has, iOS 7.0 to 15.0

The SDK dates many CoreGraphics names to iOS 7 to 15, among them the named colour spaces,
`CGPathAddRoundedRect`, `CGColorCreateGenericRGB` and the predicates that ask a space what it
is. iOS 6 already exports a good part of them, and measured on it, what it exports and what
it makes of them is the fact this file keeps.

Source: an iPad 2 running 6.1.3 and the iOS 6.0 emulator, which agree on every name, asked with
`dlsym` for each name of the framework's headers and, for each colour space name, with
`CGColorSpaceCreateWithName`; CoreGraphics of the arm64 shared cache of iOS 12.0 for the two
functions it makes different; the host's CoreGraphics for what the release's own functions are held to.

## Named colour spaces

Every `kCGColorSpace...` name the release exports is a string equal to its own name.
`CGColorSpaceCreateWithName` makes a space for three of them only:

| name | exported | `CGColorSpaceCreateWithName` |
| --- | --- | --- |
| `kCGColorSpaceGenericRGB` | yes | a three component RGB space |
| `kCGColorSpaceGenericGray` | yes | a one component gray space |
| `kCGColorSpaceGenericCMYK` | yes | a four component CMYK space |
| `kCGColorSpaceSRGB` | yes | NULL |
| `kCGColorSpaceAdobeRGB1998` | yes | NULL |
| `kCGColorSpaceGenericRGBLinear` | yes | NULL |
| `kCGColorSpaceGenericGrayGamma2_2` | yes | NULL |

Every other name (Display P3, the extended, linear and ITU-R spaces, the HLG and PQ ones,
ACES, DCI P3, ROMM, generic XYZ and Lab) is not exported by the release, and this package carries the constants: each is the string the host's CoreGraphics gives it, an
application that names one loads, and `CGColorSpaceCreateWithName` answers NULL for it, as the release does for `kCGColorSpaceSRGB`.
`CGColorSpaceCreateDeviceRGB` makes a space, and it is what a bitmap that must draw on this release
is made with. A bitmap context made with a space that came back NULL is NULL, and draws nothing.

The names that are exported and answered NULL are the release's own. The names the release does not export were absent at first, on the reasoning that a name with no space behind it is worse than one that
is not there; measured across the applications that name them, a strong reference to a missing constant stops an application before its `main`,
and the header says `CGColorSpaceCreateWithName` may answer NULL, so they are carried, as `kCGColorSpaceGenericLab` was.

## What the release already has

Also exported by the release, and held to the host's CoreGraphics by `tests/backports/device/coregraphics7.m`
on the answers recorded by `host/coregraphics7/refresh.sh`: `CGPathAddRoundedRect` and
`CGPathCreateWithRoundedRect` over every rectangle, corner and transform the test tries,
`CGColorCreateGenericRGB`, `CGColorCreateGenericGray`, `CGColorCreateGenericCMYK`,
`CGColorGetConstantColor` with `kCGColorWhite`, `kCGColorBlack` and `kCGColorClear`,
`CGColorSpaceCopyName`, `CGColorSpaceCopyPropertyList`, `CGColorSpaceCreateWithICCData`,
`CGColorSpaceCreateWithPropertyList`, `CGColorSpaceSupportsOutput`, and the `kCGPDFX...` and
`kCGPDFContextOutputIntent...` keys. The last two groups are exported, and how they behave was
not compared.

## What this package carries

`CGColorSpaceCopyICCData` (10.0): iOS 12 makes `CGColorSpaceCopyICCProfile` a branch to it
(`0x182df02f0` to `0x182df0030`), so the profile of the release answers for it.
`CGColorSpaceUsesExtendedRange` (9.3, the first armv7 cache that exports it; the header says 10.0): iOS 12 reads one flag of the space
(`0x182df0470`), which only the extended spaces set, and the release makes none, so the answer is NO.
`CGColorSpaceIsHDR` (13.0), `CGColorSpaceUsesITUR_2100TF` (14.0), `CGColorSpaceIsHLGBased` and
`CGColorSpaceIsPQBased` (15.0): a space answers YES to them only when it is an HLG, PQ or extended
space, and the release makes none of these, so the answer is NO for every space and for NULL.

`CGColorSpaceIsWideGamutRGB` is absent: iOS 12 reads a flag of the space that is set from its profile
(`0x182df04a8`), and a profile the release is given may well be a wide gamut, so a fixed answer would
be a guess.
