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

### Both rungs, and the counts behind every absent row

The thirteen `absent` rows of `registry/ARKit/ios11.json` were read against **both** armv7 caches
of the port's two releases — 6.1.3 (244 881 694 bytes) and 4.3 (153 152 518 bytes) — with
`modules/apple/objc.lua`'s `inventory`, which walks each cache's own `__objc_classlist`,
`__objc_catlist` and `__objc_protolist` rather than scanning strings:

| | 6.1.3 | 4.3 |
| --- | --- | --- |
| classes and protocols walked | 11378 and 1171 | 7187 and 564 |
| names beginning `AR` | **0** and **0** | **0** and **0** |
| names containing `Depth`, `TrueDepth`, `LiDAR`, `SceneDepth`, `Tracked`, `DepthData` | **0** of 12549 | **0** of 7751 |
| selectors in the union of classes, protocols and categories | 113 981 | 70 062 |
| `AVCaptureDevice` (positive control) | 100 instance, 5 class | 66 instance, 5 class |
| `CMMotionManager` (positive control) | 74 instance, 4 class | 64 instance, 1 class |
| a nonsense name (negative control) | absent | absent |

**A correction the walk forces, and it is the reason this section exists.** The absent rows used to
carry the source "no depth and no face class of any kind". That is false of 6.1.3 and the walk says
so: 137 of its 12 549 class and protocol names contain `Face`. They are FaceTime internals, a
Facebook view, a pass template, and **2D face detection**, which iOS 6 genuinely has — `CIDetector`
(3 instance and 1 class methods), `CIFaceCoreDetector` (14 instance), `AVMetadataFaceObject`
(10 instance, 2 class), `PLCameraFaceDetectionView` (3 instance), with `-featuresInImage:options:`
and `-boundingBox` in its 113 981 selectors. What the walk finds missing is the half these rows turn
on: **0** names contain `Face` together with `Vertex`, `Triangle` or `Mesh`, and the 18 names that
contain `Mesh` are geometry interpolation (`CAMeshInterpolator`, `CAMeshTransform`,
`CAMutableMeshTransform`), a vector-graphics tessellator (`VGLDualTexturedMesh` and the rest of
`VGL*`) and a map annotation (`VKMeshAnnotationMarker`) — no scene mesh, no anchor, no vertex
buffer. A bounding box is where a face is in a picture, not how deep it is. On 4.3 the face API is
nearly gone too: 6 names contain `Face`, one of them a detector, and `CIDetector` and
`CIFaceCoreDetector` are absent outright.

`ARSKView` and `ARSKViewDelegate` are the two rows that are **not** a sensor answer, and they are
measured as a dependency instead: `SKView`, `SKScene`, `SKNode`, `SKSpriteNode`, `SKCameraNode` and
the `SKViewDelegate` protocol are absent, 0 entries each, from both caches, and
`tools/cache-index/first-rung.py` reads 7.0 for both `SKView` and `_OBJC_CLASS_$_SKView` (the
nonsense control reads `NONE`). SpriteKit has no folder, no row and no implementation in this tree,
so the view is missing on every release the port carries, not only on 6.1.3.

### The light estimate is a fixed pair, and no direction is computed

`ARDirectionalLightEstimate` is `absent` and its row had to be re-grounded to say why, because the
first version leaned on the parent as a substrate and the parent is not one. What the port
actually does: `ARLightEstimate` (`ARFrame.m:302`) holds two scalars, the frame builds it from the
tracker's two numbers (`ARFrame.m:366`), and `CharonARTracker.m:642-643` fills those in as the
fixed pair **1000** and **6500** in `-init` — they are set once and never measured from a frame.
There is no ambient estimator in the port, and no direction anywhere: `primaryLightDirection` and
`directionalLightEstimate` are in no source file of this package, and `-primaryLightDirection` is in
none of the 113 981 selectors of 6.1.3 nor of the 70062 of 4.3. So the subclass is not missing
from a substrate that would have carried it; there is nothing to carry it on.

That is stated here rather than only in the row because the neighbouring truth belongs with it: the
`implemented` row `ARLightEstimate` says its class "answers from the tracker", and the tracker
answers a constant. The row is not wrong — the value does come from the tracker — but a reader will
take it for a measurement, and it is not one. **It is not edited here**: it is a different row, and
the fix is either an estimator or an effect that says the pair is fixed, which is the owning band's
call. Recorded for the coordinator with the lines.

### What the hardware claim rests on, and what it does not

The sensor rows turn on one hardware fact: a device with no depth sensor cannot produce a face
mesh, a scene mesh, a depth photograph or a scanned object. **The tree's own record of the fleet's
silicon is one measured line and it is the graphics half**: `facts/Metal/PixelFormats.md` records
the renderer string of the fleet's iPad 2 at 6.1.3, `OpenGL ES 2.0 IMGSGX543-73.16.1`, read on the
device by `tests/backports/device/gl-extensions.m` on 2026-09-24. The SoC name is not measured
anywhere in this tree. `A5` appears in five places — `facts/ARKit/ARKit.md`,
`facts/DeviceCheck/DCAppAttestService.md`, `facts/Metal/MTLCreateSystemDefaultDevice.md`,
`facts/Metal/RenderPath.md` and the `registry/Metal/ios8*.json` rows — and every one of them is
asserting the model-to-silicon mapping rather than reading it off a device. That is worth
recording as what it is: **no `absent` row here rests on the `A5` label.** What each of these rows
rests on is the walk above (the release has no depth API at all, on either rung) together with the
port's own two `+isSupported` answers, which are code and can be read. Establishing the silicon
properly is a device measurement nobody has taken yet, and it is owed to the five places that
assert it.

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
`ARReferenceObject`, `ARAppClipCodeAnchor`, `ARCollaborationData`,
`ARParticipantAnchor` and `ARCoachingOverlayView` are not started.

`ARImageAnchor` is carried: it is the anchor whose thing in the world is a printed picture, holding
the `ARReferenceImage` the session found it from and the scale it measured against it — the tracker's
own frames, so it rests on the same measurement as everything else the camera is the sensor for.

`ARSCNView` and `ARSKView` are not absent: they are carried over this tree's SceneKit and SpriteKit
backports, and belong to that library's registry.

## What the gate's compiler still asks for, named

The full gate builds with `-Werror`, and two of its warnings are not warnings: a class the SDK
declares must **implement every accessor its header declares**, and a protocol it adopts must have
every method. `swiftc -c` without those flags is not the same check, and the six files compile
clean under it and do not under the gate's.

This is the list the gate's own compiler names, and it is the whole of what stands between the
library and a green build. Every entry is one of three things, and which is decided by the hardware:

**Answerable from this device — implement.** `ARConfiguration`'s `supportedVideoFormats`,
`videoFormat`, `lightEstimationEnabled`, `providesAudioData`, `worldAlignment`, `videoHDRAllowed`,
`frameSemantics`, `supportsFrameSemantics:`, `configurableCaptureDeviceForPrimaryCamera`,
`recommendedVideoFormatFor4KResolution`, `recommendedVideoFormatForHighResolutionFrameCapturing`,
`copyWithZone:`; each subclass's `init` and `new` and `autoFocusEnabled`; `ARWorldTrackingConfiguration`'s
`planeDetection` and `environmentTexturing`; `ARSession`'s `setWorldOrigin:`, `raycast:`,
`trackedRaycast:updateHandler:`, `ARFrame`'s `projectionMatrixForOrientation:viewportSize:zNear:zFar:`,
`projectPoint:orientation:viewportSize:`, `hitTest:types:`, `raycastQueryFromPoint:allowingTarget:alignment:`,
`displayTransformForOrientation:viewportSize:`, `viewMatrixForOrientation:`, `copyWithZone:`;
`ARAnchor`'s `supportsSecureCoding`, `initWithCoder:`, `encodeWithCoder:`; `ARPlaneGeometry`'s
`alignment`, `center`, `extent`; `ARPlaneAnchor`'s plane-value initialiser; `ARRaycastQuery`'s
`initWithOrigin:direction:allowingTarget:alignment:`.

**Answers the hardware, and is `@dynamic`.** Every setting that needs a sensor this device has not:
`ARWorldTrackingConfiguration`'s `initialWorldMap`, `detectionImages`, `detectionObjects`,
`wantsHDREnvironmentTextures`, `automaticImageScaleEstimationEnabled`, `maximumNumberOfTrackedImages`,
`collaborationEnabled`, `userFaceTrackingEnabled`, `appClipCodeTrackingEnabled`, `sceneReconstruction`,
`supportsUserFaceTracking`, `supportsAppClipCodeTracking`, `supportsSceneReconstruction:`;
`ARBodyTrackingConfiguration`'s the same set and `automaticSkeletonScaleEstimationEnabled`;
`ARFaceTrackingConfiguration`'s `supportedNumberOfTrackedFaces`, `maximumNumberOfTrackedFaces`,
`supportsWorldTracking`, `worldTrackingEnabled`; `ARPlaneAnchor`'s `classification`,
`classificationStatus`, `isClassificationSupported`, `classificationSupported`.

**Reports through its own argument rather than answering.** `ARSession`'s
`getCurrentWorldMapWithCompletionHandler:` (a world map is scene reconstruction, and there is no
depth sensor), `captureHighResolutionFrameWithCompletion:` (a depth-capable frame the camera cannot
give), `createReferenceObjectWithTransform:center:extent:completionHandler:` (object scanning reads a
mesh from depth), `getGeoLocationForPoint:completionHandler:` (a geo anchor is not carried yet),
`updateWithCollaborationData:` (shared anchors are not carried yet).

`ARPlaneGeometry`'s `vertices`, `textureCoordinates` and `triangleIndices` are the one place the two
spellings meet: the C surface declares them as pointers and the Swift surface, which the header
refines, as arrays. A plane that has only been **detected** has no mesh, so the C answer is a null
pointer with a count of zero and the Swift answer an empty array, and both are the truth rather than
a fabricated mesh.

## The sixty-eight `-init` and `+new` rows, decided from Apple's own metadata and not from a header

**This section replaces an earlier one that decided these rows from the header alone. That was
wrong, and the correction is the measurement below.**

`NS_UNAVAILABLE` on a declaration says the SDK does not want a caller to use it. It does **not** say
the method is absent from the class, and for ARKit the two come apart. Measured over ARKit of the
arm64e shared cache of iOS 16.0 with `modules/apple/objc.lua`'s own inventory
(`CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/16.0/dyld_shared_cache_arm64e`,
143137 classes read), each class's **own** method list answers:

| | rows | what Apple's own metadata says | status |
| --- | --- | --- | --- |
| `-[X init]` on a class that defines it | 8 | `-init` IS in the class's own instance selector list | **implemented** |
| `-[X init]` on a class that does not | 26 | `-init` is NOT in the class's own instance selector list | absent |
| `+[X new]`, every class | 34 | `+new` is in the OWN class selector list of **0 of 143137** classes | absent |

The eight classes that define `-init` of their own, and so the eight implemented rows:

`ARConfiguration`, `ARWorldTrackingConfiguration`, `AROrientationTrackingConfiguration`,
`ARFaceTrackingConfiguration`, `ARImageTrackingConfiguration`, `ARObjectScanningConfiguration`,
`ARGeoTrackingConfiguration`, `ARCamera`.

`ARConfiguration` is the one that shows why the header alone could not decide it. Its own header says

```objc
- (instancetype)init NS_UNAVAILABLE;      // ARConfiguration.h:211
+ (instancetype)new NS_UNAVAILABLE;      // ARConfiguration.h:212
```

and Apple's runtime metadata has `-init` in the class's own list all the same. Both are true at once:
the mark is the SDK telling a caller not to build the abstract base directly, and the method is there
underneath, which is exactly what the six configuration subclasses chain to - their own blocks
re-declare `- (instancetype)init;` with no mark at `ARConfiguration.h:114`. So `ARConfiguration.m`
now defines `-init`, and `initCharonCommon` - the private seam the subclasses already chained to -
goes through it.

**The controls, without which the read means nothing.** 28851 of the cache's classes carry `-init` in
their own instance list and `NSObject` carries it too, so the reader does see a class's own methods;
and `+new` is in the own class list of 0 of 143137 classes, which is the whole point - `+new` is
`NSObject`'s and is inherited rather than redeclared, so no Apple class has ever defined one and the
port must not either. Both numbers come from the same pass over the same cache.

Where the header and Apple's own metadata agree - the 26 rows whose class does not define `-init`,
and all 34 `+new` rows - the port follows the **metadata**: defining the method would put a selector
in the port's class that Apple's class does not have, changing no behaviour (`alloc` reaches the
`-init` `NSObject` inherits either way) while moving a status. Those rows are `absent`, which is the
registry's word for "measured, and not carried".

Nothing here rests on the hardware. The release carries no ARKit at all - 0 of the 11378 class names
of the 6.1.3 armv7 cache begin `AR`, as this file's `ARDepthData` row records - so what these rows
answer is the port's own metadata against Apple's, and Apple's answer is now read off Apple's own
image rather than off a header.
