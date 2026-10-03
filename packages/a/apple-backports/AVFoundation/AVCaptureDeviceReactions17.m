// AVCaptureDeviceReactions17.m - the reaction-effects half of the capture-device surface iOS 17 added, and
// the two members iOS 17.2 added to AVCaptureDeviceFormat, as two objects: one release's API each.
//
// WHAT THE PORT ANSWERS, and where every answer comes from. Two oracles, and which one speaks depends on the
// row:
//
//   * this host's own AVFoundation, measured by tests/backports/host/avf-capabilities against this MacBook
//     Pro's built-in camera, which has reactions and background replacement and none of the rest;
//   * the SDK 26.2 header's own words for the case where the hardware does not have the feature, which is
//     this port's case: every device of this port's bands is an iPhone 4S or an iPad 2, and a reaction effect
//     is a camera feature of the devices Apple shipped from 2016 on.
//
// Row by row, with the header line that decides it:
//
//   -availableReactionTypes          empty set. "Returns a list of reaction types which can be passed to
//                                    performEffectForReaction" (AVCaptureDevice.h:2478) and "The list may
//                                    differ between devices" (:2481): this camera supports none, so the list
//                                    is empty. The host's camera lists all eight (measured), for the same
//                                    reason it lists them: its camera has the hardware.
//   -canPerformReactionEffects       NO. "returns YES when resources for reactions are available on the
//                                    device instance" (:2471).
//   -reactionEffectsInProgress       an empty array: nothing can start a reaction, so none is running.
//   +reactionEffectsEnabled          the DOCUMENTED rule, read out of the application: "On iOS, Reaction
//                                    Effects are enabled by default for video conferencing applications
//                                    (apps that use \"voip\" as one of their UIBackgroundModes). Non video
//                                    conferencing applications may opt in ... NSCameraReactionEffectsEnabled"
//                                    (:2448-2450). The host answers YES because its own rule is "enabled by
//                                    default for all applications" on macOS (:2447), which is a different
//                                    platform's rule and not this one's.
//   +reactionEffectGesturesEnabled   the DOCUMENTED default: "By default, gesture detection is enabled"
//                                    (:2461), which iOS 17.4 lets an application change with
//                                    NSCameraReactionEffectGesturesEnabledDefault in its Info.plist. The
//                                    host answers NO because it reflects this Mac's Control Center Gestures
//                                    setting (:2458); a release with no such setting stays at its default.
//   +systemPreferredCamera           nil, measured on the host as nil as well: the camera the system
//                                    prefers is a choice between several cameras, and this release's
//                                    devices have one.
//   +userPreferredCamera             nil until an application sets it, and the setter's value is read
//                                    back. The host answers nil until set and then reads its own set value
//                                    back (measured); it does not answer nil again after a nil is set, which
//                                    is a system-default fallback of a release with several cameras and is
//                                    not reproduced here, since there is nothing to fall back to.
//   -performEffectForReaction:        raises. "The reactionType requested must be one of those listed in
//                                    availableReactionTypes or an exception will be thrown" (:2496): the
//                                    list is empty, so every type is one that must not be passed. The
//                                    header names no exception for it, and the port raises
//                                    NSInvalidArgumentException - the name the two refusals this host's own
//                                    class raises for unsupported arguments use (measured:
//                                    "*** -[AVCaptureDALDevice setAutoVideoFrameRateEnabled:] Not supported"
//                                    and "*** -[AVCaptureDeviceInput setMultichannelAudioMode:] Not supported").
//                                    "Performing a reaction when canPerformReactionEffects is NO is
//                                    ignored" (:2496) is the other half of the same rule, and it is what a
//                                    type that IS available would get; no type is available here.
//   Format -reactionEffectsSupported NO, the same hardware answer for a format. The host's camera answers
//                                    YES for all seven of its formats (measured).
//   Format -videoFrameRateRangeForReactionEffectsInProgress
//                                    nil, the header's own nullability for a format that cannot run a
//                                    reaction. Every format of the host's camera reports
//                                    reactionEffectsSupported YES and a 15-30 AVFrameRateRange (measured),
//                                    so the NO case cannot be read off this host and the pairing comes from
//                                    the header.
//   Format -supportedVideoZoomRangesForDepthDataDelivery
//                                    an empty array, and the host's own camera answers an empty array here
//                                    too (measured): no zoom range of this camera feeds depth delivery.
//   Format -zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported
//                                    NO, measured NO on the host's own camera as well.
//
// THE BANDS. Both objects are categories on classes the release carries, so they export no symbol of their
// own and band() keeps them in every band from the floor up - which is what every category in this package
// does, and what the port wants: from 17.0 up, the port's answers are the ones for hardware this port's
// devices do not have, and the release's own would be the ones for hardware they do.
#import "CharonAVCaptureDeviceReactions17.h"

// The camera an application chose. A class property, so one value for the process, and it is kept here
// rather than in an ivar for the same reason: the release's class cannot be given one by a category.
static AVCaptureDevice *charon_user_preferred_camera;

@implementation AVCaptureDevice (CharonCaptureDeviceReactions17)

- (NSSet<AVCaptureReactionType> *)availableReactionTypes
{
    return [NSSet set];
}

- (BOOL)canPerformReactionEffects
{
    return NO;
}

- (NSArray<AVCaptureReactionEffectState *> *)reactionEffectsInProgress
{
    return [NSArray array];
}

// The header's iOS rule, read out of the application rather than answered with a constant: YES when the
// application is a video conferencing one (voip among its UIBackgroundModes) or has opted in with
// NSCameraReactionEffectsEnabled. Both are the application's own Info.plist, which is where the header says
// they live, and both are read through NSBundle - the public way to read them.
+ (BOOL)reactionEffectsEnabled
{
    NSBundle *bundle = [NSBundle mainBundle];
    id opted_in = [bundle objectForInfoDictionaryKey:@"NSCameraReactionEffectsEnabled"];
    if ([opted_in isKindOfClass:[NSNumber class]] && [opted_in boolValue]) {
        return YES;
    }
    id modes = [bundle objectForInfoDictionaryKey:@"UIBackgroundModes"];
    if ([modes isKindOfClass:[NSArray class]] && [modes containsObject:@"voip"]) {
        return YES;
    }
    return NO;
}

// The header's documented default is enabled; an application may set the default from 17.4 on with
// NSCameraReactionEffectGesturesEnabledDefault, and until the user changes it in Control Center - a setting
// this release does not have - the value stays where it started.
+ (BOOL)reactionEffectGesturesEnabled
{
    id setting = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSCameraReactionEffectGesturesEnabledDefault"];
    if ([setting isKindOfClass:[NSNumber class]]) {
        return [setting boolValue];
    }
    return YES;
}

+ (AVCaptureDevice *)systemPreferredCamera
{
    return nil;
}

+ (AVCaptureDevice *)userPreferredCamera
{
    return charon_user_preferred_camera;
}

+ (void)setUserPreferredCamera:(AVCaptureDevice *)userPreferredCamera
{
    charon_user_preferred_camera = userPreferredCamera;
}

- (void)performEffectForReaction:(AVCaptureReactionType)reactionType
{
    // The header's rule: the type must be one -availableReactionTypes lists. That list is empty, so every
    // type is one the header says raises, and a reaction with canPerformReactionEffects NO is ignored.
    if (![[self availableReactionTypes] containsObject:reactionType]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-%@ is not one of the reaction types this device can perform (availableReactionTypes "
                           @"is empty: this camera has no reaction effects), and -performEffectForReaction: throws "
                           @"for any other type (AVCaptureDevice.h:2496)", NSStringFromSelector(_cmd)];
    }
}

@end

@implementation AVCaptureDeviceFormat (CharonCaptureDeviceFormatReactions17)

- (BOOL)reactionEffectsSupported
{
    return NO;
}

- (AVFrameRateRange *)videoFrameRateRangeForReactionEffectsInProgress
{
    return nil;
}

@end