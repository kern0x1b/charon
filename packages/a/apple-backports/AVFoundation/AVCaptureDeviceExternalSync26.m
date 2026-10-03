// AVCaptureDeviceExternalSync26.m - the eleven members of iOS 26's external sync and locked frame duration,
// in one object.
//
// WHAT THE TWO FEATURES ARE, in the header's own words, because that is what every answer below follows.
//
//   Locked frame duration (:288-303 of AVCaptureInput.h): "Setting this property guarantees the intra-frame
//   duration delivered by the device input is precisely the frame duration you request", and the header says
//   where the smallest one a given device can take comes from - "Query AVCaptureDevice/
//   minSupportedLockedVideoFrameDuration to find the minimum value supported by this AVCaptureDeviceInput".
//   So a locked duration is exactly as capable as the device's own minimum, and the header says what that
//   minimum is where the feature is absent: "kCMTimeInvalid is returned when the device or its current
//   configuration does not support locked frame rate" (AVCaptureDevice.h:383).
//
//   External sync (:311-350): an input can follow an AVExternalSyncDevice - a genlock or a house-sync box -
//   at a frame duration the box drives, and the header says what the device reports where it is absent:
//   "This property returns kCMTimeInvalid when the device's current configuration does not support external
//   sync device following" (AVCaptureDevice.h:393).
//
// This release has neither. Measured, 6.1.3's AVCaptureDevice owns no member of either feature
// (tools/corpus/objc-inventory.lua over the 6.1.3 armv7 cache), its capture session has no frame-duration
// lock of any kind, and no external sync hardware exists to follow. So:
//
//   -minSupportedLockedVideoFrameDuration   kCMTimeInvalid, the header's own sentence for the case.
//   -minSupportedExternalSyncFrameDuration  kCMTimeInvalid, the same sentence for the other feature.
//   -isLockedVideoFrameDurationSupported    the DEVICE's minimum, because the header says that minimum IS
//                                          this input's minimum; kCMTimeInvalid there means NO here.
//   -isExternalSyncSupported                the same derivation from -minSupportedExternalSyncFrameDuration.
//   -videoFrameDurationLocked                NO, by the header's own definition - "Returns true when an
//                                          AVCaptureDeviceInput associated with the device has its
//                                          activeLockedVideoFrameDuration property set to something other
//                                          than kCMTimeInvalid" (:376) - read with this port's own input:
//                                          no input here can be, because -setActiveLockedVideoFrameDuration:
//                                          refuses every valid value (below).
//   -activeLockedVideoFrameDuration         kCMTimeInvalid, the header's own "In order to disable locked video
//                                          frame duration, set this property to kCMTimeInvalid" (:288) and its
//                                          default (:281). Nothing is kept: the setter refuses every value
//                                          that is not kCMTimeInvalid, so there is no last accepted one.
//   -isFollowingExternalSyncDevice          NO: nothing is followed, because -followExternalSyncDevice:...:...
//                                          refuses (below).
//   -activeExternalSyncVideoFrameDuration   kCMTimeInvalid, "The value of this readonly property is
//                                          kCMTimeInvalid unless the AVExternalSyncDevice is actively
//                                          driving the AVCaptureDeviceInput" (:338).
//   -externalSyncDevice                     nil, "This property returns nil when an external sync device is
//                                          disconnected or fails to calibrate" (:345) - and none is ever
//                                          followed here. AVExternalSyncDevice is forward-declared and never
//                                          instantiated: its class, its six properties, its -init and +new, its
//                                          discovery session and its delegate protocol are a family of their
//                                          own rows.
//   -followExternalSyncDevice:...:delegate: refuses with Apple's own reason, measured on this host:
//                                          "*** -[AVCaptureDeviceInput followExternalSyncDevice:videoFrameDuration:delegate:]
//                                          followExternalSyncDevice:videoFrameDuration:delegate: is not supported on this
//                                          device. Check the device minSupportedExternalSyncFrameDuration property."
//                                          The header's own rule is the same: "Calling this method throws an
//                                          NSInvalidArgumentException if AVCaptureDeviceInput/
//                                          externalSyncSupported returns false" (:331).
//   -unfollowExternalSyncDevice             returns. "This method stops your input from syncing to the
//                                          external sync device you specified" (:348), and there is none:
//                                          nothing to stop. Measured on the host: it returns.
//
// ONE DIVERGENCE FROM THE HOST, measured and named rather than smoothed over: sent a valid CMTime,
// -setActiveLockedVideoFrameDuration: on the host RETURNS and keeps it (measured: 1/30 afterwards), while the
// header says twice that a valid value throws when the device's minSupportedLockedVideoFrameDuration is
// kCMTimeInvalid (:302) and that setting it while lockedVideoFrameDurationSupported is false throws (:303). The
// host accepts a value it then does not honour - its own device still reports -isVideoFrameDurationLocked NO
// after the set (measured) - and the port refuses, which is the header's rule and not a value nothing can
// reach. The reason is this port's own: the header names NSInvalidArgumentException for it and no words.
#import "CharonAVCaptureDeviceExternalSync26.h"

// The two device minima, declared HERE and not in the header, because the host harness drops the port's own
// header when it compiles a copy (so the copy cannot replace Apple's members in that process) and a category
// interface that travels with the source compiles in both. -[AVCaptureDevice minSupportedLockedVideoFrameDuration]
// and -[AVCaptureDevice minSupportedExternalSyncFrameDuration] are this port's own members, declared in
// CharonAVCaptureDeviceExternalSync26.h and defined in this file; this interface is what lets the two helpers
// below call them through a typed receiver. It is a declaration, not a definition: no selector is added here.
@interface AVCaptureDevice (CharonCaptureDeviceExternalSync26Minima)
- (CMTime)minSupportedLockedVideoFrameDuration;
- (CMTime)minSupportedExternalSyncFrameDuration;
@end

// The device's own minimum, which the header says is this input's minimum, so that the two support flags are
// derived rather than written: "Query AVCaptureDevice/minSupportedLockedVideoFrameDuration to find the minimum
// value supported by this AVCaptureDeviceInput" (AVCaptureInput.h:290). kCMTimeInvalid is the header's own
// answer for a device that cannot lock (:383), and an invalid time is one with no value and a timescale of 1 -
// which is what CMTIME_IS_INVALID reads.
static BOOL charon_device_supports_locked_frame_duration(AVCaptureDevice *device)
{
    return device ? !CMTIME_IS_INVALID([device minSupportedLockedVideoFrameDuration]) : NO;
}

static BOOL charon_device_supports_external_sync(AVCaptureDevice *device)
{
    return device ? !CMTIME_IS_INVALID([device minSupportedExternalSyncFrameDuration]) : NO;
}

@implementation AVCaptureDevice (CharonCaptureDeviceExternalSync26)

- (BOOL)isVideoFrameDurationLocked
{
    return NO;
}

- (CMTime)minSupportedLockedVideoFrameDuration
{
    return kCMTimeInvalid;
}

- (BOOL)isFollowingExternalSyncDevice
{
    return NO;
}

- (CMTime)minSupportedExternalSyncFrameDuration
{
    return kCMTimeInvalid;
}

@end

@implementation AVCaptureDeviceInput (CharonCaptureDeviceInputExternalSync26)

- (BOOL)isLockedVideoFrameDurationSupported
{
    return charon_device_supports_locked_frame_duration(self.device);
}

- (CMTime)activeLockedVideoFrameDuration
{
    return kCMTimeInvalid;
}

- (void)setActiveLockedVideoFrameDuration:(CMTime)activeLockedVideoFrameDuration API_AVAILABLE(ios(26.0))
{
    // The header's own two rules, both about a device that cannot lock: "If you set this property to a valid
    // value while the receiver's AVCaptureDevice/minSupportedLockedVideoFrameDuration is kCMTimeInvalid, it
    // throws an NSInvalidArgumentException" (:302), and "If you set this property while the receiver's
    // lockedVideoFrameDurationSupported property returns false, it throws an NSInvalidArgumentException"
    // (:303). kCMTimeInvalid is always allowed - it is how a locked duration is disabled (:288) - and nothing
    // is kept, because a setter that accepts only kCMTimeInvalid has no other value to remember.
    if (CMTIME_IS_INVALID(activeLockedVideoFrameDuration))
        return;
    [NSException raise:NSInvalidArgumentException
                format:@"*** -[AVCaptureDeviceInput %@] The device's minSupportedLockedVideoFrameDuration is"
                       @" kCMTimeInvalid, so it cannot lock a frame duration"
                       @" (AVCaptureInput.h:302), and the property is left at kCMTimeInvalid",
                       NSStringFromSelector(_cmd)];
}

- (BOOL)isExternalSyncSupported
{
    return charon_device_supports_external_sync(self.device);
}

- (CMTime)activeExternalSyncVideoFrameDuration
{
    return kCMTimeInvalid;
}

- (AVExternalSyncDevice *)externalSyncDevice
{
    return nil;
}

- (void)followExternalSyncDevice:(AVExternalSyncDevice *)externalSyncDevice
                 videoFrameDuration:(CMTime)frameDuration
                        delegate:(id<AVExternalSyncDeviceDelegate>)delegate API_AVAILABLE(ios(26.0))
{
    // The header's own rule (:331) and Apple's own reason for it, measured on this host and raised unchanged:
    // the text names this port's class, which is the class the header declares the method on.
    [NSException raise:NSInvalidArgumentException
                format:@"*** -[AVCaptureDeviceInput %@] %@ is not supported on this device. Check the device"
                       @" minSupportedExternalSyncFrameDuration property.",
                       NSStringFromSelector(_cmd), NSStringFromSelector(_cmd)];
}

- (void)unfollowExternalSyncDevice
{
    // Nothing is followed, so there is nothing to stop. Measured on the host: this returns rather than
    // raising, and the port does the same rather than inventing a refusal the header names nowhere.
}

@end
