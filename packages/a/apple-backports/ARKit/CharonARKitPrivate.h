// CharonARKitPrivate.h - the declarations two of the ARKit files share, which the SDK's headers
// do not carry because the framework keeps them to itself. Nothing here is API: an application
// never sees these names, and the registry weighs none of them.

#import <ARKit/ARKit.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARPlaneAnchor (CharonPrivate)
/// Built from a plane the detector found, which the tracker carries as its own struct.
- (instancetype)initWithPlaneValue:(NSValue *)value;
@end

@interface ARPlaneGeometry (CharonPrivate)
/// Built from one plane the detector found, which the tracker carries as its own struct.
- (instancetype)initWithPlaneValue:(NSValue *)value;
@end

@interface ARHitTestResult (CharonPrivate)
- (instancetype)initWithHitValue:(NSValue *)value;
@end

@interface ARPointCloud (CharonPrivate)
- (instancetype)initWithPoints:(NSData *)points count:(NSUInteger)count;
@end

@interface ARRaycastResult (CharonPrivate)
- (instancetype)initWithHitValue:(NSValue *)value;
@end

@interface ARFrame (CharonPrivate)
- (instancetype)initWithCameraTransform:(simd_float4x4)cameraTransform
                        deviceTransform:(simd_float4x4)deviceTransform
                  cameraTransformTime:(NSTimeInterval)timestamp
                         imageResolution:(CGSize)resolution
                           lightEstimate:(CGFloat)lightEstimate
                ambientColorTemperature:(CGFloat)ambientColorTemperature
                               tracking:(BOOL)tracking;

/// Adds an anchor to this frame, which the session does once it has seen the world.
- (void)addAnchor:(ARAnchor *)anchor;
@end

@interface ARAnchor (CharonPrivate)
/// The session names an anchor the application adds, because a name is what the application then
/// finds it by.
@property (nonatomic, copy) NSUUID *identifier;
@end

NS_ASSUME_NONNULL_END
