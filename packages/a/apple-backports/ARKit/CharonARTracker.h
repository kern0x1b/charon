// CharonARTracker.h - the visual-inertial tracker behind ARSession on a device whose camera and
// gyroscope are the whole of its sensing.
//
// An ARKit session on a device with a camera, a gyroscope and an accelerometer but no LiDAR and no
// structured-depth sensor is a visual-inertial odometry problem, and that is what this is: features
// found in the camera frames, matched between consecutive frames by a patch around a corner, and
// integrated into a camera pose with the gyroscope's rotation. Planes are what a plane *detector*
// reports without measuring: a run of points that stays level and does not turn, which is a surface
// the camera has seen enough of to guess that it is there - a real answer to Apple's "detected"
// rather than its "alignment", which needs the sensor this device does not have.
//
// Nothing here is a stand-in. The camera frames come from the release's own
// AVCaptureVideoDataOutput and the rotation from the release's own CMMotionManager, both measured
// present in the armv7 shared cache of iOS 6.1.3; the tracking, the matching, the integration and the
// plane detection are this file's own.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// One point the tracker follows, in normalised image coordinates and in the camera's own frame.
typedef struct {
    simd_float2 image;          ///< where it is in the frame, 0..1 with the origin top left
    simd_float3 camera;         ///< where it is in the camera's frame, metres
    simd_float3 world;          ///< where it is in the world, metres, once the pose is known
    float      scale;           ///< how big it looks, for the size of its patch
    uint32_t   identifier;      ///< stable across frames, so an anchor can name it
    uint8_t    age;             ///< frames seen, so a stale point can be dropped
    uint8_t    hits;            ///< frames matched in a row
} CharonARPoint;

/// A surface the plane detector found: a centre, a normal, an extent and how much of it was seen.
typedef struct {
    simd_float3 center;
    simd_float3 normal;         ///< unit, in the world
    simd_float3 extent;         ///< half the width, height and length of what was seen
    float       alignment;      ///< the confidence the detector has in the plane
    uint32_t    identifier;
} CharonARPlane;

/// One hit of a ray against a plane, in world coordinates.
typedef struct {
    simd_float3 position;
    simd_float3 localNormal;
    uint32_t     planeIdentifier;
} CharonARHit;

/// A point cloud sample, which ARKit hands out as indices into a buffer it names itself.
typedef struct {
    simd_float3 position;
} CharonARCloudPoint;

@protocol CharonARTrackerDelegate;

/// The tracker. One per session; a session owns it and asks it for a pose.
@interface CharonARValue : NSObject

/// A plane or a hit, carried out of the tracker as an object.
///
/// These are structs that hold SIMD vectors, and `@encode` cannot describe an extended vector type
/// on this target - it answers that the type's encoding is incomplete - so the bytes travel in a
/// box object with a declared ivar rather than in an NSValue, whose `objCType` would have to name
/// the struct. Reading the struct back is `getValue:`, and the size is the struct's own.
- (instancetype)initWithBytes:(const void *)bytes size:(size_t)size NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Copies the struct out. NO is answered when the box holds fewer bytes than the struct needs,
/// which is what a box of a different struct is.
- (BOOL)getValue:(void *)value;

@property (nonatomic, readonly) size_t size;

@end

@interface CharonARTracker : NSObject

/// Whether the camera and the gyroscope this needs are both really there. ARKit's own
/// `+[ARWorldTrackingConfiguration isSupported]` asks the same question.
+ (BOOL)isSupported;

/// Whether the front camera can be asked for, which the body and face work would need.
+ (BOOL)hasFrontCamera;

/// The camera ARKit would capture from, or nil when there is none. This is the only place in the
/// library that enumerates cameras, so `+[ARConfiguration configurableCaptureDeviceForPrimaryCamera]`
/// and the video formats answer from the same enumeration the session captures with.
+ (nullable AVCaptureDevice *)captureDeviceForPosition:(AVCaptureDevicePosition)position;

/// Every format the given camera can be configured to, as AVCaptureVideoDataOutput would list them.
+ (NSArray<AVCaptureDeviceFormat *> *)supportedCaptureFormatsForPosition:(AVCaptureDevicePosition)position;

/// The camera's own intrinsics for a frame of the given size: the focal length in pixels and the
/// principal point, in the order the framework's `simd_float3x3` puts them.
///
/// The camera states how wide it sees - `AVCaptureDeviceFormat`'s field of view - and the size of
/// the frame says how many pixels that width is, which between them fix the focal length in pixels
/// and the principal point. A camera that states no field of view has nothing to build them from,
/// and the answer is the matrix of ones, which projects nothing to anywhere.
+ (simd_float3x3)cameraIntrinsicsForResolution:(CGSize)resolution;

@property (nonatomic, weak, nullable) id<CharonARTrackerDelegate> delegate;

/// Starts the camera and the gyroscope. `error` is filled in and NO answered when either is
/// refused - the camera by the application's own authorisation, the gyroscope by hardware.
- (BOOL)startWithError:(NSError **)error;

/// A still photograph of the scene, at the largest size the primary camera's still output will give.
///
/// This is the same camera the session captures from, asked for a single frame rather than a
/// stream, which is what a high-resolution frame is: the same optics, the same pose, the same
/// moment. The still output of this release's AVFoundation takes the picture at the camera's own
/// active format, so the size is whatever the video output was configured for and nothing larger is
/// claimed. `error` is filled in and NULL answered when the output could not take the picture.
- (nullable CVPixelBufferRef)copyHighResolutionImageWithError:(NSError **)error
    CF_RETURNS_RETAINED;

/// Stops both, and forgets the world.
- (void)stop;

/// The camera's own pose for the frame just handed in: a 4x4 from the camera's space to the
/// world's, which is the transform every anchor and every ray is expressed in.
- (simd_float4x4)processPixelBuffer:(CVPixelBufferRef)pixelBuffer
                        captureTime:(NSTimeInterval)captureTime
                      deviceRotation:(simd_quatf)deviceRotation;

/// The points of the current frame, which is the point cloud an anchor is made of.
@property (nonatomic, readonly) NSData *pointCloud;

/// The planes the detector has, which is the geometry a plane anchor is made of.
@property (nonatomic, readonly) NSArray<CharonARValue *> *planes;

/// The pose of the camera at the capture time of the current frame, as a `simd_float4x4`.
@property (nonatomic, readonly) simd_float4x4 cameraTransform;

/// The device motion at the capture time of the current frame, in the world's frame.
@property (nonatomic, readonly) simd_float4x4 deviceTransform;

/// The intensity of the ambient light in the current frame, 1000 being the neutral Apple uses.
@property (nonatomic, readonly) CGFloat lightEstimate;

/// The ambient colour temperature in kelvin, 6500 being the neutral Apple uses.
@property (nonatomic, readonly) CGFloat ambientColorTemperature;

/// Whether the camera sees a tracked feature in the current frame, which
/// `ARCamera.trackingState` reports as `ARCameraTrackingStateLimited` when it does not.
@property (nonatomic, readonly) BOOL isTracking;

/// The size of the frame the camera is giving, in pixels.
@property (nonatomic, readonly) CGSize imageResolution;

/// The capture time of the current frame, in seconds since the session started.
@property (nonatomic, readonly) NSTimeInterval timestamp;

/// A ray from the camera through a point of the frame, in world coordinates.
- (BOOL)raycastFromPoint:(CGPoint)point
                allowing:(NSUInteger)targets
                results:(NSMutableArray<CharonARValue *> *)results;

/// A ray from a world point along a world direction.
- (BOOL)raycastFromOrigin:(simd_float3)origin
                 direction:(simd_float3)direction
                allowing:(NSUInteger)targets
                  results:(NSMutableArray<CharonARValue *> *)results;

/// A ray in the camera's own space, which is what a hit test against a feature is.
- (BOOL)hitTestPoint:(CGPoint)point
          results:(NSMutableArray<CharonARValue *> *)results;

/// A ray against the planes only, which is what Apple's "existingPlaneGeometry" asks for.
- (BOOL)hitTestPoint:(CGPoint)point
    existingPlane:(BOOL)existingPlane
          results:(NSMutableArray<CharonARValue *> *)results;

@end

/// What the tracker tells its owner, once per frame.
@protocol CharonARTrackerDelegate <NSObject>
- (void)tracker:(CharonARTracker *)tracker didUpdateWithTimestamp:(NSTimeInterval)timestamp;
@end

NS_ASSUME_NONNULL_END
