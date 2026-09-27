// The subclasses' own settings: what the camera and the tracker honour, and what needs hardware
// this device has not. A setting that needs a sensor it has not is `@dynamic`, which is the honest
// spelling: the accessor is declared, the library does not answer it, and a call raises rather than
// quietly reporting a value nothing is behind.

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
    self = [super initCharonCommon];
    if (self)
        _planeDetection = ARPlaneDetectionHorizontal;
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

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

+ (BOOL)isSupported
{
    // A world-tracking session is a camera and a gyroscope, which is what this device has.
    return [CharonARTracker isSupported];
}

@end

@implementation AROrientationTrackingConfiguration

- (instancetype)init
{
    self = [super initCharonCommon];
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

+ (BOOL)isSupported
{
    // The gyroscope alone, which is the one sensor this class needs and the one it was named for.
    Class manager = NSClassFromString(@"CMMotionManager");
    return [manager isAvailable];
}

@end

@implementation ARFaceTrackingConfiguration

- (instancetype)init
{
    self = [super initCharonCommon];
    return self;
}

+ (instancetype)new { return [[self alloc] init]; }

+ (NSInteger)supportedNumberOfTrackedFaces { return 0; }
+ (BOOL)supportsWorldTracking { return NO; }

- (BOOL)isAutoFocusEnabled { return YES; }
- (void)setAutoFocusEnabled:(BOOL)autoFocusEnabled { (void)autoFocusEnabled; }

- (NSInteger)maximumNumberOfTrackedFaces { return 0; }
- (void)setMaximumNumberOfTrackedFaces:(NSInteger)maximumNumberOfTrackedFaces { (void)maximumNumberOfTrackedFaces; }

- (BOOL)isWorldTrackingEnabled { return NO; }
- (void)setWorldTrackingEnabled:(BOOL)worldTrackingEnabled { (void)worldTrackingEnabled; }

+ (BOOL)isSupported
{
    // A face is measured by a depth sensor across the face, and this device has none: no TrueDepth, and
    // no LiDAR either. Apple answers NO for a device without the sensor, and so does this.
    return NO;
}

@end
