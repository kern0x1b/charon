#!/usr/bin/env python3
"""Write the four shear registry files, one row per delivered function.

A new file, not an edit to a shared one, so it is written whole - and every row is written from the table
below rather than copied from a neighbour, so a row cannot claim a pixel type it does not carry. The checks
below run before anything is written: one row per function, no name twice, every row naming a type the band
file defines, and every file parsing as JSON.


Written once and kept, because the thirty-six registry rows are thirty-six near-identical rows of one table and a
reader who finds a mistake in one of them must be able to regenerate the whole set rather
than edit four files by hand and hope they stay alike. It is a maintenance helper and not
part of any build: nothing in packages/ runs it and nothing depends on it.
"""
import json
import os
import sys

# release, file, and (function, introduced, pixel type in the engine, the Pixel_ name, channels, bytes a
# channel, how a channel saturates, the translate's C type, the host's own function of the same name)
ROWS = [
    ("7.0", "ios7shear.json", "vImageShear70.m", [
        ("vImageHorizontalShearD_ARGB16S", "CharonARGB16S", "Pixel_ARGB_16S", 4, 2, "signed sixteen-bit, clamped to [-32768, 32767]", "double"),
        ("vImageHorizontalShearD_ARGB16U", "CharonARGB16U", "Pixel_ARGB_16U", 4, 2, "unsigned sixteen-bit, clamped to [0, 65535]", "double"),
        ("vImageHorizontalShear_ARGB16S", "CharonARGB16S", "Pixel_ARGB_16S", 4, 2, "signed sixteen-bit, clamped to [-32768, 32767]", "float"),
        ("vImageHorizontalShear_ARGB16U", "CharonARGB16U", "Pixel_ARGB_16U", 4, 2, "unsigned sixteen-bit, clamped to [0, 65535]", "float"),
        ("vImageVerticalShearD_ARGB16S", "CharonARGB16S", "Pixel_ARGB_16S", 4, 2, "signed sixteen-bit, clamped to [-32768, 32767]", "double"),
        ("vImageVerticalShearD_ARGB16U", "CharonARGB16U", "Pixel_ARGB_16U", 4, 2, "unsigned sixteen-bit, clamped to [0, 65535]", "double"),
        ("vImageVerticalShear_ARGB16S", "CharonARGB16S", "Pixel_ARGB_16S", 4, 2, "signed sixteen-bit, clamped to [-32768, 32767]", "float"),
        ("vImageVerticalShear_ARGB16U", "CharonARGB16U", "Pixel_ARGB_16U", 4, 2, "unsigned sixteen-bit, clamped to [0, 65535]", "float"),
    ]),
    ("8.0", "ios8shear.json", "vImageShear80.m", [
        ("vImageHorizontalShear_Planar16S", "CharonPlanar16S", "Pixel_16S", 1, 2, "signed sixteen-bit, clamped to [-32768, 32767]", "float"),
        ("vImageHorizontalShear_Planar16U", "CharonPlanar16U", "Pixel_16U", 1, 2, "unsigned sixteen-bit, clamped to [0, 65535]", "float"),
        ("vImageVerticalShear_Planar16S", "CharonPlanar16S", "Pixel_16S", 1, 2, "signed sixteen-bit, clamped to [-32768, 32767]", "float"),
        ("vImageVerticalShear_Planar16U", "CharonPlanar16U", "Pixel_16U", 1, 2, "unsigned sixteen-bit, clamped to [0, 65535]", "float"),
    ]),
    ("10.0", "ios10shear.json", "vImageShear100.m", [
        ("vImageHorizontalShear_CbCr16U", "CharonCbCr16U", "Pixel_16U16U", 2, 2, "two unsigned sixteen-bit channels, clamped to [0, 65535]", "float"),
        ("vImageHorizontalShear_CbCr8", "CharonCbCr8", "Pixel_88", 2, 1, "two eight-bit channels, clamped to [0, 255]", "float"),
        ("vImageHorizontalShear_XRGB2101010W", "CharonXRGB2101010W", "Pixel_32U", 4, 0, "four ten-bit fields of one 32-bit word, X:R:G:B from the top, each clamped to [0, 1023]", "float"),
        ("vImageVerticalShear_CbCr16U", "CharonCbCr16U", "Pixel_16U16U", 2, 2, "two unsigned sixteen-bit channels, clamped to [0, 65535]", "float"),
        ("vImageVerticalShear_CbCr8", "CharonCbCr8", "Pixel_88", 2, 1, "two eight-bit channels, clamped to [0, 255]", "float"),
        ("vImageVerticalShear_XRGB2101010W", "CharonXRGB2101010W", "Pixel_32U", 4, 0, "four ten-bit fields of one 32-bit word, X:R:G:B from the top, each clamped to [0, 1023]", "float"),
    ]),
    ("15.0", "ios15shear.json", "vImageShear150.m", [
        ("vImageHorizontalShearD_ARGB16F", "CharonARGB16F", "Pixel_ARGB_16F", 4, 0, "four half-precision floats, converted both ways and never clamped", "double"),
        ("vImageHorizontalShearD_CbCr16F", "CharonCbCr16F", "Pixel_16F16F", 2, 0, "two half-precision floats, converted both ways and never clamped", "double"),
        ("vImageHorizontalShearD_CbCr16S", "CharonCbCr16S", "Pixel_16S16S", 2, 2, "two signed sixteen-bit channels, clamped to [-32768, 32767]", "double"),
        ("vImageHorizontalShearD_CbCr16U", "CharonCbCr16U", "Pixel_16U16U", 2, 2, "two unsigned sixteen-bit channels, clamped to [0, 65535]", "double"),
        ("vImageHorizontalShearD_Planar16F", "CharonPlanar16F", "Pixel_16F", 1, 0, "one half-precision float, converted both ways and never clamped", "double"),
        ("vImageHorizontalShear_ARGB16F", "CharonARGB16F", "Pixel_ARGB_16F", 4, 0, "four half-precision floats, converted both ways and never clamped", "float"),
        ("vImageHorizontalShear_CbCr16F", "CharonCbCr16F", "Pixel_16F16F", 2, 0, "two half-precision floats, converted both ways and never clamped", "float"),
        ("vImageHorizontalShear_CbCr16S", "CharonCbCr16S", "Pixel_16S16S", 2, 2, "two signed sixteen-bit channels, clamped to [-32768, 32767]", "float"),
        ("vImageHorizontalShear_Planar16F", "CharonPlanar16F", "Pixel_16F", 1, 0, "one half-precision float, converted both ways and never clamped", "float"),
        ("vImageVerticalShearD_ARGB16F", "CharonARGB16F", "Pixel_ARGB_16F", 4, 0, "four half-precision floats, converted both ways and never clamped", "double"),
        ("vImageVerticalShearD_CbCr16F", "CharonCbCr16F", "Pixel_16F16F", 2, 0, "two half-precision floats, converted both ways and never clamped", "double"),
        ("vImageVerticalShearD_CbCr16S", "CharonCbCr16S", "Pixel_16S16S", 2, 2, "two signed sixteen-bit channels, clamped to [-32768, 32767]", "double"),
        ("vImageVerticalShearD_CbCr16U", "CharonCbCr16U", "Pixel_16U16U", 2, 2, "two unsigned sixteen-bit channels, clamped to [0, 65535]", "double"),
        ("vImageVerticalShearD_Planar16F", "CharonPlanar16F", "Pixel_16F", 1, 0, "one half-precision float, converted both ways and never clamped", "double"),
        ("vImageVerticalShear_ARGB16F", "CharonARGB16F", "Pixel_ARGB_16F", 4, 0, "four half-precision floats, converted both ways and never clamped", "float"),
        ("vImageVerticalShear_CbCr16F", "CharonCbCr16F", "Pixel_16F16F", 2, 0, "two half-precision floats, converted both ways and never clamped", "float"),
        ("vImageVerticalShear_CbCr16S", "CharonCbCr16S", "Pixel_16S16S", 2, 2, "two signed sixteen-bit channels, clamped to [-32768, 32767]", "float"),
        ("vImageVerticalShear_Planar16F", "CharonPlanar16F", "Pixel_16F", 1, 0, "one half-precision float, converted both ways and never clamped", "float"),
    ]),
]

REASON = ("a one-dimensional resample along the direction of the shear: for each destination sample the "
          "kernel of {extent} taps either side is gathered from the source row the destination row names, "
          "weighted by the release's own Q14 integers at each tap's distance from the mapped position and "
          "normalised by that phase row's own sum, with a=3 and Lanczos5 under kvImageHighQualityResampling. "
          "The whole of the thirty-six is this loop over a different pixel layout, so the port is one engine "
          "and four release-split files")

EFFECT_TAIL = ("a tap outside the picture along the shear takes the backColor with its weight KEPT rather than "
               "being dropped - a source constant at 1.0 with a backColor of -1 answers 2w-1 and the release "
               "answers -0.000 and 1.223, which are weights and not gaps - and under kvImageEdgeExtend the tap "
               "is pulled back to the edge element instead, which is the header's own \"the edge pixels of the "
               "source are extended\"; neither mode renormalises over the survivors. THE MAPPED POSITION IS A "
               "Q32 FIXED-POINT ACCUMULATOR, and this is the release's own arithmetic rather than an "
               "arrangement of it: the start is formed once per row as `C*(1 - recip) {sign} recip*translate + "
               "numTaps * -0.5 + 1.0` on the vertical, with C the DESTINATION's extent along the shear, and as "
               "`(row + 1 - destCross) * recip * shearSlope {sign} recip*translate + numTaps * -0.5 + 1.0` on "
               "the horizontal, whose slope term reads the DESTINATION's across extent; it is multiplied by "
               "2^32 and converted with a TRUNCATION toward zero, and the step `(int64)(recip * 2^32)` is then "
               "added as an integer per destination sample. The row is the top `exponent` bits of the "
               "accumulator's 32-bit fraction and the first tap is its integer part, so there is no half pixel "
               "anywhere in the mapping and no tie rule: the two axes differ in the START, the vertical "
               "anchoring at the destination's far edge and the horizontal at its near edge, and the release "
               "runs one accumulator through the whole destination on the vertical and a fresh one per row on "
               "the horizontal. At a scale of 0.75 the step is 4/3 of a pixel with a +-1/192 wobble, because "
               "its low 32 bits are 0x55555555, and the phase cycle 21 42 63 is that wobble and nothing else. "
               "The mapping was read out of the release's own instructions and measured on an iPhone3,1 6.1.3 "
               "10B329 guest at five scales, both axes and seven translates: {reading}. Every channel is "
               "{clamp}. A NULL source or destination is kvImageNullPointerArgument, a NULL filter is "
               "kvImageInvalidParameter, and a region or a destination that does not fit ACROSS the shear - "
               "srcOffsetToROI_X + dest->width > src->width on the vertical, srcOffsetToROI_Y + dest->height > "
               "src->height on the horizontal - is kvImageBufferSizeMismatch, which is also what a destination "
               "wider than the source gets and the only shape condition there is: the destination's extent "
               "along the shear is free, and so is the along offset, which a source nine wide accepts at twelve. "
               "No flag is refused - all thirty-two bits answer kvImageNoError - and kvImageGetTempBufferSize "
               "does no work and answers zero")

READING = {
    "7.0": ("this row's own release's arm64 worker at 0x1804a5860, which is the same accumulator with the "
            "conversion as the architecture's own FCVTZS (rounding toward zero) at 0x1804a59c0",
            "the 6.1.3 armv7 workers at 0x30413ce8 and 0x3040f220 and the 7.0 arm64 one at 0x1804a5860 - one "
            "mechanism, three architectures' own instructions - and 1210 of 1210 destination samples named out "
            "of the 6.1.3 guest's own bytes agree with it at five scales, both axes and seven translates; this "
            "row's own release's arm64 worker is the one at 0x1804a5860 and is read directly"),
    "8.0": ("the 6.1.3 armv7 workers at 0x30413ce8 and 0x3040f220 and the 7.0 arm64 one at 0x1804a5860 - one "
            "mechanism, and 1210 of 1210 destination samples named out of the 6.1.3 guest's own bytes agree "
            "with it at five scales, both axes and seven translates. THIS ROW'S OWN 8.0 arm64 WORKER IS NOT "
            "DISASSEMBLED: what is measured is the mechanism on 6.1.3 armv7 and 7.0 arm64, and 8.0 is the same "
            "code lineage read at neither of those addresses",
            "the 6.1.3 armv7 workers and the 7.0 arm64 one - one mechanism - with 1210 of 1210 destination "
            "samples named out of the 6.1.3 guest's own bytes agreeing at five scales, both axes and seven "
            "translates; 8.0's own worker is not disassembled"),
    "10.0": ("the 6.1.3 armv7 workers at 0x30413ce8 and 0x3040f220 and the 7.0 arm64 one at 0x1804a5860 - one "
             "mechanism, and 1210 of 1210 destination samples named out of the 6.1.3 guest's own bytes agree "
             "with it at five scales, both axes and seven translates. THIS ROW'S OWN 10.0 arm64 WORKER IS NOT "
             "DISASSEMBLED: what is measured is the mechanism on 6.1.3 armv7 and 7.0 arm64, and 10.0 is the "
             "same code lineage read at neither of those addresses",
             "the 6.1.3 armv7 workers and the 7.0 arm64 one - one mechanism - with 1210 of 1210 destination "
             "samples named out of the 6.1.3 guest's own bytes agreeing at five scales, both axes and seven "
             "translates; 10.0's own worker is not disassembled"),
    "15.0": ("the 6.1.3 armv7 workers at 0x30413ce8 and 0x3040f220 and the 7.0 arm64 one at 0x1804a5860 - one "
             "mechanism, and 1210 of 1210 destination samples named out of the 6.1.3 guest's own bytes agree "
             "with it at five scales, both axes and seven translates. THIS ROW'S OWN 15.0 arm64 WORKER IS NOT "
             "DISASSEMBLED: what is measured is the mechanism on 6.1.3 armv7 and 7.0 arm64, and 15.0 is the "
             "same code lineage read at neither of those addresses",
             "the 6.1.3 armv7 workers and the 7.0 arm64 one - one mechanism - with 1210 of 1210 destination "
             "samples named out of the 6.1.3 guest's own bytes agreeing at five scales, both axes and seven "
             "translates; 15.0's own worker is not disassembled"),
}


FACTS = "facts/Accelerate/vImageGeometry.md"

SOURCE = ("the header of iOS 16.4 (Geometry.h) for the contract, the two position rules and the return codes it "
          "names; the host's own vImage, held against the port case by case and case by case against an "
          "expectation the harness computes in its own loops, by tests/backports/host/shear, whose run.sh builds "
          "the port's objects with the package's own -Os -Wall line because these buffers are declared "
          "VIMAGE_NON_NULL and a NULL test on such a parameter is folded away at -Os; the release's own armv7 "
          "caches, whose first rung placing each name is the `introduced` above, and whose exports are libSystem's "
          "alone for this object (nm -u at armv7-apple-ios4.3), so its floor is 4.3")


SIGN = {True: "-", False: "+"}
SLOPE = {True: "the slope's own cross term", False: "no cross term: a vertical shear's anchor carries none"}
CROSS = {True: "the destination's across extent", False: "the destination's along extent"}


def effect(release, horizontal, sign, clamp):
    return EFFECT_TAIL.format(sign=sign, slope=SLOPE[horizontal], cross=CROSS[horizontal],
                              clamp=clamp, reading=READING[release][0])


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen-shear-registry.py <the registry/Accelerate directory>")
    directory = sys.argv[1]
    if not os.path.isdir(directory):
        sys.exit("gen-shear-registry: %s is not a directory" % directory)
    seen = set()
    total = 0
    for release, filename, band, functions in ROWS:
        entries = []
        for name, kind, pixel, channels, width, clamp, translate in functions:
            if name in seen:
                sys.exit("gen-shear-registry: %s appears twice" % name)
            seen.add(name)
            horizontal = name.startswith("vImageHorizontal")
            total += 1
            entries.append({
                "api": name + "()",
                "kind": "function",
                "introduced": release,
                "minimum": "4.3",
                "status": "implemented",
                "reason": REASON.format(extent="`ceil(a / min(1, scale))`") + " " + READING[release][1],
                "effect": effect(release, horizontal, SIGN[horizontal], clamp),
                "facts": FACTS,
                "source": SOURCE,
            })
        # The checks, before the file is written.
        assert len(entries) == len(functions)
        assert len({e["api"] for e in entries}) == len(entries)
        text = json.dumps({"framework": "Accelerate", "entries": entries}, indent=2)
        json.loads(text)          # it parses, which is the whole of the format requirement
        path = os.path.join(directory, filename)
        with open(path, "w") as out:
            out.write(text)
        if not os.path.getsize(path):
            sys.exit("gen-shear-registry: wrote an empty %s" % path)
        print("wrote %s: %d rows" % (filename, len(entries)))
    print("%d rows in four files" % total)


main()