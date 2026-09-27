# The configurations, and what each one needs from the hardware

Six configurations, six answers, and the answers differ because the *sensors* differ. The old
registry gave them all one reason, "ARKit asks for an A9 chip or later", which is a statement about
a chip and not about what is missing.

Source for the framework's own side: ARKit of the arm64 shared cache of iOS 12.0, read with the
image's symbols — `+[ARConfiguration isSupported]` at `0x19d3b54a0`, a jump into `ARDeviceSupported`,
a value computed once from the hardware and kept, and `+[ARWorldTrackingConfiguration isSupported]`
at `0x19d3cfaf4`, which asks the hardware in its own way. The header of SDK 26.2 says of the
property that it determines whether this device supports the configuration.

Source for *this* device's side: the armv7 shared cache of iOS 6.1.3, read with
`modules/apple/objc.lua` — `AVCaptureDevice` with 100 instance methods, `AVCaptureVideoDataOutput`
with 26, `CMMotionManager` with 74 from CoreMotion, `CLLocationManager` with 81, and no depth and no
face class of any kind.

| configuration | `+isSupported` | the sensors it needs | this device |
| --- | --- | --- | --- |
| `ARConfiguration` | YES | a camera and motion | has both |
| `ARWorldTrackingConfiguration` | YES | a camera and a gyroscope | has both |
| `AROrientationTrackingConfiguration` | YES | a gyroscope | has one |
| `ARPositionalTrackingConfiguration` | YES | a camera and a location service | has both |
| `ARImageTrackingConfiguration` | YES | a camera | has one |
| `ARBodyTrackingConfiguration` | YES | a camera, and the front one for the body | has one |
| `ARFaceTrackingConfiguration` | **NO** | a depth sensor across the face | has none |
| `ARObjectScanningConfiguration` | **NO** | scene depth, to read a mesh from | has none |

Two of the NO answers are worth being careful about, because they are *not* chip answers even
though Apple gates them on one:

- **A face is measured, not inferred.** `ARFaceAnchor`'s geometry is a depth map across the face,
  and `ARFaceTrackingConfiguration` is refused on a device with no TrueDepth. This one is a genuine
  hardware wall, and the answer is the one Apple documents.
- **A body is inferred, not measured.** A body is a pose estimated from the frames the camera
  already gives; there is no sensor of its own. So the configuration answers YES on a device with a
  front camera, and the estimator is the work, not the hardware. The same holds for
  `ARMatteGenerator` (person segmentation on the frames) and `AREnvironmentProbeAnchor` (a cube map
  of the light, assembled from the frames).

What `ARSession` does with the answer: a session run with a configuration whose `+isSupported` is NO
does not start, and the application is told through `session:didFailWithError:` with the reason the
hardware gave. A session run with one that is YES starts the release's own
`AVCaptureVideoDataOutput` and `CMMotionManager` and reports frames.

## A note on the enum that is not there

`ARPlaneAnchorAlignment` in the SDK's C headers has exactly two cases, `Horizontal` and `Vertical`;
Apple's "not determined" case is a Swift-side addition the C surface does not carry. A detected
plane here is reported as `Horizontal`, because a level surface is what the detector found — and it
is a detection, not a measurement, because there is no depth sensor to measure one. See
`ARKit.md` for why that matters to `ARPlaneGeometry`'s empty vertex buffers.
