# The motion requests of Vision: optical flow and trajectories, what the host answers

Measured by `tests/backports/host/vision-motion/motion.m` (its answers are in `expected.txt`, checked by `run.sh`).
Both requests and their observations are on the host; the port has none of them, and the rows that name them stay owed.

## Optical flow (`VNGenerateOpticalFlowRequest`)

- On a 64x64 target and a 64x64 source, with `computationAccuracy` high, the request answers one
  `VNPixelBufferObservation`, in a 64x64 buffer of format `kCVPixelFormatType_TwoComponent16Half` (843264102).
  The two components are the horizontal and vertical displacement, as half-precision floats.
- The values do not track a known shift. A textured picture shifted by 3 pixels, a picture not shifted, and a
  binary square shifted by 3 all give medians of about -2 to 2 in the vertical component, a NaN at some points, and
  no consistent horizontal displacement (the unshifted picture gives a horizontal median of NaN). The sign and the
  size of the displacement that Vision's output means are not established by this measurement, so the flow is not
  implemented: an implementation would have to reproduce values this measurement cannot check.

## Trajectories (`VNDetectTrajectoriesRequest`)

- The request is run on a timed `CMSampleBuffer` (a bare pixel buffer answers error 18, "No valid
  presentationTimeStamp was available for this image").
- Requested with a frame analysis spacing of 1/30 s and a trajectory length of 3, the request reports a trajectory
  length of 5.
- On a 16-pixel square moving one pixel per frame, the first `VNTrajectoryObservation` appears at the seventh frame
  (frame index 6), and one appears on every frame after it. Its confidence is 0.000.
- The trajectory's own values (its polynomial, its points, its moving average) are not read here. The port has no
  trajectory observation: the reasons in the registry name this.

## What is owed, and why

Both requests and the trajectory observation stay owed. Implementing either needs the algorithm Vision uses, which is
not measured: the flow values above do not reduce to a shift, and the trajectory values are not read. The measurements
in this file are the facts an implementation would be checked against.
