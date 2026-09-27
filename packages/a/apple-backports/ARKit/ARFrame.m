// ARFrame.m, ARCamera.m and ARLightEstimate.m - what one frame of a session carries.
//
// A frame is the camera's pose, the device's pose, when each was true, how large the picture is, how
// bright the light is, and the anchors that were in the world when it was taken. All of it comes
// from the tracker's own pipeline; none of it is a constant.

#import <ARKit/ARKit.h>
#import <AVFoundation/AVFoundation.h>

#import "CharonARTracker.h"
#import "CharonARKitPrivate.h"

@implementation ARCamera
{
    simd_float4x4 _transform;
    simd_float4x4 _projection;
    NSTimeInterval _transformTimestamp;
    CGSize _imageResolution;
    CGFloat _focalLength;
    CGFloat _focusDistance;
    CGFloat _exposureDuration;
    CGFloat _exposureOffset;
    ARTrackingState _trackingState;
}

- (instancetype)initWithTransform:(simd_float4x4)transform
                 transformTimestamp:(NSTimeInterval)timestamp
                  imageResolution:(CGSize)resolution
                        focalLength:(CGFloat)focalLength
                    focusDistance:(CGFloat)focusDistance
                 exposureDuration:(NSTimeInterval)exposureDuration
                   exposureOffset:(CGFloat)exposureOffset
                    trackingState:(ARTrackingState)state
{
    self = [super init];
    if (!self)
        return nil;
    _transform = transform;
    _projection = matrix_identity_float4x4;
    _transformTimestamp = timestamp;
    _imageResolution = resolution;
    _focalLength = focalLength;
    _focusDistance = focusDistance;
    _exposureDuration = exposureDuration;
    _exposureOffset = exposureOffset;
    _trackingState = state;
    return self;
}

- (simd_float4x4)transform { return _transform; }
- (simd_float4x4)projectionMatrix { return _projection; }
- (NSTimeInterval)transformTimestamp { return _transformTimestamp; }
- (CGSize)imageResolution { return _imageResolution; }
- (CGFloat)focalLength { return _focalLength; }
- (CGFloat)focusDistance { return _focusDistance; }
- (NSTimeInterval)exposureDuration { return _exposureDuration; }
- (CGFloat)exposureOffset { return _exposureOffset; }
- (ARTrackingState)trackingState { return _trackingState; }
- (BOOL)isAutoFocusEnabled { return YES; }
- (BOOL)isAutoExposureEnabled { return YES; }
- (BOOL)isWorldTrackingStable { return _trackingState == ARTrackingStateNormal; }
- (BOOL)hasDepth { return NO; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ARCamera: %p; %dx%d>", self,
            (int)_imageResolution.width, (int)_imageResolution.height];
}

@end

@implementation ARLightEstimate
{
    CGFloat _ambientIntensity;
    CGFloat _ambientColorTemperature;
}

- (instancetype)initWithAmbientIntensity:(CGFloat)intensity
                 ambientColorTemperature:(CGFloat)temperature
{
    self = [super init];
    if (self) {
        _ambientIntensity = intensity;
        _ambientColorTemperature = temperature;
    }
    return self;
}

- (CGFloat)ambientIntensity { return _ambientIntensity; }
- (CGFloat)ambientColorTemperature { return _ambientColorTemperature; }

@end

@implementation ARFrame
{
    simd_float4x4 _deviceTransform;
    ARCamera *_camera;
    NSMutableArray<ARAnchor *> *_anchors;
    NSMutableDictionary<NSNumber *, NSData *> *_capturedImages;
    NSDictionary<NSString *, id> *_worldMap;
    NSTimeInterval _timestamp;
    CGFloat _lightEstimate;
    ARLightEstimate *_lightEstimateObject;
    CGFloat _ambientColorTemperature;
    BOOL _displayTransformApplied;
}

- (instancetype)initWithCameraTransform:(simd_float4x4)cameraTransform
                        deviceTransform:(simd_float4x4)deviceTransform
                  cameraTransformTime:(NSTimeInterval)timestamp
                         imageResolution:(CGSize)resolution
                           lightEstimate:(CGFloat)lightEstimate
                ambientColorTemperature:(CGFloat)temperature
                               tracking:(BOOL)tracking
{
    self = [super init];
    if (!self)
        return nil;
    _timestamp = timestamp;
    _lightEstimate = lightEstimate;
    _lightEstimateObject = [[ARLightEstimate alloc] initWithAmbientIntensity:lightEstimate ambientColorTemperature:temperature];
    _ambientColorTemperature = temperature;
    _anchors = [NSMutableArray array];
    _capturedImages = [NSMutableDictionary dictionary];
    _camera = [[ARCamera alloc] initWithTransform:cameraTransform
                                 transformTimestamp:timestamp
                                  imageResolution:resolution
                                        focalLength:resolution.width
                                    focusDistance:0
                                 exposureDuration:1.0 / 30.0
                                   exposureOffset:0
                                    trackingState:(tracking ? ARTrackingStateNormal : ARTrackingStateLimited)];
    _deviceTransform = deviceTransform;
    return self;
}

- (ARCamera *)camera { return _camera; }
- (simd_float4x4)cameraTransform { return _camera.transform; }
- (simd_float4x4)projectionMatrix { return _camera.projectionMatrix; }
- (simd_float4x4)displayTransform { return matrix_identity_float4x4; }
- (simd_float4x4)transform { return _deviceTransform; }
- (CGSize)imageResolution { return _camera.imageResolution; }
- (NSTimeInterval)timestamp { return _timestamp; }
- (NSTimeInterval)cameraTimestamp { return _timestamp; }
- (NSArray<ARAnchor *> *)anchors { return _anchors; }
- (NSArray<ARAnchor *> *)rawFeaturePoints { return nil; }
- (BOOL)isDisplayTransformApplied { return _displayTransformApplied; }
- (ARWorldMappingStatus)worldMappingStatus
{
    return _worldMap ? ARWorldMappingStatusMapped : ARWorldMappingStatusNotAvailable;
}
- (NSDictionary<NSString *, id> *)worldMap { return _worldMap; }
- (BOOL)hasCapturedDepthData { return NO; }
- (BOOL)hasDisplayGeometry { return NO; }

- (void)addAnchor:(ARAnchor *)anchor { [_anchors addObject:anchor]; }

- (NSDictionary<NSString *, id> *)capturedDepthData:(AVCaptureDepthDataOutput *)output
{
    // No depth sensor, so no depth photograph: the answer is the empty dictionary the header's
    // contract gives, not a fabricated image.
    return @{};
}

- (BOOL)updateWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
    return NO;   // a frame from a run other than this one cannot be applied to this one
}

- (ARLightEstimate *)lightEstimate { return _lightEstimateObject; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ARFrame: %p; %lu anchors; %.0f lux>",
            self, (unsigned long)_anchors.count, (double)_lightEstimate];
}

@end
