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

**It found a real bug, and then it failed to pass.**

    spatial tracker differential: 30 frames, 5.73 degrees and 0.050 m a step,
      driven 1.450 m along the path, the last pose truth at 1.450 m
      rotation error: mean 1.60000 rad (91.673 deg), worst 2.90000 rad (166.158 deg)
      distance error: mean 0.66572 m, worst 0.99510 m
      tracking: no, 0 points, 0 planes

1. **Fixed: the corner pick and the patch search shared one array.** `findFeatures` overwrote the
   matched points before `matchFeaturesTurningBy:` could read them, so nothing was ever matched.
   They are now two arrays — `_candidates` for what a frame offers and `_points` for what was
   matched into it — and a corner the search did not match keeps its own identity for the next
   frame. That is `CharonARTracker.m`'s two-array structure.

2. **Open, and it is why the numbers above are the ones they are: the corner pick returns nothing
   from the second frame on.** Measured, not assumed: 21 candidates on the first frame and **0** on
   every frame after it, while the luma the tracker has read has a mean squared gradient of 5849 and
   the first frame's identical loop found 895 positions above the score threshold. So the frame is
   read and the texture is there, and the same loop in the same function on the next frame scores
   every position below the threshold. Not yet located, and not worked around.

**ARKit is therefore not deliverable yet.** The classes, the configurations and the `isSupported`
answers are carried and the files compile; the tracking behind them does not run, and the honest
statement is that a session would start, report frames, and carry no points. Everything the
registry says about the classes is true; nothing it says is a claim that tracking works, and the
next thing to do is the corner pick.
