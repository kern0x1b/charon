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
          "weighted by sinc(x)*sinc(x/a) at each tap's distance from the mapped position and normalised per "
          "phase, with a=3 and Lanczos5 under kvImageHighQualityResampling. The whole of the thirty-six is this "
          "loop over a different pixel layout, so the port is one engine and four release-split files")

EFFECT_TAIL = ("a tap outside the picture along the shear takes the backColor with its weight KEPT rather than "
               "being dropped - a source constant at 1.0 with a backColor of -1 answers 2w-1 and the release "
               "answers -0.000 and 1.223, which are weights and not gaps - and under kvImageEdgeExtend the tap "
               "is pulled back to the edge element instead, which is the header's own \"the edge pixels of the "
               "source are extended\"; neither mode renormalises over the survivors. The mapped position along "
               "the shear is (along0 + along + 0.5 {sign} translate {slope}) / scale - 0.5, where the vertical's "
               "is anchored to the DESTINATION's far edge and the horizontal's to its near edge, and the "
               "shearSlope multiplies the cross coordinate read from the opposite edge - {cross} - so the two "
               "axes are mirrors of one another. Measured on the host's own kernel: at a scale of two on a "
               "twelve-row source the vertical's destination row 0 maps to source row 5.75 and the horizontal's "
               "destination column 0 to -0.25, and the offset is the destination's extent and not the source's "
               "(a twelve-row source into a twenty-row destination offsets by ten, not six). Every channel is "
               "{clamp}. A NULL source or destination is kvImageNullPointerArgument, a NULL filter is "
               "kvImageInvalidParameter, and a region or a destination that does not fit ACROSS the shear - "
               "srcOffsetToROI_X + dest->width > src->width on the vertical, srcOffsetToROI_Y + dest->height > "
               "src->height on the horizontal - is kvImageBufferSizeMismatch, which is also what a destination "
               "wider than the source gets and the only shape condition there is: the destination's extent "
               "along the shear is free, and so is the along offset, which a source nine wide accepts at twelve. "
               "No flag is refused - all thirty-two bits answer kvImageNoError - and kvImageGetTempBufferSize "
               "does no work and answers zero")

FACTS = "facts/Accelerate/vImageGeometry.md"

SOURCE = ("the header of iOS 16.4 (Geometry.h) for the contract, the two position rules and the return codes it "
          "names; the host's own vImage, held against the port case by case and case by case against an "
          "expectation the harness computes in its own loops, by tests/backports/host/shear, whose run.sh builds "
          "the port's objects with the package's own -Os -Wall line because these buffers are declared "
          "VIMAGE_NON_NULL and a NULL test on such a parameter is folded away at -Os; the release's own armv7 "
          "caches, whose first rung placing each name is the `introduced` above, and whose exports are libSystem's "
          "alone for this object (nm -u at armv7-apple-ios4.3), so its floor is 4.3")


def effect(horizontal, translate, clamp):
    sign = "-" if horizontal else "+"
    slope = "+ slope * (cross - dstCross + 0.5)" if horizontal else "+ slope * (cross + 0.5)"
    cross = "cross - dstCross + 0.5" if horizontal else "cross + 0.5"
    return (EFFECT_TAIL.format(sign=sign, slope=slope, cross=cross, clamp=clamp))


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
                "reason": REASON.format(extent="`ceil(a / min(1, scale))`"),
                "effect": effect(horizontal, translate, clamp),
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