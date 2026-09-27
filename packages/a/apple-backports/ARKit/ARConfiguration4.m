// ARConfiguration4.m - the 16.0 configurations: a body pose and a tracked place.
//
// Split from ARConfiguration2.m because an object carries the API of one release, beside the
// raycast vocabulary in ARRaycast.m and the skeleton's joint names in ARKitConstants16.m.

#import <ARKit/ARKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>

#import "CharonARKitPrivate.h"
#import "CharonARTracker.h"

// As in ARConfiguration.m: the settings that arrived after the release's own ARKit are carried with
// the header's own guard, and the values behind them are this device's.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// `ARConfiguration` is abstract and its initialiser is declared unavailable, which is the SDK telling a
// caller not to build one; a subclass is exactly what is being built here, so the calls that chain
// to it are the base class saying yes. Because the base class names no designated initialiser that a
// subclass can see - the one it has is private, and a category cannot mark a method designated -
// every -init below is reported as a designated initialiser reaching a non-designated one. The chain
// is the base class's own values and nothing else, so the check has nothing left to add here.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation ARBodyTrackingConfiguration
{
    ARPlaneDetection _planeDetection;
    AREnvironmentTexturing _environmentTexturing;
}

- (instancetype)init
{
    self = [super initCharonCommon];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }


+ (BOOL)supportsAppClipCodeTracking { return NO; }

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (ARPlaneDetection)planeDetection { return _planeDetection; }
- (void)setPlaneDetection:(ARPlaneDetection)planeDetection { _planeDetection = planeDetection; }

- (AREnvironmentTexturing)environmentTexturing { return _environmentTexturing; }
- (void)setEnvironmentTexturing:(AREnvironmentTexturing)environmentTexturing { _environmentTexturing = environmentTexturing; }

@dynamic initialWorldMap;
@dynamic detectionImages;
@dynamic wantsHDREnvironmentTextures;
@dynamic automaticImageScaleEstimationEnabled;
@dynamic automaticSkeletonScaleEstimationEnabled;
@dynamic maximumNumberOfTrackedImages;
@dynamic appClipCodeTrackingEnabled;


+ (BOOL)isSupported
{
    // A body is a pose estimated from the camera's own frames, which needs no sensor of its own, and
    // the front camera. This device has a front camera, so the answer is what the hardware gives.
    return [CharonARTracker hasFrontCamera];
}

@end

@implementation ARPositionalTrackingConfiguration
{
    ARPlaneDetection _planeDetection;
}

- (instancetype)init
{
    self = [super initCharonCommon];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }


- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (ARPlaneDetection)planeDetection { return _planeDetection; }
- (void)setPlaneDetection:(ARPlaneDetection)planeDetection { _planeDetection = planeDetection; }


@dynamic initialWorldMap;

+ (BOOL)isSupported
{
    // A tracked image and a place to put it: the camera, and a location service.
    if (![CharonARTracker isSupported])
        return NO;
    return [CLLocationManager class] != nil;
}

@end