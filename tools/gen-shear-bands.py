#!/usr/bin/env python3
"""Write the four shear band files from one table, so the thirty-six wrappers cannot drift apart.

Every function is the same five lines over a different pixel type, a different translate's type and a
different release; the four files differ only in which releases they carry, because an object may hold the API
of exactly one release (tools/release-split.lua measures that from the held caches' export trie's first rung,
and the registry's `introduced` is what it reads for a name no cache places).

The script asserts the shape of what it is about to write - the number of functions per file, and that every
name in the table appears exactly once in the output - and refuses to write a file it has not checked.


Written once and kept, because the four band files are thirty-six near-identical rows of one table and a
reader who finds a mistake in one of them must be able to regenerate the whole set rather
than edit four files by hand and hope they stay alike. It is a maintenance helper and not
part of any build: nothing in packages/ runs it and nothing depends on it.
"""
import os
import re
import sys

# release, file, and the functions it carries.
#   name                     type              translate    back reader              channels
ROWS = [
    ("7.0", "vImageShear70.m", [
        ("vImageHorizontalShearD_ARGB16S", "CharonARGB16S", "double", "CharonShearBackS16(back, backColor, 4);"),
        ("vImageHorizontalShearD_ARGB16U", "CharonARGB16U", "double", "CharonShearBackU16(back, backColor, 4);"),
        ("vImageHorizontalShear_ARGB16S", "CharonARGB16S", "float", "CharonShearBackS16(back, backColor, 4);"),
        ("vImageHorizontalShear_ARGB16U", "CharonARGB16U", "float", "CharonShearBackU16(back, backColor, 4);"),
        ("vImageVerticalShearD_ARGB16S", "CharonARGB16S", "double", "CharonShearBackS16(back, backColor, 4);"),
        ("vImageVerticalShearD_ARGB16U", "CharonARGB16U", "double", "CharonShearBackU16(back, backColor, 4);"),
        ("vImageVerticalShear_ARGB16S", "CharonARGB16S", "float", "CharonShearBackS16(back, backColor, 4);"),
        ("vImageVerticalShear_ARGB16U", "CharonARGB16U", "float", "CharonShearBackU16(back, backColor, 4);"),
    ]),
    ("8.0", "vImageShear80.m", [
        ("vImageHorizontalShear_Planar16S", "CharonPlanar16S", "float", "CharonShearBackS16(back, &backColor, 1);"),
        ("vImageHorizontalShear_Planar16U", "CharonPlanar16U", "float", "CharonShearBackU16(back, &backColor, 1);"),
        ("vImageVerticalShear_Planar16S", "CharonPlanar16S", "float", "CharonShearBackS16(back, &backColor, 1);"),
        ("vImageVerticalShear_Planar16U", "CharonPlanar16U", "float", "CharonShearBackU16(back, &backColor, 1);"),
    ]),
    ("10.0", "vImageShear100.m", [
        ("vImageHorizontalShear_CbCr16U", "CharonCbCr16U", "float", "CharonShearBackU16(back, backColor, 2);"),
        ("vImageHorizontalShear_CbCr8", "CharonCbCr8", "float", "CharonShearBackU8(back, backColor, 2);"),
        ("vImageHorizontalShear_XRGB2101010W", "CharonXRGB2101010W", "float", "XRGB"),
        ("vImageVerticalShear_CbCr16U", "CharonCbCr16U", "float", "CharonShearBackU16(back, backColor, 2);"),
        ("vImageVerticalShear_CbCr8", "CharonCbCr8", "float", "CharonShearBackU8(back, backColor, 2);"),
        ("vImageVerticalShear_XRGB2101010W", "CharonXRGB2101010W", "float", "XRGB"),
    ]),
    ("15.0", "vImageShear150.m", [
        ("vImageHorizontalShearD_ARGB16F", "CharonARGB16F", "double", "CharonShearBackF16(back, backColor, 4);"),
        ("vImageHorizontalShearD_CbCr16F", "CharonCbCr16F", "double", "CharonShearBackF16(back, backColor, 2);"),
        ("vImageHorizontalShearD_CbCr16S", "CharonCbCr16S", "double", "CharonShearBackS16(back, backColor, 2);"),
        ("vImageHorizontalShearD_CbCr16U", "CharonCbCr16U", "double", "CharonShearBackU16(back, backColor, 2);"),
        ("vImageHorizontalShearD_Planar16F", "CharonPlanar16F", "double", "CharonShearBackF16(back, &backColor, 1);"),
        ("vImageHorizontalShear_ARGB16F", "CharonARGB16F", "float", "CharonShearBackF16(back, backColor, 4);"),
        ("vImageHorizontalShear_CbCr16F", "CharonCbCr16F", "float", "CharonShearBackF16(back, backColor, 2);"),
        ("vImageHorizontalShear_CbCr16S", "CharonCbCr16S", "float", "CharonShearBackS16(back, backColor, 2);"),
        ("vImageHorizontalShear_Planar16F", "CharonPlanar16F", "float", "CharonShearBackF16(back, &backColor, 1);"),
        ("vImageVerticalShearD_ARGB16F", "CharonARGB16F", "double", "CharonShearBackF16(back, backColor, 4);"),
        ("vImageVerticalShearD_CbCr16F", "CharonCbCr16F", "double", "CharonShearBackF16(back, backColor, 2);"),
        ("vImageVerticalShearD_CbCr16S", "CharonCbCr16S", "double", "CharonShearBackS16(back, backColor, 2);"),
        ("vImageVerticalShearD_CbCr16U", "CharonCbCr16U", "double", "CharonShearBackU16(back, backColor, 2);"),
        ("vImageVerticalShearD_Planar16F", "CharonPlanar16F", "double", "CharonShearBackF16(back, &backColor, 1);"),
        ("vImageVerticalShear_ARGB16F", "CharonARGB16F", "float", "CharonShearBackF16(back, backColor, 4);"),
        ("vImageVerticalShear_CbCr16F", "CharonCbCr16F", "float", "CharonShearBackF16(back, backColor, 2);"),
        ("vImageVerticalShear_CbCr16S", "CharonCbCr16S", "float", "CharonShearBackS16(back, backColor, 2);"),
        ("vImageVerticalShear_Planar16F", "CharonPlanar16F", "float", "CharonShearBackF16(back, &backColor, 1);"),
    ]),
]

# The pixel type each function's `Pixel_*` parameter is, and the translate parameter's own name.
PIXEL = {
    "CharonARGB16U": "Pixel_ARGB_16U", "CharonARGB16S": "Pixel_ARGB_16S", "CharonARGB16F": "Pixel_ARGB_16F",
    "CharonPlanar16U": "Pixel_16U", "CharonPlanar16S": "Pixel_16S", "CharonPlanar16F": "Pixel_16F",
    "CharonCbCr8": "Pixel_88", "CharonCbCr16U": "Pixel_16U16U", "CharonCbCr16S": "Pixel_16S16S",
    "CharonXRGB2101010W": "Pixel_32U", "CharonCbCr16F": "Pixel_16F16F",
}

HEADER = """// The shears of vImage at {release}, over the mapping CharonShear.h carries: {count} functions, every one
// of them the same two lines of arithmetic over a different pixel type and a different translate's type, and
// the refusals and the two position rules measured rather than assumed (facts/Accelerate/vImageGeometry.md).
//
// One release per object, which is what the band machinery wants: this file's names are all first exported by
// the {release} caches and none of them by an earlier one, so it enters the build there and not below.

#import <Accelerate/Accelerate.h>
#include "CharonShear.h"
"""

BODY = """
vImage_Error {name}(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount srcOffsetToROI_X,
                   vImagePixelCount srcOffsetToROI_Y, {translate} {axis}Translate, {translate} shearSlope,
                   ResamplingFilter filter, const {pixel} backColor, vImage_Flags flags)
{{
    // The caller's own filter, read: `ours` is zeroed and the read refused for anything that is not one of
    // the two measured shapes, and CharonShearReady turns that into kvImageInvalidParameter - AFTER the
    // NULL-buffer refusal, which is the order the release makes them in.
    CharonResampleFilter ours;
    int have = CharonResampleFilterOf(filter, &ours);
    vImage_Error ready = CharonShearReady(src, dest, have ? &ours : 0, {axis_flag}, srcOffsetToROI_X, srcOffsetToROI_Y);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = {{ 0, 0, 0, 0 }};
    {back}
    return CharonShearRun(src, dest, &ours, {type}, {yes_no}, {axis}Translate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}}
"""

XRGB_BACK = """uint32_t word = backColor;
    for (unsigned channel = 0; channel < 4; channel++)
        back[channel] = (double)((word >> (channel * 10)) & 0x3FFu);"""


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen-shear-bands.py <the Accelerate directory>")
    directory = sys.argv[1]
    if not os.path.isdir(directory):
        sys.exit("gen-shear-bands: %s is not a directory" % directory)
    total = 0
    for release, filename, functions in ROWS:
        text = HEADER.format(release=release, count=len(functions))
        for name, kind, translate, back in functions:
            horizontal = name.startswith("vImageHorizontal")
            axis = "horizontal" if horizontal else "vertical"
            body = XRGB_BACK if back == "XRGB" else back
            text += BODY.format(name=name, translate=translate, axis=axis, pixel=PIXEL[kind], type=kind,
                                yes_no="1" if horizontal else "0", axis_flag="1" if horizontal else "0", back=body)
        # The three checks, before the file is written and not after.
        assert len(functions) == len(set(f[0] for f in functions)), \
            "%s repeats a function name" % filename
        for name, _, _, _ in functions:
            assert text.count("vImage_Error " + name + "(") == 1, \
                "%s: %s is not defined exactly once" % (filename, name)
            assert text.count(name + "(") == 1, \
                "%s: %s appears somewhere other than its own definition" % (filename, name)
        assert "pragma clang diagnostic" not in text, "%s carries a pragma" % filename
        # One definition per row, counted on the definition line and not on the token: `vImage_Error` also
        # appears on each function's own `vImage_Error ready = ...` line.
        assert len(re.findall(r"^vImage_Error vImage", text, re.M)) == len(functions), \
            "%s: %d definitions for %d functions" % (filename, len(re.findall(r"^vImage_Error vImage", text, re.M)), len(functions))
        assert text.count("charon_half_to_float") == 0
        path = os.path.join(directory, filename)
        if not text.endswith("\n"):
            text += "\n"
        with open(path, "w") as out:
            out.write(text)
        if not os.path.getsize(path):
            sys.exit("gen-shear-bands: wrote an empty %s" % path)
        total += len(functions)
        print("wrote %s: %d functions" % (filename, len(functions)))
    print("%d functions in four files" % total)


main()