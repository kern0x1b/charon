# ARConfiguration and its subclasses, iOS 11.0 and 12.0

Introduced in iOS 11.0, with two more subclasses in 12.0: the description of
what an augmented-reality session is asked to do. What an application asks first
is whether the device can run one at all, so that is what is carried.

Source: ARKit of the arm64 shared cache of iOS 12.0, read with the symbols of
the image: `+[ARConfiguration isSupported]` at `0x19d3b54a0`, a jump into
`ARDeviceSupported`, a value computed once from the hardware and kept, and
`+[ARWorldTrackingConfiguration isSupported]` at `0x19d3cfaf4`, which asks the
hardware in its own way; the class lists of the image give the same method on
`ARFaceTrackingConfiguration`, `ARImageTrackingConfiguration` and
`ARObjectScanningConfiguration`. The header of SDK 16.4 says of the property
that it determines whether this device supports the configuration. The host's
ARKit through Mac Catalyst answers NO for every configuration below. iOS 11.0
has no ARKit in the cache this package holds for that release, which is an iPod
touch's, and the arm64e caches of 16.0 and 18.0 come
without the symbol file the reader needs, so neither was read.

## What is carried

`ARConfiguration`, `ARWorldTrackingConfiguration`,
`AROrientationTrackingConfiguration`, `ARFaceTrackingConfiguration`,
`ARImageTrackingConfiguration` and `ARObjectScanningConfiguration`, so that a
program that asks `ARWorldTrackingConfiguration.isSupported` before it does
anything else links and gets an answer.

- `+isSupported` answers **NO** on each. Apple documents ARKit as needing an A9
  chip or later, and the iPhone 4S and the iPad 2 have an A5; the answer is
  faithful, not a refusal.
- The class hierarchy is the release's: each of the five is a subclass of
  `ARConfiguration`, which is a subclass of `NSObject`.
- A copy is a new object of the same class. A configuration that cannot run
  holds no settings, so the copy has nothing to copy.
- `ARErrorDomain` is `com.apple.arkit.error` and
  `ARReferenceObjectArchiveExtension` is `arobject`, both read from the release
  and from the host.

## What is absent, and why

Every setting of a configuration - the world alignment, the plane detection, the
detection images and objects, the initial world map, the video formats, the
environment texturing, the audio and the auto focus - is absent, and so are the
session, the frame, the anchors, the camera, the views and the delegates. A
session needs a camera pipeline, a motion coprocessor and a chip the hardware of
this release does not have. `respondsToSelector:` answers no for each of those
and an unchecked call raises, which is the honest thing for an application that
was written to ask `isSupported` first and go no further.

The registry says which, entry by entry; the members that came in iOS 13 and
after are outside this batch.
