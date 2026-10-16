# The CGImage constructors of Core ML's image feature value, measured against the host

The two constructors `+featureValueWithCGImage:pixelsWide:pixelsHigh:pixelFormatType:options:error:` and its
orientation form (both iOS 13.0) are measured by `tests/backports/host/coreml-image-constructors/probe.m`. The
probe builds the answers from two pictures (a 4x3 gradient and a 5x4 noise picture), 8 orientations, 8 crop
rects, 2 output sizes (2x2 and 8x6), 4 crop-and-scale options (nil, 0, 1, 2) and 3 formats (32BGRA, 32ARGB,
OneComponent8). That is 3072 cases, one line each. The probe compiles against the host framework, and against the
port's sources, so host and port are compared line by line.

The port does not match the host on every case, so these constructors stay **owed**. What is measured is below.

## What matches

- **Errors.** 1152 of the 3072 cases are errors, and the port's error lines are identical to the host's. The
  failing crop rects give these codes, all in the domain `com.apple.Vision`:

  | crop rect (x,y,w,h) | code | why |
  | --- | --- | --- |
  | 0,0,0,2 | 3 | no width |
  | 1,0,1,1 | 4 | one pixel wide, not at the origin |
  | 9,9,2,2 | 4 | wholly outside the picture |

  The rects 0,0,1,1, 0,0,2,2, 1,0,2,2 and -1,0,2,2 are valid. The zero output size is error 3, from the size, not the
  crop.
- **Crop placement and the fill outside the picture.** With stretch, a 2x2 crop written to a 2x2 output is an
  identity, and it matches the host for every crop rect that is valid and not one pixel wide, on both pictures (32 of
  32 for each group). The rect -1,0,2,2 runs off the left edge, so the match covers the fill outside the picture too.
- **Orientation.** Orientations 1 to 8 map as the EXIF numbering says. The port's stretch of the 4x3 gradient
  matches the host in all 8 orientations, BGRA and ARGB, at both sizes.
- **The default option.** On the host, nil answers exactly as option 2 in all 768 cases where both are present.
- **Stretch of the whole gradient.** The port's stretch (option 2, and nil) matches the host in all 64 cases with no
  crop: the 4x3 gradient reduced to 2x2 and enlarged to 8x6, in every orientation and format.
- **Identity picture.** A picture already of the requested size comes back as its own bytes, on the host and in the
  port (a single 5x4 noise picture, BGRA, nil option, measured in scratch and not in the committed probe).

## What does not match

Stretch (options nil and 2), counted as matches over the cases of each crop rect (64 per rect, two options, two
sizes, eight orientations and two formats):

| crop rect | gradient | noise |
| --- | --- | --- |
| none | 64/64 | 0/64 |
| 0,0,1,1 (one pixel) | 0/64 | 0/64 |
| 0,0,2,2, 1,0,2,2, -1,0,2,2 | 32/64 | 32/64 |

Those 32 are the 2x2 output in each case. The 8x6 output of every 2x2 crop differs (0 of 32 for each).

- **Enlarging a crop.** The 2x2 crops enlarged to 8x6 differ on both pictures. The whole gradient enlarged to 8x6
  matches, so the difference is in how the resampler treats a small source (edge taps or the sample positions), not
  in the sizes. Not identified here.
- **Noise.** The uncropped noise differs at both sizes, reduced to 2x2 and enlarged to 8x6. Identity matches, so the
  difference is in the resampler, not the draw. The port's resampler is the Vision kernel
  (`CharonVisionBilinear.c`), which matches the host on the gradient.
- **The one-pixel crop.** Every 0,0,1,1 crop differs from the host on both pictures, at both sizes, under stretch.
  The cause is not identified.
- **Cover (0) and fit (1).** On the gradient at 8x6, which has the picture's own aspect, all four options give the
  same answer on the host and in the port, so that size cannot separate them. At 2x2 the host's cover and fit differ
  from the port's. The host's fit answers alpha 127 where the port answers 255, which is not explained. The numbering
  of 0 and 1 follows Vision's `VNImageCropAndScaleOption` (CenterCrop 0, ScaleFit 1, ScaleFill 2), and nil equalling 2
  agrees with it, but the pixels do not yet confirm 0 and 1.
- **OneComponent8 (grey).** The host answers a grey image. The port's `MLFeatureValue` carries 32BGRA and 32ARGB
  pixel buffers only. It answers any other format as an undefined image value with no buffer, so all 640 valid grey
  cases come back with no buffer. The port's reader takes an image value's bytes as float32 (`MLFeatureValue.m`), so
  an 8-bit grey buffer cannot be carried until the reader takes one. The grey draw itself was measured in scratch
  (`grey5`, not committed): CoreGraphics' grey draw of the BGRA picture is within one level of the host's grey on all
  3072 bytes, and 75 of them differ by one.

## What is owed, and why

The two CGImage pixel-size rows stay owed until: the host's resampler on enlarged small sources and on noise is
identified and matched; cover and fit are measured at an aspect that separates them from stretch; and the port
carries a grey buffer in its image feature value. The crop placement, the error rules and the orientation are
matched and are the part a port can state now.
