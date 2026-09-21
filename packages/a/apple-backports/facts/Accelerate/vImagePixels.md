# Four pixel conversions of vImage, iOS 7

Four names the corpus asks for that iOS 6.1.3 does not export: `vImageConvert_RGB565toBGRA8888`,
`vImageConvert_BGRA8888toRGB565`, `vImageConvert_ARGB16UtoRGB16U` and `vImageConvert_ARGBFFFFtoRGBFFF`. iOS 6 has
`vImageConvert_RGB565toARGB8888` and `vImageConvert_ARGB8888toRGB565` from iPhone OS 5 but neither of the BGRA pair,
and neither of the two that drop an alpha channel.

Read from: `Conversion.h` of SDK 16.4, which writes the arithmetic of all four out; the host's own Accelerate, compared
byte for byte in `tests/backports/host/ypcbcr`; the armv7 cache of iOS 6.1.3 for what the release exports.

## The arithmetic

The header gives it exactly, and it is integer arithmetic with no rounding left to choose:

    red   = (5 bit red   * 255 + 15) / 31
    green = (6 bit green * 255 + 31) / 63
    blue  = (5 bit blue  * 255 + 15) / 31

on the way out of a 565 word, and

    red   = (8 bit red   * 31 + 127) / 255
    green = (8 bit green * 63 + 127) / 255
    blue  = (8 bit blue  * 31 + 127) / 255

on the way in, packed as `(red << 11) | (green << 5) | blue` into a word of the machine's own order. A BGRA8888 pixel
is blue, green, red, alpha in that order in memory, and the alpha of a 565 word is the byte the caller passes.
`vImageConvert_ARGB16UtoRGB16U` and `vImageConvert_ARGBFFFFtoRGBFFF` drop the first channel of each pixel and move the
other three down, which the header says works in place, so the port moves rather than copies them.

Unlike the Y'CbCr conversions beside them, these four agree with the system on every byte: the differential's count of
bytes that differ did not move by one when they were added to it. There is no floating point in them to differ in.

## The refusals

They are the system's own, and the differential checks each against it. A destination larger than the source is
`kvImageRoiLargerThanInputBuffer` in all four. The header's own comment above the 565 expansion says
`kvImageBufferSizeMismatch` there; the system does not, and the differential caught the port agreeing with the comment
rather than with the release, so the port answers what the release answers. A flag outside the set the header lists is
`kvImageUnknownFlagsBit`; and `kvImageGetTempBufferSize` does no work and answers zero, as the header says, for the two
that take it.
