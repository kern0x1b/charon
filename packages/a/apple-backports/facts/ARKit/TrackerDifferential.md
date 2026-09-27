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

## Where the tracker stands after the Gauss-Newton step

Measured on 2026-09-27, the synthetic sequence of 30 frames at 5.73 degrees and 0.050 m a step, the
whole path 1.450 m:

```
rotation error: mean 1.74652 rad (100.068 deg), worst 3.01560 rad (172.781 deg)
distance error: mean 0.78884 m, worst 1.19418 m
tracking: no, 336 points, 0 planes
```

Three things were wrong with the pose before the step could mean anything, and two are now right:

- **The pose was thrown away every frame.** After the pipeline ran, `_cameraTransform` was reset to
  the identity, so nothing the solver computed survived to the next frame and a rate integrated over
  a sequence was worth nothing. The gyroscope's turn is now applied to the pose the tracker already
  holds, so the pose is carried from one frame to the next.
- **The projection used the pose backwards.** The pose is the camera's in the world - that is the
  transform a landmark is placed with - and putting a world point back into the camera's space is
  its inverse. The solver now inverts it, and the camera's own space is the one the rest of the file
  uses, where a ray out of the camera is `(image.x - 0.5, image.y - 0.5, 1)` and forward is `+z`.
- **The matched points carried no world position at all.** A point is a landmark once it has been
  seen twice, and its place in the world was only ever computed for the copy that feeds the plane
  pass, so the set the solver reads had `world` of zero throughout and every residual was refused as
  a point behind the camera. A point is now placed in the world when it is first seen and when it
  survives its first frame.

**What is still wrong, and it is the one number that matters:** the scale a landmark is placed at.
`placePointInWorld:` puts a point as far off as its feature's size says, and that size is a grid cell
width in pixels, so the depth it produces is `0.5 / (cellWidth / lumaWidth)` - a few pixels counted
as metres, where the scene is at 1.45 m. Every reprojection residual is therefore measured against a
world the wrong size, which is why the step moves the pose but not towards the truth: the rotation
error is 100 degrees and the distance error 0.79 m, and no plane is found because the points the plane
pass grows regions from are in the wrong place.

That number is a judgement, not a derivation, and it is the one thing in the tracker that has to be
calibrated against the scene rather than computed from a frame. It is not guessed at here: the fix is
to give the tracker the scene's real scale - from the camera's field of view, which
`+cameraIntrinsicsForResolution:` already reads and which turns a pixel offset into an angle and so a
patch size into a distance - and then to re-measure. Until that is done the step is wired and
running but is not yet producing a pose the picture agrees with.
