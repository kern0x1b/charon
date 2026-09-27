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

## What is measured, and what is not yet

**The 8-bit shapes are done and are held byte for byte.** The four 4:2:2 and 4:4:4 eight-bit shapes, the
a2vy shape with its own alpha plane, and the two 4:2:0 shapes of the first delivery agree with the system on
every sample of `tests/backports/host/ypcbcr8`, no sample differing by more than one - which is the last bit,
the header's "faithfully rounded" and the fixed-point-versus-float difference the first delivery recorded.
The 10-bit and 16-bit shapes are **not**: over the whole family the differential now runs 8 947 checks and
**1 377 of them fail**, 13.37 per cent of 7 396 352 samples apart and up to 65 535 wide, and every failure is
in a shape whose samples are 10 or 16 bits wide - `444CrYpCb10ToARGB8888` and `...ToARGB16Q12` (256 each),
`444AYpCbCr16ToARGB8888` (256), `422v210ToARGB8888` and `...ToARGB16Q12` (160 and 192),
`444AYpCbCr16ToARGB16U` (128), `422CbYpCrYp16ToARGB16U` (128) - with one exception,
`422CbYpCrYp16ToARGB8888`, which fails once. The 8-bit shapes fail nowhere. That is a real defect in the wide
and ten-bit read path and it is **not** fixed; the next round starts there.

Two things this round did fix, both found by a probe rather than by the differential:

- **A v210 unit is six samples of one row, not a block of two rows.** Over a four-row buffer whose four units
  each carry their own values, the system returns row 1 as row 1's unit; the port had been dividing the row by
  six and returned row 0's for the first six rows, and had been writing one destination unit row per two
  source rows. The chroma of a unit is the mean of the row's own three column pairs, which is what the
  header's pseudo-code adds up.
- **`charon_v210_join` took a `float` array and was handed a `uint32_t` array through a cast**, so the
  graded integers' bit patterns were read as floats and every chroma of a Q12 source came out wrong. Its
  arguments are the integers now.

And a gap in the check itself, which is why the numbers above are new: the differential's main loop had been
lost in an edit, so the run that reported "0 failures, 623 616 samples compared" was exercising one shape and
the four wide-source cases and nothing else - the 8, 947 is the count the whole family gives. The claim this
section made before, over the whole family, was not supported by what the run measured.

## The Q12 source: where the system stops following the header

The two functions whose *source* is a Q12 buffer - `vImageConvert_ARGB16Q12To444CrYpCb10` and
`vImageConvert_ARGB16Q12To422CrYpCbYpCbYpCbYpCrYpCrYp10` - are the one place where the system's answers do
not come out of the header's formula, and the measurement is on both sides:

- A **zero** Q12 pixel comes back from the system as a luma of **258** in a ten-bit word, where the header's
  formula gives the bias, 64. A luma sweep shows the system's luma rising by 0.257 a unit where the formula
  rises by `R_Yp * 876/4096` = 0.064, and the chroma rising and falling on a scale of 0.875 where the formula
  gives 0.219.
- A channel that runs past 1023 **wraps to zero** rather than stopping there: over a sweep of red from 0 to
  4096 the system's Yp goes 258, 321, 389, ... 977, then **17** at 3072, and its Cb goes 988, 948, 912, ...
  420, monotonically, straight through the ten-bit boundary. That is neither the header's `CLAMP` nor the
  pixel range's own limits, and it is not a rounding.

So on 11 200 words of these two conversions the two answers differ on **95.71 per cent**, and the port
answers the header. The differential is explicit about it: for these two it checks the port against the
header's formula written out a third time and independently in the test, and counts the system's divergence
instead of asserting it. The 16-bit source path of the same family, `vImageConvert_ARGB16UTo*`, follows the
formula and matches the system on every sample of the run.

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
