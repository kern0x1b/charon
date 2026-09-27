# ARSession, ARFrame, ARCamera, and the anchors

What a session is: a camera, a gyroscope and a tracker, handing the application one frame at a
time. `ARSession.m`, `ARFrame.m` and `ARAnchor.m`.

## The run loop

`ARSession` owns the release's own `AVCaptureVideoDataOutput` and `CMMotionManager` — both measured
present in the armv7 shared cache of iOS 6.1.3, the first with 26 instance methods and the second
with 74 — and asks the tracker for a pose per frame. Delegate calls are made on
`delegateQueue` when the caller named one and on the main queue when it did not, which is what the
SDK's header says.

`run(_:options:)` behaves as the header says: a session already running transitions to the new
configuration, `ARSessionRunOptionResetTracking` restarts the tracker, and
`ARSessionRunOptionRemoveExistingAnchors` drops the anchors. `ARSessionRunOptionResetSceneReconstruction`
is accepted and does nothing, because there is no scene reconstruction here to reset: there is no
depth sensor to reconstruct a scene from.

A session run with a configuration whose `+isSupported` is NO **does not start**. The application is
told through `session:didFailWithError:`, with the reason the hardware gave, rather than being
allowed to run a session that could never track.

## Frames

`ARFrame` carries the camera's transform and the device's transform, the time each was true, the
image size, the light estimate, the anchors that were in the world, and what a frame does **not**
have:

- `capturedDepthData` answers an empty dictionary. A depth photograph is a depth sensor's output and
  this device has none; an empty dictionary is the contract's own answer for a frame without one.
- `hasCapturedDepthData` and `hasDisplayGeometry` answer NO, for the same reason.
- `update(withDictionary:)` answers NO: a frame from another run cannot be applied to this one.
- `worldMappingStatus` answers the framework's "not available" until a world map is added.

`ARCamera` reports the pose, the image size, the light estimate read from the frame, the focal
length from the image size, the tracking state, and `hasDepth` NO — again because there is no depth
sensor behind it.

## Anchors

An `ARAnchor` is a name, a transform and nothing else, so an anchor an application adds survives
into every frame at the pose it was added at, and is found again by its identifier. `ARAnchor` is
`NSObject` with a copy and a `isEqualToAnchor:` that compares the identifier and the transform, and
`ARAnchorCopying` is carried with it.

`ARPlaneAnchor` and `ARPlaneGeometry` are the detector's output, and they are **detections**: a
detected plane has a centre, an extent, an alignment that says what the detector found, and **no
vertex, texture-coordinate or triangle-index arrays**, because there is no mesh to give. See
`ARKit.md`.

`ARPointCloud` gives its points as `NSData` of three floats each and answers NO for
`identifier:atIndex:`, because a monocular system has no stable point indices to give back.

## Hit test and raycast

Both go against the planes the detector found, and both are in `ARAnchor.m`. A hit test prefers a
tracked feature within five centimetres of the ray and otherwise reports a plane; a raycast
substitutes into the plane equations and keeps the nearest. `ARRaycastQuery` is in the SDK's own
spelling — a world `origin`, a world `direction`, a `target` and an `alignment` — and
`ARTrackedRaycast` keeps its result, stopping in Apple's own rule: it stops being reported once the
camera has moved further than the ray's own length, because past that the result no longer describes
this frame.

`ARSessionDelegate` and `ARSessionObserver` are carried: the frame and anchor callbacks, and the
session's own state changes, which the tracker raises as it starts and stops. `ARTrackable` is
carried with them — an anchor that follows a thing in the world is what an anchor added at a pose
does here.
