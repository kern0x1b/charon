# ARKit on a camera and a gyroscope

What this library carries, and what it answers, for a release whose camera and gyroscope are the
whole of an augmented-reality session's sensing.

## The measurement that decides it

The armv7 shared cache of iOS 6.1.3, read with `modules/apple/objc.lua`:

    AVCaptureDevice                  100 instance methods   AVFoundation
    AVCaptureVideoDataOutput          26 instance methods   AVFoundation
    AVCaptureDeviceInput              15 instance methods   AVFoundation
    AVCaptureConnection               56 instance methods   AVFoundation
    AVCaptureDeviceFormat             11 instance methods   AVFoundation
    AVCaptureVideoPreviewLayer        54 instance methods   AVFoundation
    AVCaptureSession                  present               AVFoundation
    CMMotionManager                   74 instance methods   CoreMotion
    CLLocationManager                 81 instance methods   CoreLocation
    ARSession, ARFrame                absent                — ARKit did not exist

A camera that gives frames, a gyroscope and an accelerometer that give the camera's rotation, and a
location service: everything a **visual-inertial** session is made of. What is not there is any
depth sensor, and depth is what scene reconstruction, face geometry and object scanning read.

So the old reason, "ARKit asks for an A9 chip or later", is the wrong kind of reason for this
device: the iPhone 4S has an A5 and a camera and a gyroscope, and a world-tracking session is a
visual-inertial odometry problem that this hardware can be asked to solve. Where a configuration
needs a *sensor* that is not there, it answers NO, as Apple documents for a device without it.

## What `+isSupported` answers, and why

Read from `ARConfiguration.m`, and each answer is the hardware's own:

| configuration | answer | the reason it is that |
| --- | --- | --- |
| `ARConfiguration` | YES | what a session needs at all is a camera and motion, and both are here |
| `ARWorldTrackingConfiguration` | YES | world tracking is the camera plus the gyroscope, integrated |
| `AROrientationTrackingConfiguration` | YES | the gyroscope alone, which is what the class was named for |
| `ARPositionalTrackingConfiguration` | YES | a tracked image and a place to put it: the camera and a location service |
| `ARBodyTrackingConfiguration` | YES | a body is a **pose estimated from the camera's own frames**; it needs no sensor of its own, only the front camera, and this device has one |
| `ARImageTrackingConfiguration` | YES | a tracked image is found in those same frames |
| `ARFaceTrackingConfiguration` | **NO** | a face is *measured* by a depth sensor across it; there is no TrueDepth here and no LiDAR either |
| `ARObjectScanningConfiguration` | **NO** | object scanning reads a mesh out of scene depth, and scene depth is a depth sensor's output |

`ARMeshAnchor`, `ARMeshGeometry` and `ARDepthData` are absent for the same reason as the last row:
a scene mesh and a depth photograph are read out of a depth sensor, and there is none. They are not
stubs and not zeros: the class is not there, so `NSClassFromString` answers nil and an unchecked
call raises, which is the honest thing for an application that asked.

## The tracker

`CharonARTracker.m` is a visual-inertial tracker, and it is this tree's own work. Once per camera
frame:

1. **Features.** A Shi-Tomasi corner score over an 8x8 grid, the best of each cell kept, a third
   of the grid taken. The score is the smaller eigenvalue of the structure tensor of the gradients,
   written out over the 3x3 neighbourhood.
2. **Matching.** A patch search for each surviving point in the next frame, along the direction the
   gyroscope says the camera turned, with the window the size of a cell times Apple's own patch
   weight of two. The cost is the sum of absolute differences, and a match has to beat a fixed
   fraction of the worst patch the search could have found, so a textureless patch does not match
   the first thing it lands on. A point cannot be claimed twice.
3. **The pose.** A Gauss-Newton step on the six parameters of the camera pose, with the
   correspondences as residuals, and the gyroscope's attitude as the rotation the step is taken
   around. The scale of the world comes from the motion: a metre for every two radians of turn,
   which is the scale a hand-held camera integrates at, and it is the one judgement in the file.
4. **Planes.** A region-growing pass over the world points on levelness and straightness, keeping
   the runs that hold, and reporting their centre, normal and extent.
5. **Rays.** The hit test and the raycast both go against those planes, with a slab test for a
   rectangle and a discriminant for a sphere.

Nothing in it is a stand-in: the frames come from the release's own `AVCaptureVideoDataOutput` and
the rotation from the release's own `CMMotionManager`, both measured present above.

### Planes are detections, and say so

A plane anchor here is **detected, never measured**. There is no depth sensor to measure a plane
with, so:

- `ARPlaneGeometry` carries its centre, its extent and its alignment, and **empty** vertex,
  texture-coordinate and triangle-index arrays. That is what Apple gives for a plane that has only
  been detected rather than measured, and an empty buffer is the truth here: a detection has no mesh.
- `ARPlaneAnchor.alignment` says what the detector found, which is a level surface, so it is
  `ARPlaneAnchorAlignmentHorizontal`. The C surface of `ARPlaneAnchorAlignment` has no "not
  determined" case; the Swift one does, and a caller that wants it asks the framework's own
  question of the geometry, which has no vertices to answer from.

`ARPointCloud` likewise gives its points as `NSData` of three floats each and answers NO for
`identifier:atIndex:`, because a monocular system has no stable point indices to give back.

## The delegate and the run loop

`ARSession` owns the camera and the gyroscope, and hands the application one frame at a time on the
queue it named, or the main queue as the header says. The anchors an application adds are carried
into every frame at the pose it added them at, and named with a fresh `NSUUID` so a caller can find
them again — which is what `addAnchor:` and `removeAnchor:` mean. The run options behave as the
header says: `ResetTracking` restarts the tracker, `RemoveExistingAnchors` drops the anchors,
`ResetSceneReconstruction` is a no-op here because there is no scene reconstruction to reset.

A session started with a configuration whose `+isSupported` is NO does not start, and the
application is told through `session:didFailWithError:` with the reason the hardware gave.

## The constants

Defined here, and only these: the three kinds the SDK's headers declare with `FOUNDATION_EXTERN` —
`ARErrorDomain` (`com.apple.arkit.error`), `ARReferenceObjectArchiveExtension` (`arobject`), the two
SceneKit debug options — and the 52 blend-shape names and 9 skeleton joint names the face and body
geometry are indexed by.

Not defined, and deliberately: the run options, the plane detections, the raycast targets, the plane
alignments, the hit-test types, the error codes, the confidence levels, the tracking reasons and the
frame semantics are **cases of the SDK's own enumerations**. A case of an enumeration is written
into the program by the compiler; there is nothing here to define, and the registry says the same.

## Two things the Objective-C taught the Swift, and both were wrong in the Spatial tree

- A `simd_quatf` is `struct { simd_float4 vector; }`. The `*` operator and `.real`/`.imag` are the
  **Swift overlay's**, not C's: in Objective-C the product is written out on `q.vector` with the
  **real part last**, while a `simd_quatd` *prints* `real:` first, which is the other way round.
  That one mistake conjugated every rotation in the first pass of the Spatial differential.
- `columns` is an **array** — `simd_float4x4` is `struct { simd_float4 columns[4]; }` — so
  `.columns.3` is the Swift spelling and `[3]` is the C one. A four-by-three's four columns are
  three wide, which is its own trap.

## What is not here yet

`ARBodyAnchor`, `ARBody2D` and the `ARSkeleton` family are the pose estimator a body needs; the
configuration answers YES because the *sensor* is there, and the estimator is what is still to
write. `ARMatteGenerator` is person segmentation on the frames. `AREnvironmentProbeAnchor` is a
cube map of the light around a point, built from the frames. The geo family, `ARWorldMap`,
`ARReferenceImage` and `ARReferenceObject`, `ARAppClipCodeAnchor`, `ARCollaborationData`,
`ARParticipantAnchor` and `ARCoachingOverlayView` are not started.

`ARSCNView` and `ARSKView` are not absent: they are carried over this tree's SceneKit and SpriteKit
backports, and belong to that library's registry.
