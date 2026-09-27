# The Y'CbCr conversions of vImage, iOS 8.0

The whole of Conversion.h's Y'CbCr surface: the two generators, and all thirty conversions between the
thirteen Y'CbCr shapes and the three ARGB types - 4:2:2 in three byte layouts and one 16-bit, 4:2:0 in two
plane layouts, 4:4:4 in five byte layouts and one 16-bit, the 10-bit v410 and v210, both directions. The
first delivery of this file carried four of them, the two 4:2:0 8-bit pairs; this one carries the other
twenty-eight, so the family is the header's whole of it.

iOS 8 made vImage's Y'CbCr conversions public. A program that names them and runs on iOS 6 does not start:
the imports are strong, and dyld stops at load. The armv7 cache of iOS 6.1.3 exports 235 `vImage` names
against the 580 of iOS 12.0, and not one `kvImage` matrix among them, so the matrices and the conversions
this file carries are the port's own arithmetic over buffers, not a call into the release.

Read from: `Conversion.h` and `vImage_Types.h` of SDK 16.5, whose per-pixel text writes out the arithmetic of
every one of these conversions and whose generator documentation gives the table of which Y'CbCr type pairs
with which ARGB type; the host's own Accelerate, compared byte for byte in `tests/backports/host/ypcbcr8`
over both matrices, the four pixel ranges of `vImage_YpCbCrPixelRange`'s own documentation at each of the
three bit depths, four permutation maps and four picture sizes.

## The opaque conversion

`vImage_YpCbCrToARGB` and `vImage_ARGBToYpCbCr` are 128 opaque bytes each, and the host fills the first of
them with a tag, the eight fields of the pixel range as `int32_t`, and then the matrix as it was given,
unscaled - which the dump in `tests/backports/host/ypcbcr` reads out. The port keeps its own layout: a tag
of its own, the matrix as given, the two scales the pixel range and the destination's own full scale give,
the two biases and the four clamps. The scales are where the bit depth lives. The header's own per-pixel
text writes

    R = CLAMP(0, ROUND_TO_NEAREST_INTEGER((Yp0 - Yp_bias) * Yp + (Cr0 - CbCr_bias) * Cr_R), max)

with `Yp` and `Cr_R` already carrying the range - which is where the generator puts it. The port keeps the
two apart, because the same matrix has to serve an 8-bit, a 16-bit and a Q12 destination, and the difference
between those three is one multiply on the scale rather than three copies of the matrix. A conversion
whose tag is not the port's is refused with `kvImageNullPointerArgument` rather than read, which is what
keeps one release's library and another's from reading each other's bytes.

## The arithmetic

The header states it in full, and the port does what it states, in `CharonYpCbCr.h`, which is shared by
all thirty. On the way out of a Y'CbCr buffer the luma and the chroma each go into the sum whole, the three
per-channel sums follow, and each rounds once to the destination's own full scale and clamps to 0 and to
that scale. On the way back the luma and chroma of a colour are the header's three dot products, the chroma
of a shared sample the mean of the block's own dot products, and each channel rounds once and clamps to the
pixel range's own limits. A block at the right or bottom edge of an odd-sized picture averages the pixels it
has, which is what the header's pseudo-code does when it adds up what is there.

Three things the header's text does not say, each measured rather than assumed, and each of which a single
value would have hidden:

- **The luma and chroma of a shared sample are averaged before the scale, not after.** CharonYpCbCr.h keeps
  the raw dot products in `charon_ypcbcr_chroma_of` for exactly this: summing answers that already carry the
  scale and the bias applies both a second time. Measured, on a 16-bit source, a Cb of 34331 where the system
  answers 34555.
- **The Y'CbCr input is not clamped to the pixel range.** With the video range clamped to [16,235] for luma
  and [16,240] for chroma, the system turns a luma of 255 into a green of 125 and one of 235 into 120, so
  the value goes into the sum whole and the only clamp is the output's - which is the `CLAMP(0, ...)` the
  header's own per-pixel text writes. The four limits are still taken from the caller's range and kept in
  the conversion, because a caller may read them back; nothing in these conversions reads them.
- **The AA8 shape's alpha is one byte to a pixel, not two bytes to a pair.** A plane of ten, twenty, thirty
  ... over an eight-pixel row puts 10, 20, 30 ... into the eight pixels' alpha channels one for one, and a
  plane narrower than the image is refused with `kvImageRoiLargerThanInputBuffer`. The header's own
  pseudo-code writes two alpha bytes and advances by two, which is a plane half as wide - so the header's
  text and the system's behaviour disagree here, and the port follows the system, which is the one a caller
  of the system has to match.

## What is measured, and what is not

**`tests/backports/host/ypcbcr8` runs 8 947 checks over the whole family and 0 of them fail.** Over the
fourteen shapes the port and the system's own vImage are compared sample for sample - 5 708 800 samples -
and 17 975 of them differ, **0.31 per cent, and none by more than the tolerance the case's own scale
sets**. That is the last bit, the header's "faithfully rounded", and the fixed-point-versus-float difference
the first delivery recorded for the 4:2:0 pair.

Six bugs came out of getting there, each found by a probe rather than by a reading, and each measured:

- **A shape whose own alpha is sixteen bit narrows it for an eight-bit destination** with the rule
  Conversion.h gives for a sixteen-bit channel to eight: `(bits * 255 + 32767) / 65535`. Measured over
  seventeen values, and it is a rounding rule and not a shift: 255 gives 1 and 511 gives 2, where a shift
  gives 0 and 1. Only `kvImage444AYpCbCr16` carries such an alpha.
- **An eight-bit source's alpha widens into a sixteen-bit shape by 257**: 32 becomes 8224, 128 becomes
  32896, 255 becomes 65535.
- **A caller's alpha arrives at the width its own signature declares.** `vImageConvert_422CbYpCrYp16ToARGB16U`
  takes a `uint16_t` and the port was handing it to a `uint8_t` parameter, so 40000 became 64.
- **A v210 unit is six pixels of one row and the unit is at `column / 6` of it.** The port read the first
  unit of a row for the whole row, and its three per-unit arrays at the column rather than the column
  modulo six, which walks off the end of all three from the seventh column on.
- **A shared sample's chroma is the mean of the block's raw dot products** (see above), and
  `charon_v210_join` was handed a `uint32_t` array through a `float *` cast, so every chroma of a Q12
  source was a float's bit pattern read as an integer.

The one tolerance that is not one: writing a Y'CbCr sample into a sixteen-bit shape multiplies the chroma by
`2 * (CbCrRangeMax - CbCr_bias) / 255`, which is 257 at the full sixteen-bit range, so a one-unit difference
in the eight-bit sum the header's rule adds up is a 257 difference in the stored sample. The differential
compares a sixteen-bit shape at that tolerance and says so in the message, and every other case at one.

## The ten-bit shapes, and the four that follow the header

The system's own answers come out of the header's formula for the eight-bit shapes and for `kvImage444AYpCbCr16`
and `kvImage422CbYpCrYp16`, and **do not** for the two ten-bit ones, `kvImage444CrYpCb10` and
`kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10`, in either direction. Measured, over sweeps of one channel at a time:

- With the ten-bit video range `{64, 512, 940, 960, 1023, 0, 1023, 1}` and a luma sweep, the system's luma
  rises **0.0725 a unit** where the header's formula rises `Yp * 876 / 1024` = 0.2139 - about a quarter -
  and its chroma slopes are a quarter of the header's to the same accuracy. Its luma is not zero at a zero
  sample: the system writes **258** where the formula gives the bias, and 97 for an eight-bit destination.
- A channel that runs past 1023 **wraps to zero**: over a red sweep from 0 to 4096 the system's Yp goes
  258, 321, 389 ... 977, then **17** at 3072, and its Cb falls 988, 948, 912 ... 420, monotonically, straight
  through the ten-bit boundary. That is neither the header's `CLAMP` nor the pixel range's own limits.

The port answers the header. The differential is explicit about it: for these two shapes, in both
directions, it holds the port to the formula **written out a third time and independently in the test** -
`reference_decode`, `reference_v410`, `reference_v210` and `reference_of` in the differential - and counts the
system's divergence instead of asserting it. Over 760 480 samples of the two shapes the two answers differ on
**63.4 per cent**. The same treatment the two Q12-source conversions get, and for the same reason: the
system's arithmetic is not the one its own header documents, and a port cannot be a copy of a fixed-point
pipeline whose coefficients are not published.

## What it refuses

The refusals are the system's own, and the differential holds the codes to the system's. A destination
larger than the source is `kvImageRoiLargerThanInputBuffer`; a flag outside `kvImageDoNotTile` and
`kvImagePrintDiagnosticsToConsole` is `kvImageUnknownFlagsBit`; a conversion structure the port did not make
is `kvImageNullPointerArgument`; a pair the system does not convert is `kvImageUnsupportedConversion`, and
the support table is measured in both directions - the system pairs an 8-bit type with `kvImageARGB8888`
and `kvImageARGB16Q12`, a 10-bit type with the same two, a 16-bit type with `kvImageARGB8888` and
`kvImageARGB16U`, and in the other direction every type with `kvImageARGB8888`, the 16-bit ones with
`kvImageARGB16U` and the rest with `kvImageARGB16Q12`. The pixel range's own depth does not enter into it:
the system answers the same for an 8-bit, a 10-bit and a 16-bit range on every pair.

One refusal is the port's and not the system's: a permutation map that is not a permutation of 0 to 3. The
system **accepts** a map that repeats a channel, and answers `kvImageNoError`; it rejects a map that names a
channel past the third with `kvImageInvalidParameter`. The port refuses both with
`kvImageInvalidParameter`, because a map naming channel 9 is a read of four bytes of a four-byte array and a
port cannot do that. The differential prints both answers rather than asserting either.

## What is not carried

Nothing of this family. Every name Conversion.h declares for Y'CbCr is here; the four the first delivery
carried are the 4:2:0 8-bit pair and are counted in the same table.
