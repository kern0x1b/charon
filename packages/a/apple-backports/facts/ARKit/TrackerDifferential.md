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

### The open failure, narrowed

**The corner pick returns nothing from the second frame on, whatever the frame contains.** Measured,
not assumed:

| the surface | positions above the score threshold |
| --- | --- |
| a hash of the world position, 7 to 13 per metre | 3 |
| three sines at 20 to 30 per metre | 694 in the *worst* frame of the driven path |
| three sines at 90 to 140 per metre | 936 from the origin, 0 from the second frame on, aliased |

The middle row is the one that settles it: a surface that carries hundreds of corners in every
frame, measured on the very frames the tracker is handed, and the pick still returns nothing. So the
surface is not the cause, and neither is the threshold.

The localisation, as measured:

- the luma the tracker has read has a mean squared gradient of 5849 on frame 2 - the texture is
  there, and the first frame's identical loop found 895 positions above the threshold;
- the same loop, in the same function, on the next frame, scores every position below it;
- the frame-processing entry point is handed a `CVPixelBuffer` the harness writes and the tracker
  reads through its own stride and format logic.

So: the read is right, the scene is right, the score and the threshold are right, and the pick
stops finding anything after the first frame. That points at the pick's per-call state - the grid's
`best`/`bestX`/`bestY`, and the `_luma` size it derives its cells from - rather than at the maths of
the score, and that is where the next reading goes.

**ARKit is not deliverable yet.** The classes, the configurations, the `isSupported` answers and
the frame, anchor, hit-test and raycast plumbing are carried, and the six files compile for
armv7 / iOS 6.1.3 with no diagnostic. A session would start, report frames, and carry no points.
Nothing in the registry claims otherwise.
