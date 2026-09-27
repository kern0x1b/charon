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

The differential found **four** defects, three in the tracker and one in the test, each located by
dumping the tracker's own state for one frame and reading it:

1. **The corner pick and the patch search shared one array.** `findFeatures` overwrote the matched
   points before `matchFeaturesTurningBy:` could read them, so nothing was ever matched. Two arrays
   now: `_candidates` for what a frame offers, `_points` for what was matched into it.

2. **The attitude the caller hands in was thrown away.** `processPixelBuffer:` overwrote its
   `deviceRotation` argument with a global that only the CoreMotion handler filled, so wherever
   there is no motion handler - which is every run of this differential - the tracker believed the
   camera had never turned, the search window drifted off the frame, and **not one position was
   searched**: `searched=0`, `drift=(-1.05,-1.05)`, `angle=4.1888` on a step of 0.1 rad. With the
   argument used, `angle=0.1000` - the true step - and 7917 positions searched.

3. **The unmatched corners were written over the matches.** The array is laid out as the matches
   followed by the fresh corners, and the second run started at index zero instead of at the match
   count, so every match was destroyed before the next frame saw it. Measured with the match dumping
   its own state: **17 to 19 matches a frame and still 0 points placed**, because a matched point
   never accumulated the three frames that would place it in the world. Fixed: **336 points**.

4. **The test surface, in the first version, was a hash of the world position** - the wrong scene
   for a Shi-Tomasi score, which takes the *smaller* of the two eigenvalues of the structure tensor
   and so rejects a stripe however strong the stripe is. Replaced by three sines of the world
   coordinates, at a spatial frequency measured to be inside what a 160x120 frame can sample.

## Where it stands, and it does not pass

    spatial tracker differential: 30 frames, 5.73 degrees and 0.050 m a step,
      driven 1.450 m along the path, the last pose truth at 1.450 m
      rotation error: mean 1.60000 rad (91.673 deg), worst 2.90000 rad (166.158 deg)
      distance error: mean 0.66572 m, worst 0.99510 m
      tracking: no, 336 points, 0 planes

The features are found, matched and placed - 336 points, which is what the pick and the search are
supposed to produce. **The pose is still wrong, and the reason is visible in the file:**
`refinePose` advances the camera along the direction the gyroscope says it turned, and nothing
else. There is no correspondence term in it, so the pose is dead-reckoned, and the differential
measures exactly that: a mean rotation error of 91 degrees over 30 steps, and 0 planes because the
plane detector never sees a consistent world to grow regions in.

So the next piece of work is named and is not a fix: `refinePose` needs the Gauss-Newton step its
own comment already claims, over the six parameters of the pose, from the reprojection residuals of
the 17-to-19 matches the frame now has. Until that lands, ARKit is not deliverable: a session would
start, report frames, carry 336 points, and put them in the wrong place.
