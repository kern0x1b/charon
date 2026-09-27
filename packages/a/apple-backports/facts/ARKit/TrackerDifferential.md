# The tracker's offline differential, and what it measures

There is no ARKit on the host to compare against, so the comparison is constructed: a camera is
walked along a path it is also *shown*, each frame rendered by hand from where the surface point of
each pixel really is, and the pose the tracker reports for that frame is compared with the pose that
produced it. The attitude it is driven with carries the gyroscope's own error, because a gyroscope
on a real device is never exact.

`spatial-tracker-diff.m` builds and runs it:

    clang -O -fobjc-arc -DCHARON_TRACKER_OFFLINE=1 -I . -o tracker-diff \
          CharonARTracker.m spatial-tracker-diff.m \
          -framework Foundation -framework CoreVideo -framework CoreGraphics
    ./tracker-diff

## The seam, and what it leaves out

`CHARON_TRACKER_OFFLINE` compiles out three things and nothing else: the `CMMotionManager` the
session owns, the `AVCaptureDevice`/`AVCaptureSession` the session owns, and the two
`ARRaycastTarget` cases a raycast filters its targets with. The first two do not exist on the host
and the third is not declared there. Every line of the tracking, the matching, the integration, the
plane detection, the hit test and the raycast is the same object file either way, which is what
makes the offline numbers say something about the device build.

The frame-processing entry point deliberately does not require the tracker to have been started:
the camera is the session's business, and a recorded sequence has to be runnable through the same
code path a live one uses.

## What it measures, and what it found

The ground truth is 30 frames, each turning 5.73 degrees about `y` and walking 5 cm forwards, so
the last pose is 1.450 m along an arc whose position and attitude are known in closed form. Compared
per frame: the angle between the attitude the reported camera transform carries and the attitude
that produced the frame, and the distance between the reported camera position and the true one.

    spatial tracker differential: 30 frames, 5.73 degrees and 0.050 m a step,
      driven 1.450 m along the path, the last pose truth at 1.450 m
      rotation error: mean 1.60000 rad (91.673 deg), worst 2.90000 rad (166.158 deg)
      distance error: mean 0.66572 m, worst 0.99510 m
      tracking: no, 0 points, 0 planes

**Those numbers are a failure, and they are reported as one.** The pose errors are what a tracker
that never tracks looks like; nothing above is a claim that it works.

### Fixed, and the fix was real

1. **The corner pick and the patch search shared one array.** `findFeatures` overwrote the matched
   points before `matchFeaturesTurningBy:` could read them, so nothing was ever matched, whatever
   the frame contained. They are now two arrays - `_candidates` for what a frame offers, `_points`
   for what was matched into it - and a corner the search did not match keeps its own identity into
   the next frame. Found by the differential: 0 points and 0 planes, which is what a tracker that
   never matches a point looks like.

### Two bugs in the test surface, and one of them was instructive

The first surface was a **hash of the world position**, which is the wrong scene for this test and
the reason the pick found nothing. A hash has a large gradient energy but almost none of it across
both directions at once, and the Shi-Tomasi score takes the *smaller* of the two eigenvalues of the
structure tensor, so it rejects a stripe however strong the stripe is. The tracker was right and the
test was wrong. Replacing it with three sines of the world coordinates - a surface with real
two-dimensional structure - is what a corner detector is looking for.

The frequencies then had to be reconciled with the sampling, and **that reconciliation is not
finished**. Measured on the same 160x120 frame with the same score and the same threshold of 40:

| spatial frequency of the surface | positions above the threshold | best score |
| --- | --- | --- |
| 7 to 13 per metre | 3 | 49.8 |
| 90 to 140 per metre, camera at the origin | 936 | 47818.7 |
| 90 to 140, camera on the driven path | **0 from the second frame on** | — |

The last row is the open problem, and it is a property of the *harness*: at 2 m those frequencies
project to roughly ten cycles per pixel, so a turn of 5.73 degrees a step walks the sampling
straight through the aliasing, and a scene that is well sampled from the origin is not well sampled
from a turned camera. The frame the tracker reads has a mean squared gradient of 5849 - the texture is
there - and the same loop in the same function scores every position below the threshold. The fix is
a surface band-limited to what the camera can actually see at that distance, which is a property of
the test and not of the tracker.

**ARKit is therefore not deliverable yet.** The classes, the configurations, the `isSupported`
answers and the frame, anchor, hit-test and raycast plumbing are carried and the six files compile
for armv7 / iOS 6.1.3 with no diagnostic. A session would start, report frames, and carry no points.
Nothing in the registry claims otherwise, and the next thing to do is the corner pick: finish
calibrating this harness, then read out the pose error it is built to measure.
