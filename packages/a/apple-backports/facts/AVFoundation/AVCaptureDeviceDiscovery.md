# Finding the cameras and microphones, iOS 10

Introduced in iOS 10.0: `AVCaptureDeviceDiscoverySession`, `-[AVCaptureDevice deviceType]`,
`+[AVCaptureDevice defaultDeviceWithDeviceType:mediaType:position:]` and the device types
`AVCaptureDeviceTypeBuiltInMicrophone`, `...WideAngleCamera` and `...TelephotoCamera`; iOS 10.2 added
`AVCaptureDeviceTypeBuiltInDualCamera`.

Source: AVFoundation of the armv7s cache of iOS 10.3.4, read method by method; AVFoundation of iOS 6.0 for what it
already has; the host's own AVFoundation run beside the port through Mac Catalyst (`host/avcapture`); the device test
`avcapture.m` on the cameras and microphone of an iPad 2.

It lives in a library of its own, `libAVFoundationBackports.dylib`, built with the `avfoundation` config, so that only a
port that looks for cameras loads AVFoundation.

## The device types

The four constants are strings whose values are their own names, and `AVCaptureDeviceTypeBuiltInDuoCamera`, which
10.3.4 also exports, is the same string as the dual camera; the header of iOS 11 no longer names it and it is not carried.

`-[AVCaptureDevice deviceType]` of the base class answers the empty string. The release's two subclasses answer for
themselves: the audio device always the built-in microphone, the video device the type its capture source names, one of
wide angle, telephoto and dual. iOS 6 has one kind of camera, the wide angle one, on the back and on the front, and one
microphone, so the port answers by the media types the device has: video only is the wide angle camera, audio only the
built-in microphone, and any other combination the empty string.

## Finding devices

`+[AVCaptureDevice defaultDeviceWithDeviceType:mediaType:position:]` answers nothing when it is sent to a subclass and
raises `NSInvalidArgumentException` for a nil type, with the reason `*** +[AVCaptureDevice defaultDeviceWithDeviceType:mediaType:position:]
The deviceType cannot be nil` (the host's own prefix names its class of the day; the tail is the same). Otherwise it is the first
device of the list a discovery session for that one type would give.

A discovery session takes its list when it is made. The release collects the video devices when any of the wide angle,
telephoto and dual types is asked for, then the audio devices when the microphone is, and keeps those that are connected,
whose position is the one asked for unless it is unspecified, that have the media type asked for unless it is nil, and whose
type is one of those asked for. A nil or empty list of types finds nothing.

The order differs by the release a program is linked against, and the header says so: unsorted for iOS 10, and for iOS 11 and
later in the order of the types given, and inside one type by position, unspecified before back before front. A program
built now is linked against a later release, so the port gives that order. The host's own AVFoundation agrees on the
combinations of types, media types and positions the test asks for.

`-description` is `<Class: pointer device types: [WideAngleCamera, Microphone], media type: Any, position: Unspecified>`,
the types named without their prefix, `Any` for no media type and `Unspecified`, `Back`, `Front` or `<Unknown>` for the
position.

## What the hardware has

An iPhone 4S and an iPad 2 have a camera on each side and one microphone. The telephoto and dual cameras are not there, so
a search for them finds nothing, as it does on an iPhone 7 for a type it does not have. Not carried: the multi-camera
device sets of iOS 13, and every other type of iOS 10 and later.

## What differs on the host

macOS names its microphone `AVCaptureDeviceTypeMicrophone` and answers nil to `defaultDeviceWithDeviceType:` for the
built-in microphone type; the test leaves the microphone's type and default out of the comparison, and holds the
microphone to what 10.3.4 does with it, on the device.
