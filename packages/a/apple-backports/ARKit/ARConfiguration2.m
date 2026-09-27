// The subclasses' own settings: what the camera and the tracker honour, and what needs hardware
// this device has not. A setting that needs a sensor it has not is `@dynamic`, which is the honest
// spelling: the accessor is declared, the library does not answer it, and a call raises rather than
// quietly reporting a value nothing is behind.

#import <ARKit/ARKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>

#import "CharonARTracker.h"

// As in ARConfiguration.m: the settings that arrived after the release's own ARKit are carried with
// the header's own guard, and the values behind them are this device's.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// `ARConfiguration` is abstract and its initialiser is declared unavailable, which is the SDK telling a
// caller not to build one; a subclass is exactly what is being built here, so the calls that chain
// to it are the base class saying yes.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunavailable-function"

/// The auto focus every configuration that has a camera declares, and this camera has one.
@interface ARConfiguration (CharonAutoFocus)
@property (nonatomic, assign, getter=isAutoFocusEnabled) BOOL autoFocusEnabled;
@end

@implementation ARWorldTrackingConfiguration
{
    ARPlaneDetection _planeDetection;
    AREnvironmentTexturing _environmentTexturing;
}

- (instancetype)init
{
    // `ARConfiguration`'s own initialiser is declared unavailable because it is abstract, so a
    // subclass starts from NSObject and carries its own state; the header's default for a world
    // map is horizontal plane detection.
    self = [super init];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // A world-tracking session is a camera and a gyroscope, which is what this device has.
    return [CharonARTracker isSupported];
}

+ (BOOL)supportsUserFaceTracking { return NO; }
+ (BOOL)supportsAppClipCodeTracking { return NO; }

+ (BOOL)supportsSceneReconstruction:(ARSceneReconstruction)sceneReconstruction
{
    // A mesh of the scene is read out of scene depth, and a depth sensor is what this device has not.
    (void)sceneReconstruction;
    return NO;
}

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (ARPlaneDetection)planeDetection { return _planeDetection; }
- (void)setPlaneDetection:(ARPlaneDetection)planeDetection { _planeDetection = planeDetection; }

- (AREnvironmentTexturing)environmentTexturing { return _environmentTexturing; }
- (void)setEnvironmentTexturing:(AREnvironmentTexturing)environmentTexturing { _environmentTexturing = environmentTexturing; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; planeDetection = %lu>",
            NSStringFromClass([self class]), self, (unsigned long)_planeDetection];
}

// The settings a caller sets that this device cannot honour behind. Each is declared by the SDK's
// own header and is not answered here, which is what `@dynamic` says.
@dynamic initialWorldMap;
@dynamic detectionImages;
@dynamic detectionObjects;
@dynamic wantsHDREnvironmentTextures;
@dynamic automaticImageScaleEstimationEnabled;
@dynamic maximumNumberOfTrackedImages;
@dynamic collaborationEnabled;
@dynamic userFaceTrackingEnabled;
@dynamic appClipCodeTrackingEnabled;
@dynamic sceneReconstruction;

#pragma clang diagnostic pop

@end

@implementation AROrientationTrackingConfiguration

- (instancetype)init
{
    self = [super init];
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // The gyroscope alone, which is the one sensor this class needs and the one it was named for.
    return [CMMotionManager new].deviceMotionAvailable;
}

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

@end

@implementation ARPositionalTrackingConfiguration
{
    ARPlaneDetection _planeDetection;
}

- (instancetype)init
{
    self = [super init];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // A tracked image and a place to put it: the camera, and a location service.
    if (![CharonARTracker isSupported])
        return NO;
    return [CLLocationManager class] != nil;
}

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (ARPlaneDetection)planeDetection { return _planeDetection; }
- (void)setPlaneDetection:(ARPlaneDetection)planeDetection { _planeDetection = planeDetection; }

#pragma clang diagnostic pop

@dynamic initialWorldMap;

@end

@implementation ARImageTrackingConfiguration
{
    NSInteger _maximumNumberOfTrackedImages;
}

- (instancetype)init
{
    self = [super init];
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // A tracked image is found in the camera's frames and needs no depth sensor.
    return [CharonARTracker isSupported];
}

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (NSInteger)maximumNumberOfTrackedImages { return _maximumNumberOfTrackedImages; }
- (void)setMaximumNumberOfTrackedImages:(NSInteger)maximumNumberOfTrackedImages {
    _maximumNumberOfTrackedImages = maximumNumberOfTrackedImages;
}

@dynamic trackingImages;

#pragma clang diagnostic pop

@end

@implementation ARBodyTrackingConfiguration
{
    ARPlaneDetection _planeDetection;
    AREnvironmentTexturing _environmentTexturing;
}

- (instancetype)init
{
    self = [super init];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // A body is a pose estimated from the camera's own frames, which needs no sensor of its own, and
    // the front camera. This device has one, so the answer is what the hardware gives.
    return [CharonARTracker hasFrontCamera];
}

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

#pragma clang diagnostic pop

@end

@implementation ARFaceTrackingConfiguration

- (instancetype)init
{
    self = [super init];
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // A face is measured by a depth sensor across the face, and this device has none: no TrueDepth,
    // and no LiDAR either. Apple answers NO for a device without the sensor, and so does this.
    return NO;
}

+ (NSInteger)supportedNumberOfTrackedFaces { return 0; }
+ (BOOL)supportsWorldTracking { return NO; }

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (NSInteger)maximumNumberOfTrackedFaces { return 0; }
- (void)setMaximumNumberOfTrackedFaces:(NSInteger)maximumNumberOfTrackedFaces { (void)maximumNumberOfTrackedFaces; }

- (BOOL)isWorldTrackingEnabled { return NO; }
- (void)setWorldTrackingEnabled:(BOOL)worldTrackingEnabled { (void)worldTrackingEnabled; }

#pragma clang diagnostic pop

@end

@implementation ARObjectScanningConfiguration
{
    ARPlaneDetection _planeDetection;
}

- (instancetype)init
{
    self = [super init];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (BOOL)isSupported
{
    // Object scanning reads a mesh out of the depth the camera sees; without a depth sensor there is
    // no mesh to read, and the framework is right to say so.
    return NO;
}

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (ARPlaneDetection)planeDetection { return _planeDetection; }
- (void)setPlaneDetection:(ARPlaneDetection)planeDetection { _planeDetection = planeDetection; }

#pragma clang diagnostic pop

@end
