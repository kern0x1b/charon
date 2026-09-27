// CharonARKitPrivate.h - the declarations two of the ARKit files share, which the SDK's headers
// do not carry because the framework keeps them to itself. Nothing here is API: an application
// never sees these names, and the registry weighs none of them.

#import <ARKit/ARKit.h>
#import <simd/simd.h>

#import "CharonARTracker.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARConfiguration (CharonPrivate)
/// The base class's own initialiser under a name a subclass can call. The SDK marks `-init`
/// unavailable on `ARConfiguration` because the class is abstract, and an unavailable method is
/// unreachable from the subclass that would initialise it, so the same initialiser is reached here
/// instead. It is not API: nothing outside this library calls it, and a caller cannot create an
/// abstract configuration in the first place.
- (instancetype)initCharonCommon;
@end

@interface ARVideoFormat (CharonPrivate)
/// Built from a format the primary camera really has, which the tracker enumerates.
- (instancetype)initWithCaptureFormat:(AVCaptureDeviceFormat *)format;
@end

@interface ARPlaneAnchor (CharonPrivate)
/// Built from a plane the detector found, which the tracker carries as its own struct.
- (instancetype)initWithPlaneValue:(CharonARValue *)value;
@end

@interface ARPlaneGeometry (CharonPrivate)
/// Built from one plane the detector found, which the tracker carries as its own struct.
- (instancetype)initWithPlaneValue:(CharonARValue *)value;
@end

@interface ARHitTestResult (CharonPrivate)
- (instancetype)initWithHitValue:(CharonARValue *)value;
@end

@interface ARPointCloud (CharonPrivate)
- (instancetype)initWithPoints:(NSData *)points count:(NSUInteger)count;
@end

@interface ARRaycastQuery (CharonPrivate)
/// Built from a ray in the world, which is what a caller asking for a raycast gives the framework.
- (instancetype)initWithOrigin:(simd_float3)origin
                    direction:(simd_float3)direction
             allowingTarget:(ARRaycastTarget)target
                    alignment:(ARRaycastTargetAlignment)alignment;
@end

@interface ARRaycastResult (CharonPrivate)
- (instancetype)initWithHitValue:(CharonARValue *)value;
@end

@interface ARFrame (CharonPrivate)
- (instancetype)initWithCameraTransform:(simd_float4x4)cameraTransform
                        deviceTransform:(simd_float4x4)deviceTransform
                  cameraTransformTime:(NSTimeInterval)timestamp
                         imageResolution:(CGSize)resolution
                           lightEstimate:(CGFloat)lightEstimate
                ambientColorTemperature:(CGFloat)ambientColorTemperature
                               tracking:(BOOL)tracking
                         hitTestTracker:(CharonARTracker *)hitTestTracker;

/// Adds an anchor to this frame, which the session does once it has seen the world.
- (void)addAnchor:(ARAnchor *)anchor;
@end

@interface ARAnchor (CharonPrivate)
/// The session names an anchor the application adds, because a name is what the application then
/// finds it by.
@property (nonatomic, copy) NSUUID *identifier;
@end

NS_ASSUME_NONNULL_END
