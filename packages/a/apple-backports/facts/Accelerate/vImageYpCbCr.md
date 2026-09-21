# The 420 Y'CbCr conversions of vImage, iOS 8

iOS 8 made vImage's Y'CbCr conversions public. A program that names them and runs on iOS 6 does not start: the imports
are strong, and dyld stops at load. The armv7 cache of iOS 6.1.3 exports 235 `vImage` names against the 580 of iOS
12.0, and not one `kvImage` matrix among them, so the matrices and the conversions this file carries are the port's own
arithmetic over buffers, not a call into the release.

Read from: the arm64 shared cache of iOS 12.0, where each matrix's exported pointer was followed and its floats read;
`Conversion.h` and `vImage_Types.h` of SDK 16.4, which write the per-pixel arithmetic of every one of these conversions
out in full; the host's own Accelerate, dumped for the layout of the opaque structures and compared against this file
byte for byte in `tests/backports/host/ypcbcr`.

## The matrices

Four constants, each a pointer to a small struct of floats:

| constant | coefficients |
| --- | --- |
| `kvImage_YpCbCrToARGBMatrix_ITU_R_601_4` | 1, 1.40199995, -0.714136302, -0.344136298, 1.77199996 |
| `kvImage_YpCbCrToARGBMatrix_ITU_R_709_2` | 1, 1.57480001, -0.46812427, -0.187324271, 1.8556 |
| `kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4` | 0.298999995, 0.587000012, 0.114, -0.168735892, -0.331264108, 0.5, -0.418687582, -0.0813124105 |
| `kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2` | 0.212599993, 0.715200007, 0.0722000003, -0.114572108, -0.385427892, 0.5, -0.454152912, -0.0458470918 |

The differential compares each of the four against the host's own, field by field. The 601 matrix for the forward
direction has no caller in the corpus; it is carried anyway, because it is one line of data the host agrees with and a
caller that generates a 601 conversion would otherwise follow a null pointer.

## The opaque conversion

`vImage_YpCbCrToARGB` and `vImage_ARGBToYpCbCr` are 128 opaque bytes. The host fills the first of them with a tag, the
eight fields of the pixel range as `int32`, and then the matrix as it was given, unscaled - which the dump in
`tests/backports/host/ypcbcr` reads out. The port keeps its own layout: a tag of its own, the matrix as given, the two
scales the pixel range gives, the two biases and the four clamps. Nothing outside this package reads those bytes, and
the conversions refuse a structure whose tag is not theirs, so a structure made by one release's library is never read
by another's.

## The arithmetic

The header states it in full, and the port does what it states. For Y'CbCr to ARGB, each of Y', Cb and Cr is first
clamped to the range's own limits, then

    R = round((Y' - Yp_bias) * 255/(YpRangeMax - Yp_bias) * Yp + (Cr - CbCr_bias) * 255/(2*(CbCrRangeMax - CbCr_bias)) * Cr_R)

clamped to 0 to 255, and G and B likewise; the alpha is the byte the caller gives; the permutation map moves the four
bytes on the way out. For ARGB to Y'CbCr the luma is the dot product of the three channels with the first row of the
matrix, scaled by (YpRangeMax - Yp_bias)/255 and offset by the bias; the chroma of a two by two block is the mean of
the same dot product over its four pixels, which is what the header's pseudo-code adds up and divides by four, and what
chroma sited at the centre means. A block at the right or bottom edge of an odd-sized picture averages the pixels it
has.

## The one byte of difference, measured

The system does this in fixed point; the port does it in `float` and rounds once at the end. The two disagree by
exactly one on 4262 of 457920 bytes - 0.93 per cent - over four pixel ranges (video range clamped and unclamped, full
range clamped and wide open), both matrices, four picture sizes including a two by two and an odd 34 by 18, and four
permutations. No byte ever differs by more than one, in either direction, in any of the six conversions. The port's
answer is the correctly rounded one: where they differ, the exact value lies between 0.487 and 0.498 above the integer
below it and the system rounds it up. The header promises results that are "faithfully rounded", which is what both
answers are, and the differential asserts the bound of one rather than equality.

A single channel makes this plain. With the 601 matrix and video range, a picture of pure blue at 5 writes 17 on the
host where the exact answer is 16.4895, and at 148 writes 31 where the exact answer is 30.4901; the port writes 16 and
30. No arrangement of a fixed scale and a fixed rounding reproduces the host's answers, so the difference is inside its
own pipeline and not a coefficient the port could copy.

## What it refuses

The port converts the 420 8-bit types the corpus asks for: `kvImage420Yp8_Cb8_Cr8` and `kvImage420Yp8_CbCr8`, to and
from `kvImageARGB8888`. Every other pair is refused by the generators with `kvImageUnsupportedConversion`, the code the
header names for a conversion vImage has not got. This is a stated difference from the system, which carries more: the
differential checks both sides of it, that the system converts `kvImage444CrYpCb10` and that the port says it does not.
A permutation map that is not a permutation of 0 to 3 is `kvImageInvalidParameter`; a destination bigger than the
source is `kvImageRoiLargerThanInputBuffer`; a flag outside the set the header names is `kvImageUnknownFlagsBit`; and a
conversion structure the port did not make is `kvImageNullPointerArgument` rather than a read of someone else's bytes.

## What is not carried yet

The corpus asks for 21 vImage names and this file carries ten of them, the ten the live port's own modules read.
`vImageBuffer_Init`, `vImageBuffer_InitWithCGImage` and `vImageCreateCGImageFromBuffer` were already carried for iOS 7.
`vImageConvert_RGB565toBGRA8888`, `vImageConvert_BGRA8888toRGB565`, `vImageConvert_ARGB16UtoRGB16U`,
`vImageConvert_ARGBFFFFtoRGBFFF`, `vImageScale_ARGB16U`, `vImageScale_Planar16U`, `vImageConvert_AnyToAny` and
`vImageConverter_CreateWithCGImageFormat` are the rest, each with one caller, and each still absent.
