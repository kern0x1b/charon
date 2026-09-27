// ARConfiguration.m - the description of what a session is asked to do, and the four configurations
// that carry it.
//
// `+[ARConfiguration isSupported]` and the three subclasses' own are the whole question an
// application asks before it does anything, and here the answer is the hardware's: a configuration
// that needs the camera and the gyroscope is supported on a device that has both, and one that
// needs a LiDAR's depth or a TrueDepth's face is not, which is what Apple answers for a device
// without those sensors.
//
// Source: ARKit of the arm64 shared cache of iOS 12.0, read with the image's symbols -
// `+[ARConfiguration isSupported]` at 0x19d3b54a0 and `+[ARWorldTrackingConfiguration isSupported]`
// at 0x19d3cfaf4, both of which reach `ARDeviceSupported`, a value computed once from the hardware.

#import <ARKit/ARKit.h>
#import <CoreLocation/CoreLocation.h>

#import "CharonARKitPrivate.h"
#import "CharonARKitPrivate.h"
#import "CharonARTracker.h"

// `+supportedVideoFormats`, `+configurableCaptureDeviceForPrimaryCamera` and the two recommendations
// are declared by the 16.0 headers and are implemented here for a runtime that predates them; the
// class itself only exists from 11.3. A caller reaching one of these is by definition on a release
// new enough for the answer, which is the same reasoning every other backport in this package uses.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

@implementation ARConfiguration


    
    
    
    @dynamic isSupported;
@synthesize worldAlignment = _worldAlignment;
    @synthesize lightEstimationEnabled = _lightEstimationEnabled;
    @synthesize providesAudioData = _providesAudioData;
- (instancetype)initCharonCommon
{
    return [super init];
}

+ (BOOL)supportsFrameSemantics:(ARFrameSemantics)frameSemantics
{
    // Scene semantics are read out of a depth sensor's classification of what the camera sees, and
    // this device has none, so there is no semantics to enable.
    return NO;
}

- (id)copyWithZone:(NSZone *)zone
{
    // A configuration describes what a session is asked to do; copying one and changing the copy
    // must not change the original, so every value the base class stores is carried over.
    ARConfiguration *copy = [[self class] allocWithZone:zone];
    copy.worldAlignment = self.worldAlignment;
    copy.lightEstimationEnabled = self.isLightEstimationEnabled;
    copy.providesAudioData = self.providesAudioData;
    copy.frameSemantics = self.frameSemantics;
    return copy;
}

+ (NSArray<ARVideoFormat *> *)supportedVideoFormats
{
    // The formats the back camera really has, in the order the camera reports them, so that a format
    // offered here is one the session can be configured with.
    NSArray<AVCaptureDeviceFormat *> *formats =
            [CharonARTracker supportedCaptureFormatsForPosition:AVCaptureDevicePositionBack];
    NSMutableArray<ARVideoFormat *> *result = [NSMutableArray arrayWithCapacity:formats.count];
    for (AVCaptureDeviceFormat *format in formats)
        [result addObject:[[ARVideoFormat alloc] initWithCaptureFormat:format]];
    return result;
}

+ (AVCaptureDevice *)configurableCaptureDeviceForPrimaryCamera
{
    return [CharonARTracker captureDeviceForPosition:AVCaptureDevicePositionBack];
}

+ (ARVideoFormat *)recommendedVideoFormatFor4KResolution
{
    return [self videoFormatNearestTo:CGSizeMake(3840, 2160)];
}

+ (ARVideoFormat *)recommendedVideoFormatForHighResolutionFrameCapturing
{
    // The largest frame the primary camera can deliver, and the first one at that size.
    ARVideoFormat *best = nil;
    CGFloat bestArea = 0;
    for (ARVideoFormat *format in self.supportedVideoFormats) {
        CGFloat area = format.imageResolution.width * format.imageResolution.height;
        if (area > bestArea) {
            bestArea = area;
            best = format;
        }
    }
    return best;
}

/// The offered format whose frame is closest to the one asked for, measured on the log of each
/// dimension so that a factor of two in either direction costs the same.
+ (ARVideoFormat *)videoFormatNearestTo:(CGSize)size
{
    ARVideoFormat *best = nil;
    CGFloat bestDistance = INFINITY;
    for (ARVideoFormat *format in self.supportedVideoFormats) {
        CGFloat width = format.imageResolution.width;
        CGFloat height = format.imageResolution.height;
        if (width <= 0 || height <= 0)
            continue;
        CGFloat distance = hypot(log(width / size.width), log(height / size.height));
        if (distance < bestDistance) {
            bestDistance = distance;
            best = format;
        }
    }
    return best;
}

+ (BOOL)isSupported
{
    // The device, asked the question its own sensors can answer.
    return [CharonARTracker isSupported];
}

- (BOOL)isSupported
{
    return [[self class] isSupported];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p>", NSStringFromClass([self class]), self];
}

@end

@implementation ARWorldTrackingConfiguration
- (instancetype)init
{
    self = [self initCharonCommon];
    if (!self)
        return nil;
    self.planeDetection = ARPlaneDetectionNone;
    self.environmentTexturing = AREnvironmentTexturingAutomatic;
    self.worldAlignment = ARWorldAlignmentGravity;
    self.lightEstimationEnabled = NO;
    self.detectionImages = [NSSet set];
    self.detectionObjects = [NSSet set];
    // The documented default is the richest reconstruction, which needs the depth sensor this
    // device does not have, so the default is the one the hardware can actually deliver.
    self.sceneReconstruction = ARSceneReconstructionNone;
    return self;
}

- (void)setDetectionImages:(NSSet<ARReferenceImage *> *)detectionImages
{
    // null_resettable: nil is how a caller clears the set, and it clears it.
    self.detectionImages = detectionImages ?: [NSSet set];
}

+ (BOOL)supportsAppClipCodeTracking
{
    // An App Clip code is recognised by a Neural Engine that no device this framework runs on has.
    return NO;
}

+ (BOOL)supportsUserFaceTracking
{
    // Counted from the depth sensor that measures a face, and this device has none.
    return NO;
}

+ (BOOL)supportsSceneReconstruction:(ARSceneReconstruction)reconstruction
{
    // A scene reconstruction is a mesh built from a depth sensor, and this device has none.
    return NO;
}


+ (BOOL)isSupported
{
    // A world-tracking session is a camera and a gyroscope, which is what this device has.
    return [CharonARTracker isSupported];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; planeDetection = %lu>",
            NSStringFromClass([self class]), self, (unsigned long)_planeDetection];
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end

@implementation AROrientationTrackingConfiguration
- (instancetype)init
{
    self = [self initCharonCommon];
    if (!self)
        return nil;
    self.lightEstimationEnabled = NO;
    return self;
}


+ (BOOL)isSupported
{
    // The gyroscope alone, which is the one sensor this class needs and the one it was named for.
    Class manager = NSClassFromString(@"CMMotionManager");
    return [manager isAvailable];
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end

@implementation ARPositionalTrackingConfiguration
- (instancetype)init
{
    return [self initCharonCommon];
}


+ (BOOL)isSupported
{
    // A tracked image and a place to put it: the camera, and a location service.
    if (![CharonARTracker isSupported])
        return NO;
    return [CLLocationManager class] != nil;
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end

@implementation ARFaceTrackingConfiguration
- (instancetype)init
{
    self = [self initCharonCommon];
    if (!self)
        return nil;
    self.maximumNumberOfTrackedFaces = 1;
    self.worldTrackingEnabled = NO;
    return self;
}

+ (NSInteger)supportedNumberOfTrackedFaces
{
    // Counted from the sensor that measures them, and this device has none.
    return 0;
}

+ (BOOL)supportsWorldTracking
{
    // A face is anchored in the world, so this asks the camera and the gyroscope, not the face
    // sensor: this device has both, and the face tracking that would follow does not.
    return [CharonARTracker isSupported];
}

+ (BOOL)supportsAppClipCodeTracking
{
    // An App Clip code is recognised by a Neural Engine that no device this framework runs on has.
    return NO;
}


+ (BOOL)isSupported
{
    // A face is measured by a depth sensor across the face, and this device has none: no TrueDepth, and
    // no LiDAR either. Apple answers NO for a device without the sensor, and so does this.
    return NO;
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end

@implementation ARBodyTrackingConfiguration
- (instancetype)init
{
    self = [self initCharonCommon];
    if (!self)
        return nil;
    self.automaticSkeletonScaleEstimationEnabled = YES;
    self.detectionImages = [NSSet set];
    self.maximumNumberOfTrackedImages = 0;
    return self;
}

- (void)setDetectionImages:(NSSet<ARReferenceImage *> *)detectionImages
{
    self.detectionImages = detectionImages ?: [NSSet set];
}

+ (BOOL)supportsAppClipCodeTracking
{
    // An App Clip code is recognised by a Neural Engine that no device this framework runs on has.
    return NO;
}


+ (BOOL)isSupported
{
    // A body is a pose estimated from the camera's own frames, which needs no sensor of its own, and
    // the front camera. This device has a front camera, so the answer is what the hardware gives.
    return [CharonARTracker hasFrontCamera];
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end

@implementation ARImageTrackingConfiguration
- (instancetype)init
{
    self = [self initCharonCommon];
    if (!self)
        return nil;
    self.trackingImages = [NSSet set];
    self.maximumNumberOfTrackedImages = 0;
    return self;
}

- (void)setTrackingImages:(NSSet<ARReferenceImage *> *)trackingImages
{
    self.trackingImages = [trackingImages copy] ?: [NSSet set];
}


+ (BOOL)isSupported
{
    // A tracked image is found in the camera's frames and needs no depth sensor.
    return [CharonARTracker isSupported];
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end

@implementation ARObjectScanningConfiguration
- (instancetype)init
{
    return [self initCharonCommon];
}


+ (BOOL)isSupported
{
    // Object scanning reads a mesh out of the depth the camera sees; without a depth sensor there is
    // no mesh to read, and the framework is right to say so.
    return NO;
}

+ (instancetype)new
{
    return [[self alloc] init];
}

@end
