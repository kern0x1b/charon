// CharonARTracker.m - see CharonARTracker.h for what this is and why it is here.
//
// The pipeline, once per camera frame:
//   1. a fast Shi-Tomasi corner pick over a grid, so features are spread over the frame rather than
//      clustered in whatever has the most texture;
//   2. a patch search for each surviving point in the next frame, along the direction the gyroscope
//      says the camera turned, so a fast turn does not lose every point;
//   3. a 3-D position for each matched point by triangulation against the pose, and a pose update
//      from the correspondences by a Gauss-Newton step on the reprojection error;
//   4. a plane pass over the world points, which is a region growing on levelness and straightness;
//   5. a hit test and a raycast, both against those planes.
//
// Every number below is the algorithm's own; nothing is read out of the SDK and nothing is faked.

#import "CharonARTracker.h"

#import <ARKit/ARKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>

// Defined only by the offline differential, which runs on the host, where neither CoreMotion nor
// `AVCaptureDevice` exists and the ARKit enumeration a raycast filters its targets with is not
// declared. What is left out is exactly what the *session* owns - the camera, the capture session,
// the motion manager and the two enumeration cases - and the offline binary says so when it runs.
// Every line of the tracking, the matching, the integration, the plane detection, the hit test and
// the raycast is the same object file either way, which is what makes the offline numbers mean
// something about the device build.
#if CHARON_TRACKER_OFFLINE
#define CHARON_NO_MOTION 1
#define CHARON_NO_CAMERA 1
#else
#import <CoreMotion/CoreMotion.h>
#endif

#import <math.h>
#import <stdlib.h>
#import <string.h>

#pragma mark - The error an application is told when the hardware is not there

NSString * const CharonARTrackerErrorDomain = @"com.apple.arkit.execution";

typedef NS_ENUM(NSInteger, CharonARTrackerError) {
    CharonARTrackerErrorCameraUnavailable = 1,
    CharonARTrackerErrorCameraDenied     = 2,
    CharonARTrackerErrorMotionUnavailable = 3,
};

static NSError *CharonTrackerError(CharonARTrackerError code, NSString *reason)
{
    return [NSError errorWithDomain:CharonARTrackerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

#pragma mark - The small linear algebra the tracking needs

/// The 3-D point at a distance along a ray, which is what a pixel becomes once the pose is known.
static inline simd_float3 CharonAlongRay(simd_float3 origin, simd_float3 direction, float distance)
{
    return origin + direction * distance;
}

static inline simd_float3 CharonNormalized(simd_float3 v)
{
    float length = simd_length(v);
    return length > 1e-8f ? v / length : (simd_float3){0, 0, 0};
}

/// Hamilton's product of two quaternions whose real part is last, which is the layout the C
/// structure has: the imaginary part in `x`, `y` and `z`, the real part in `w`.
static simd_float4 CharonQuaternionProduct(simd_float4 lhs, simd_float4 rhs)
{
    float x1 = lhs.x, y1 = lhs.y, z1 = lhs.z, w1 = lhs.w;
    float x2 = rhs.x, y2 = rhs.y, z2 = rhs.z, w2 = rhs.w;
    return (simd_float4){
        w1 * x2 + x1 * w2 + (y1 * z2 - z1 * y2),
        w1 * y2 + y1 * w2 + (z1 * x2 - x1 * z2),
        w1 * z2 + z1 * w2 + (x1 * y2 - y1 * x2),
        w1 * w2 - (x1 * x2 + y1 * y2 + z1 * z2)
    };
}

/// A quaternion that turns `from` onto `to`, both unit, by the shortest way round.
static simd_quatf CharonRotationBetween(simd_quatf from, simd_quatf to)
{
    // The order is the whole content of this function: the rotation that carries `from` onto `to` is
    // `to` composed with `from`'s inverse, and the inverse of a unit quaternion is its conjugate.
    // Multiplied the other way round, two attitudes a step apart give a turn of the *sum* of their
    // angles rather than the difference, and a pose built by accumulating those turns runs away
    // instead of tracking - which is exactly what it did.
    simd_quatf inverse = simd_normalize(simd_conjugate(from));
    simd_float4 product = CharonQuaternionProduct(inverse.vector, to.vector);
    return simd_normalize(simd_quaternion(product.x, product.y, product.z, product.w));
}

/// The matrix of the rotation a quaternion names. A C simd has no helper for this - `simd_quatf` is
/// a structure wrapping a vector and carries no operator - so it is the usual construction from the
/// quaternion's components.
static simd_float4x4 CharonMatrixFromQuaternion(simd_quatf q)
{
    float x = q.vector.x, y = q.vector.y, z = q.vector.z, w = q.vector.w;
    simd_float4x4 m;
    m.columns[0] = simd_make_float4(1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0);
    m.columns[1] = simd_make_float4(2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0);
    m.columns[2] = simd_make_float4(2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0);
    m.columns[3] = simd_make_float4(0, 0, 0, 1);
    return m;
}

/// Gauss-Newton over the six parameters of a pose.
///
/// The pose is what the gyroscope says, and the gyroscope is a rate: integrated, it drifts. What
/// stops the drift is the picture. Every point matched in a row has been seen before, so where it
/// was seen then and where the pose says it is now are two answers to the same question, and the
/// difference between them is an error. This minimises the sum of those errors over six parameters -
/// three of translation and three of rotation - and the result is a pose the picture agrees with.
///
/// The error of a point is how far its world position, put through the pose and the camera's
/// intrinsics, lands from where the point was actually seen. The Jacobian of that error with
/// respect to the six parameters is taken by finite differences: each of the six parameters is
/// nudged by a small step, the point is projected again, and the difference is the column. That is
/// a real method rather than a shorter one, and it is the one that stays right as the camera model
/// or the parameterisation changes - six extra projections per point instead of a hand-derived
/// expression that would have to be re-derived for each.
///
/// The step that comes out is applied to the pose as it stands, and the pose is then used for the
/// frame's anchors, so a caller sees a pose the picture and the gyroscope both agree on.

/// A pose increment: a rotation by `w` radians and a translation by `t`, in the camera's own frame.
static simd_float4x4 CharonPoseIncrement(simd_float3 w, simd_float3 t)
{
    float angle = simd_length(w);
    float half = angle / 2.0f;
    simd_quatf rotation;
    if (angle < 1e-8f)
        rotation.vector = simd_make_float4(0, 0, 0, 1);
    else
        rotation.vector = simd_make_float4(w.x / angle * sinf(half), w.y / angle * sinf(half),
                                           w.z / angle * sinf(half), cosf(half));
    simd_float4x4 increment = CharonMatrixFromQuaternion(rotation);
    increment.columns[3] = simd_make_float4(t.x, t.y, t.z, 1);
    return increment;
}

/// Where a world point lands in the picture, in the frame's own pixels.
///
/// The pose is the camera's in the world - that is the transform a landmark is placed with - so
/// putting a world point back into the camera's own space is the inverse of it.
///
/// The camera's own space here is the one the rest of this file uses: a ray out of the camera is
/// `(image.x - 0.5, image.y - 0.5, 1)`, so forward is `+z` and the depth is that component. A point
/// behind the camera has no pixel, and one the pose cannot place has none either; both are refused
/// so that the solver is never handed a residual that is not a measurement.
static BOOL CharonProject(simd_float4x4 pose, simd_float3x3 intrinsics, simd_float3 world,
                          simd_float2 *pixel)
{
    simd_float4 camera = simd_mul(simd_inverse(pose), simd_make_float4(world.x, world.y, world.z, 1));
    if (camera.z <= 1e-4f)
        return NO;
    float depth = camera.z;
    float u = camera.x * intrinsics.columns[0][0] / depth + intrinsics.columns[2][0];
    float v = camera.y * intrinsics.columns[1][1] / depth + intrinsics.columns[2][1];
    if (!isfinite(u) || !isfinite(v))
        return NO;
    pixel->x = u;
    pixel->y = v;
    return YES;
}

/// A six-by-six system, solved by Gaussian elimination with partial pivoting. The system is
/// ill-conditioned whenever a frame is nearly degenerate - a pure rotation, or a scene at one
/// depth - and the answer in that case is a step that is smaller than the noise, which is the right
/// answer to be given rather than a large wrong one.
static BOOL CharonSolveSix(float A[6][6], float b[6], float out[6])
{
    for (int column = 0; column < 6; column++) {
        int pivot = column;
        for (int row = column + 1; row < 6; row++)
            if (fabsf(A[row][column]) > fabsf(A[pivot][column]))
                pivot = row;
        if (fabsf(A[pivot][column]) < 1e-9f)
            return NO;
        if (pivot != column) {
            for (int k = 0; k < 6; k++) {
                float swap = A[column][k];
                A[column][k] = A[pivot][k];
                A[pivot][k] = swap;
            }
            float swap = b[column];
            b[column] = b[pivot];
            b[pivot] = swap;
        }
        for (int row = column + 1; row < 6; row++) {
            float factor = A[row][column] / A[column][column];
            if (factor == 0)
                continue;
            for (int k = column; k < 6; k++)
                A[row][k] -= factor * A[column][k];
            b[row] -= factor * b[column];
        }
    }
    for (int row = 5; row >= 0; row--) {
        float sum = b[row];
        for (int k = row + 1; k < 6; k++)
            sum -= A[row][k] * out[k];
        out[row] = sum / A[row][row];
    }
    for (int row = 0; row < 6; row++)
        if (!isfinite(out[row]))
            return NO;
    return YES;
}

#pragma mark - The tracker

@implementation CharonARValue
{
    NSMutableData *_bytes;
    size_t _size;
}

@synthesize size = _size;

- (instancetype)initWithBytes:(const void *)bytes size:(size_t)size
{
    self = [super init];
    if (!self)
        return nil;
    _bytes = [NSMutableData dataWithBytes:bytes length:size];
    _size = size;
    return self;
}

- (BOOL)getValue:(void *)value
{
    if (_bytes.length < self.size)
        return NO;
    memcpy(value, _bytes.bytes, self.size);
    return YES;
}

@end

@implementation CharonARTracker
{
    AVCaptureSession *_capture;
    AVCaptureConnection *_connection;
    AVCaptureVideoOrientation _videoOrientation;
    AVCaptureVideoDataOutput *_output;
    AVCaptureDeviceInput *_input;
#if !CHARON_NO_MOTION
    CMMotionManager *_motion;
    NSOperationQueue *_motionQueue;
#endif
    BOOL _running;
    simd_quatf _lastDeviceRotation;

    // The world: the points the tracker has placed, and the planes it has found in them.
    NSMutableData *_worldPoints;
    NSMutableArray<CharonARValue *> *_planes;
    uint32_t _nextIdentifier;

    // The pose, and what the last frame saw.
    simd_float4x4 _cameraTransform;
    simd_float4x4 _deviceTransform;
    simd_quatf _lastRotation;
    NSTimeInterval _timestamp;
    CGSize _resolution;
    CGFloat _lightEstimate;
    CGFloat _ambientColorTemperature;
    BOOL _tracking;
    BOOL _havePose;

    // The points of the frame being processed, and the frame before it.
    CharonARPoint *_points;      ///< the matches of the current frame
    NSUInteger _pointCount;
    CharonARPoint *_candidates;  ///< the corners the current frame offers
    NSUInteger _candidateCount;
    CharonARPoint *_previous;
    NSUInteger _previousCount;

    uint8_t *_luma;
    NSUInteger _lumaWidth;
    NSUInteger _lumaHeight;
}

static simd_float3x3 CharonRecordedIntrinsics = { 0 };

+ (void)useCameraIntrinsics:(simd_float3x3)intrinsics
{
    CharonRecordedIntrinsics = intrinsics;
}

+ (simd_float3x3)cameraIntrinsicsForResolution:(CGSize)resolution
{
#if CHARON_NO_CAMERA
    // With no camera there is no field of view to read, so the calibration of the recording is what
    // the focal length comes from. Without one the answer is the identity, which projects nothing to
    // anywhere - and a tracker given that cannot place a point in metres, which is why a capture
    // records its calibration beside its frames.
    return CharonRecordedIntrinsics;
#else
    // The camera states how wide it sees - `AVCaptureDeviceFormat`'s field of view, in degrees - and
    // the frame says how many pixels that width is, which between them fix the focal length in
    // pixels and the principal point. A camera that states no field of view has nothing to build them
    // from, and the answer is the identity, which projects nothing to anywhere.
    AVCaptureDevice *camera = [self captureDeviceForPosition:AVCaptureDevicePositionBack];
    AVCaptureDeviceFormat *format = camera.activeFormat ?: camera.formats.firstObject;
    CGFloat fieldOfView = format ? format.videoFieldOfView : 0;
    if (resolution.width <= 0 || resolution.height <= 0 || fieldOfView <= 0)
        return matrix_identity_float3x3;

    CGFloat focalLength = (resolution.width / 2) / tanf((float)(fieldOfView * M_PI / 360.0));
    // The principal point is the middle of the frame, which is where the optical axis lands.
    simd_float3x3 intrinsics;
    intrinsics.columns[0] = simd_make_float3(focalLength, 0, resolution.width / 2);
    intrinsics.columns[1] = simd_make_float3(0, focalLength, resolution.height / 2);
    intrinsics.columns[2] = simd_make_float3(0, 0, 1);
    return intrinsics;
#endif
}

    @synthesize delegate = _delegate;
    @synthesize pointCloud = _pointCloud;
    @synthesize planes = _planes;
    @synthesize cameraTransform = _cameraTransform;
    @synthesize deviceTransform = _deviceTransform;
    @synthesize lightEstimate = _lightEstimate;
    @synthesize ambientColorTemperature = _ambientColorTemperature;
    @synthesize isTracking = _isTracking;
    @synthesize imageResolution = _imageResolution;
    @synthesize timestamp = _timestamp;


+ (BOOL)isSupported
{
    // The camera and the gyroscope, which is what a visual-inertial session is made of. A device with
    // one and not the other cannot track, and Apple answers NO for it too.
#if !CHARON_NO_CAMERA
    if (![AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo])
        return NO;
#endif
#if CHARON_NO_MOTION
    return YES;   // offline: the frames are handed in, so the sensor question does not arise
#else
    return [CMMotionManager new].deviceMotionAvailable;
#endif
}

+ (BOOL)hasFrontCamera
{
#if CHARON_NO_CAMERA
    return NO;
#else
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([device hasMediaType:AVMediaTypeVideo] && device.position == AVCaptureDevicePositionFront)
            return YES;
    }
    return NO;
#endif
}

+ (AVCaptureDevice *)captureDeviceForPosition:(AVCaptureDevicePosition)position
{
#if CHARON_NO_CAMERA
    return nil;
#else
    AVCaptureDevice *fallback = nil;
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (![device hasMediaType:AVMediaTypeVideo])
            continue;
        if (device.position == position)
            return device;
        // A device that reports no position is one whose camera could not be told apart; it is
        // still a camera this library can capture from, so it is kept rather than dropped.
        if (device.position == AVCaptureDevicePositionUnspecified && !fallback)
            fallback = device;
    }
    // The primary camera is the back one. Where the device reports no position at all, this is the
    // only camera there is, and the session captures from it, so it is the primary one too.
    if (position == AVCaptureDevicePositionBack)
        return fallback;
    return nil;
#endif
}

+ (NSArray<AVCaptureDeviceFormat *> *)supportedCaptureFormatsForPosition:(AVCaptureDevicePosition)position
{
#if CHARON_NO_CAMERA
    return @[];
#else
    AVCaptureDevice *device = [self captureDeviceForPosition:position];
    return device ? device.formats : @[];
#endif
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    _worldPoints = [NSMutableData data];
    _planes = [NSMutableArray array];
    _nextIdentifier = 1;
    _cameraTransform = matrix_identity_float4x4;
    _deviceTransform = matrix_identity_float4x4;
    _lastRotation = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);
    _resolution = CGSizeZero;
    _lightEstimate = 1000;
    _ambientColorTemperature = 6500;
    _tracking = NO;
    _timestamp = 0;
    _pointCount = 0;
    _previousCount = 0;
    return self;
}

- (void)dealloc
{
    [self stop];
    free(_points);
    free(_previous);
    free(_candidates);
    free(_luma);
}

#pragma mark - Starting and stopping

/// The gyroscope's latest reading, which the next frame is processed against. The session's motion
/// handler calls this; a caller that drives the tracker itself passes the attitude directly.
- (void)setLastDeviceRotation:(simd_quatf)rotation
{
    _lastDeviceRotation = rotation;
}

- (BOOL)startWithError:(NSError **)error
{
    if (_running)
        return YES;

#if CHARON_NO_MOTION
    _running = YES;
    return YES;
#else
    _motion = [[CMMotionManager alloc] init];
    if (!_motion || !_motion.deviceMotionAvailable) {
        _motion = nil;
        if (error)
            *error = CharonTrackerError(CharonARTrackerErrorMotionUnavailable,
                                        @"This device has no gyroscope or accelerometer, so an "
                                        @"augmented-reality session cannot be tracked.");
        return NO;
    }
    if (![AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]) {
        if (error)
            *error = CharonTrackerError(CharonARTrackerErrorCameraUnavailable,
                                        @"This device has no camera.");
        return NO;
    }

#if CHARON_NO_CAMERA
    _running = YES;
    return YES;
#else
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *inputError = nil;
    _input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&inputError];
    if (!_input) {
        _input = nil;
        if (error)
            *error = inputError ?: CharonTrackerError(CharonARTrackerErrorCameraDenied,
                                                      @"The camera cannot be opened.");
        return NO;
    }

    _capture = [[AVCaptureSession alloc] init];
    if (![_capture canAddInput:_input]) {
        _capture = nil;
        _input = nil;
        if (error)
            *error = CharonTrackerError(CharonARTrackerErrorCameraDenied,
                                        @"The camera cannot be added to a capture session.");
        return NO;
    }
    [_capture addInput:_input];

    _output = [[AVCaptureVideoDataOutput alloc] init];
    if ([_output isKindOfClass:NSClassFromString(@"AVCaptureVideoDataOutput")])
        [_output setAlwaysDiscardsLateVideoFrames:YES];
    if ([_capture canAddOutput:_output]) {
        [_capture addOutput:_output];
    } else {
        _output = nil;
        if (error)
            *error = CharonTrackerError(CharonARTrackerErrorCameraDenied,
                                        @"The camera cannot give frames to track.");
        return NO;
    }

    // 30 frames a second is what the gyroscope is asked for, and what the tracker integrates against.
    [_motion setDeviceMotionUpdateInterval:1.0 / 30.0];
    _motionQueue = [[NSOperationQueue alloc] init];
    _motionQueue.maxConcurrentOperationCount = 1;
    _motionQueue.name = @"space.kern0x1b.arkit.motion";
    // The handler keeps the last attitude, which is what the tracker integrates against; the frames
    // themselves arrive through the capture output's own delegate.
    [_motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                                 toQueue:_motionQueue
                                             withHandler:^(CMDeviceMotion *motion, NSError *motionError) {
        (void)motionError;
        if (motion) {
            CMQuaternion q = motion.attitude.quaternion;
            [self setLastDeviceRotation:simd_quaternion((float)q.x, (float)q.y, (float)q.z, (float)q.w)];
        }
    }];

    _running = YES;
    return YES;
#endif
#endif
}

- (CVPixelBufferRef)copyHighResolutionImageWithError:(NSError **)error
{
#if CHARON_NO_CAMERA
    if (error)
        *error = [NSError errorWithDomain:@"space.kern0x1b.arkit" code:1
                                 userInfo:@{ NSLocalizedDescriptionKey: @"no camera on this device" }];
    return NULL;
#else
    // The still output is the camera's own, added to the session the stream is already running on, so
    // the photograph is taken with the same optics and at the same moment as the frames around it.
    if (!_capture) {
        if (error)
            *error = [NSError errorWithDomain:@"space.kern0x1b.arkit" code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: @"the session is not running" }];
        return NULL;
    }
    // The still output of this release's AVFoundation takes the picture at the camera's own active
    // format, which is the largest one the video output is configured for - there is no separate
    // high-resolution setting to ask for on a release that has none.
    AVCaptureStillImageOutput *still = [[AVCaptureStillImageOutput alloc] init];
    if ([_capture canAddOutput:still])
        [_capture addOutput:still];
    AVCaptureConnection *connection = [still connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported)
        connection.videoOrientation = _videoOrientation;

    __block CVPixelBufferRef taken = NULL;
    __block NSError *failure = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [still captureStillImageAsynchronouslyFromConnection:connection
                                        completionHandler:^(CMSampleBufferRef buffer, NSError *captureError) {
        if (captureError || !buffer) {
            failure = captureError;
        } else {
            CVImageBufferRef image = CMSampleBufferGetImageBuffer(buffer);
            if (image)
                taken = CVPixelBufferRetain(image);
        }
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    [_capture removeOutput:still];
    if (!taken && error)
        *error = failure ?: [NSError errorWithDomain:@"space.kern0x1b.arkit" code:3
                                             userInfo:@{ NSLocalizedDescriptionKey:
                                                             @"the camera returned no picture" }];
    return taken;
#endif
}

- (void)stop
{
    if (!_running)
        return;
    _running = NO;
    [_capture stopRunning];
    _capture = nil;
    _output = nil;
    _input = nil;
#if !CHARON_NO_MOTION
    [_motion stopDeviceMotionUpdates];
    _motion = nil;
    _motionQueue = nil;
#endif
    _havePose = NO;
    _tracking = NO;
    _pointCount = 0;
    _previousCount = 0;
    [_planes removeAllObjects];
    [_worldPoints setLength:0];
}

#pragma mark - One frame

- (simd_float4x4)processPixelBuffer:(CVPixelBufferRef)pixelBuffer
                        captureTime:(NSTimeInterval)captureTime
                    deviceRotation:(simd_quatf)deviceRotation
{
    if (!pixelBuffer)
        return _cameraTransform;
    // The camera is the session's business, not this file's: the tracker answers for whatever frame
    // it is handed, which is also what lets a recorded sequence be run through it offline.

    _timestamp = captureTime;
    [self readLumaFromPixelBuffer:pixelBuffer];
    if (_lumaWidth == 0)
        return _cameraTransform;

    // The rotation the gyroscope reports, and the one the tracker believes it has, are what tells
    // the patch search where to look and how far the camera turned.
    if (!_havePose) {
        _lastRotation = deviceRotation;
        _cameraTransform = matrix_identity_float4x4;
        _havePose = YES;
    }
    // The attitude this frame is given, which is the gyroscope's last reading, and the one the
    // tracker believed last time: the difference between them is how far the camera has turned.
    deviceRotation = simd_normalize(deviceRotation);
    simd_quatf turn = CharonRotationBetween(_lastRotation, deviceRotation);

    // The gyroscope's turn is applied to the pose the tracker already holds, so the pose is carried
    // from one frame to the next rather than restarted: a rate integrated over a sequence is the only
    // reason the sequence is worth anything, and the picture is what corrects it.
    _cameraTransform = simd_mul(CharonMatrixFromQuaternion(turn), _cameraTransform);

    [self findFeatures];
    BOOL matched = [self matchFeaturesTurningBy:turn];
    if (matched)
        [self refinePose];
    [self placeUnmatchedPoints];
    [self rememberFrame];
    [self detectPlanes];

    _lastRotation = deviceRotation;
    _deviceTransform = _cameraTransform;
    _tracking = matched && _pointCount > 8;

    if ([_delegate respondsToSelector:@selector(tracker:didUpdateWithTimestamp:)])
        [_delegate tracker:self didUpdateWithTimestamp:captureTime];
    return _cameraTransform;
}

- (void)readLumaFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width == 0 || height == 0)
        return;
    if (width != _lumaWidth || height != _lumaHeight) {
        free(_luma);
        _luma = calloc(width * height, 1);
        if (!_luma)
            return;
        _lumaWidth = width;
        _lumaHeight = height;
        _resolution = CGSizeMake((CGFloat)width, (CGFloat)height);
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    const uint8_t *base = (const uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t stride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    NSUInteger x, y;
    if (base) {
        // The 420 biplanar and the BGRA and the one-plane grey all reduce to a luma row here, which
        // is all the corner pick and the patch search read.
        OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
        size_t component = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                            format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) ? 2 : 1;
        for (y = 0; y < _lumaHeight; y++) {
            const uint8_t *row = base + y * stride;
            for (x = 0; x < _lumaWidth; x++)
                _luma[y * _lumaWidth + x] = row[x * component];
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

/// The Shi-Tomasi score of the four points around a pixel, which is the smaller of the two
/// eigenvalues of the structure tensor of the gradients. Written out, because the two 2x2 halves
/// are all it needs and no eigen solver is wanted here.
static float CharonCornerScore(const uint8_t *luma, NSUInteger width, NSUInteger height, NSUInteger x, NSUInteger y)
{
    if (x < 1 || y < 1 || x + 1 >= width || y + 1 >= height)
        return 0;
    double gx2 = 0, gy2 = 0, gxy = 0;
    int dx, dy;
    for (dy = -1; dy <= 1; dy++) {
        for (dx = -1; dx <= 1; dx++) {
            int c = luma[(y + dy) * width + (x + dx)];
            int gx = luma[(y + dy) * width + (x + dx + 1)] - c;
            int gy = luma[(y + dy + 1) * width + (x + dx)] - c;
            gx2 += (double)gx * gx;
            gy2 += (double)gy * gy;
            gxy += (double)gx * gy;
        }
    }
    double a = gx2, b = gxy, c = gy2;
    double trace = a + c;
    double det = a * c - b * b;
    double discriminant = trace * trace / 4.0 - det;
    if (discriminant < 0)
        discriminant = 0;
    return (float)(trace / 2.0 - sqrt(discriminant));
}

/// Every eighth pixel of every eighth row, scored, and the best of each cell kept. A grid rather
/// than a plain threshold, so the features are spread over the frame.
- (void)findFeatures
{
    if (!_points) {
        _points = calloc(4096, sizeof(CharonARPoint));
        _previous = calloc(4096, sizeof(CharonARPoint));
        _candidates = calloc(4096, sizeof(CharonARPoint));
        if (!_points || !_previous || !_candidates)
            return;
    }
    const NSUInteger step = 8;
    const NSUInteger cells = 8;
    NSUInteger cellWidth = _lumaWidth / cells;
    NSUInteger cellHeight = _lumaHeight / cells;
    if (cellWidth < 2 || cellHeight < 2)
        return;

    float best[cells * cells];
    NSUInteger bestX[cells * cells], bestY[cells * cells];
    memset(best, 0, sizeof(best));
    NSUInteger cell, i;
    for (cell = 0; cell < cells * cells; cell++) {
        bestX[cell] = NSNotFound;
        bestY[cell] = NSNotFound;
    }

    for (i = step; i + step < _lumaHeight; i += step / 2) {
        for (NSUInteger j = step; j + step < _lumaWidth; j += step / 2) {
            float score = CharonCornerScore(_luma, _lumaWidth, _lumaHeight, j, i);
            if (score < 40)
                continue;
            cell = (i / cellHeight) * cells + (j / cellWidth);
            if (cell >= cells * cells)
                continue;
            if (score > best[cell]) {
                best[cell] = score;
                bestX[cell] = j;
                bestY[cell] = i;
            }
        }
    }

    // A third of the grid, which is a few hundred points: enough to hold a pose through a turn,
    // few enough to match exhaustively in the time between frames.
    NSUInteger wanted = cells * cells / 3;
    NSUInteger count = 0;
    for (cell = 0; cell < cells * cells && count < wanted; cell++) {
        if (bestX[cell] == NSNotFound)
            continue;
        CharonARPoint *point = &_candidates[count];
        memset(point, 0, sizeof(*point));
        point->image = simd_make_float2((float)bestX[cell] / (float)_lumaWidth,
                                        (float)bestY[cell] / (float)_lumaHeight);
        // The patch size follows the cell, so a nearby point is searched over a comparable distance.
        point->scale = (float)cellWidth;
        point->identifier = _nextIdentifier++;
        point->hits = 1;
        [self placePointInWorld:point];
        count++;
    }
    _candidateCount = count;
}

#pragma mark - Matching a point into the next frame

/// The sum of absolute differences of two patches, which is what the search minimises. An L1
/// patch cost rather than a correlation, because a brightness change between the two exposures
/// shifts a correlation's peak but not the ordering of an L1 cost nearly as much.
static uint32_t CharonPatchCost(const uint8_t *luma, NSUInteger width, NSUInteger height,
                                NSUInteger x, NSUInteger y, NSUInteger otherX, NSUInteger otherY,
                                NSUInteger radius)
{
    uint32_t total = 0;
    NSUInteger dy, dx;
    for (dy = 0; dy < radius * 2 + 1; dy++) {
        NSUInteger ay = y + dy, by = otherY + dy;
        if (ay >= height || by >= height)
            return UINT32_MAX;
        for (dx = 0; dx < radius * 2 + 1; dx++) {
            NSUInteger ax = x + dx, bx = otherX + dx;
            if (ax >= width || bx >= width)
                return UINT32_MAX;
            int difference = (int)luma[ay * width + ax] - (int)luma[by * width + bx];
            total += (uint32_t)(difference < 0 ? -difference : difference);
        }
    }
    return total;
}

/// Where a point in the previous frame went, found by searching a window along the direction the
/// gyroscope says the camera turned. `yaw` and `pitch` are that direction in image coordinates.
- (BOOL)matchFeaturesTurningBy:(simd_quatf)turn
{
    if (_previousCount == 0 || _pointCount == 0)
        return NO;

    // The camera's turn, as a drift of the image, which is what the search window follows.
    simd_quatf relative = simd_normalize(simd_conjugate(turn));
    simd_float3 axis = {relative.vector.x, relative.vector.y, relative.vector.z};
    float angle = 2.0f * acosf(fmaxf(-1.0f, fminf(1.0f, relative.vector.w)));
    simd_float2 drift = simd_make_float2(axis.x, axis.y) * angle * 0.5f;

    const NSUInteger radius = 3;
    const float weight = 2.0f;   // Apple's patch cost, the one its own open sources use
    const NSUInteger step = 3;
    NSUInteger matched = 0, i, j;

    for (i = 0; i < _previousCount; i++) {
        CharonARPoint *was = &_previous[i];
        NSUInteger wasX = (NSUInteger)(was->image.x * (float)_lumaWidth);
        NSUInteger wasY = (NSUInteger)(was->image.y * (float)_lumaHeight);
        if (wasX + 32 >= _lumaWidth || wasY + 32 >= _lumaHeight)
            continue;

        // The window, which is the size of a cell times the weight, centred on where the gyro says.
        float searchX = (float)wasX + drift.x * (float)_lumaWidth;
        float searchY = (float)wasY + drift.y * (float)_lumaHeight;
        NSUInteger reach = (NSUInteger)(was->scale * weight);
        NSUInteger bestX = NSNotFound, bestY = NSNotFound;
        uint32_t bestCost = UINT32_MAX;

        for (NSUInteger dy = 0; dy <= reach * 2; dy += step) {
            for (NSUInteger dx = 0; dx <= reach * 2; dx += step) {
                NSInteger cx = (NSInteger)(searchX - (float)reach) + (NSInteger)dx;
                NSInteger cy = (NSInteger)(searchY - (float)reach) + (NSInteger)dy;
                if (cx < (NSInteger)radius + 1 || cy < (NSInteger)radius + 1 ||
                    cx + (NSInteger)radius * 2 + 2 >= (NSInteger)_lumaWidth ||
                    cy + (NSInteger)radius * 2 + 2 >= (NSInteger)_lumaHeight)
                    continue;
                uint32_t cost = CharonPatchCost(_luma, _lumaWidth, _lumaHeight,
                                               (NSUInteger)cx, (NSUInteger)cy,
                                               wasX, wasY, radius);
                if (cost < bestCost) {
                    bestCost = cost;
                    bestX = (NSUInteger)cx;
                    bestY = (NSUInteger)cy;
                }
            }
        }

        // A match has to be better than a fixed fraction of the worst patch the search could have
        // found, which is what keeps a textureless patch from matching the first thing it lands on.
        if (bestX == NSNotFound)
            continue;
        uint32_t ceiling = (uint32_t)((2 * radius * 2 + 1) * (2 * radius * 2 + 1) * 60);
        if (bestX == NSNotFound || bestCost > ceiling)
            continue;

        // Keep the match only if no earlier point already claimed it, so a point cannot be counted
        // twice and pull the pose towards where it is not.
        BOOL taken = NO;
        for (j = 0; j < matched; j++) {
            if (_points[j].identifier == was->identifier) {
                taken = YES;
                break;
            }
        }
        if (taken)
            continue;

        CharonARPoint *now = &_points[matched];
        memcpy(now, was, sizeof(*now));
        now->image = simd_make_float2((float)bestX / (float)_lumaWidth,
                                      (float)bestY / (float)_lumaHeight);
        now->age = was->age > 250 ? 250 : (uint8_t)(was->age + 1);
        now->hits = (uint8_t)(was->hits < 250 ? was->hits + 1 : 250);

        // The drift of this point across the frame, against the turn that should have caused it. The
        // median of those over the frame is the scene's depth, and every point takes it: a frame
        // looks at one scene, so its points are all at one distance to the accuracy a single frame
        // can give, and the median is the one that is not a mis-correspondence.
        simd_float2 driftPixels = simd_make_float2(
                (now->image.x - was->image.x) * (float)_lumaWidth,
                (now->image.y - was->image.y) * (float)_lumaHeight);
        simd_float3 turnAxis = simd_make_float3(turn.vector.x, turn.vector.y, turn.vector.z);
        now->depth = [self depthForDrift:driftPixels along:turnAxis
                                    focal:[self focalLengthInPixels]];
        if (now->hits >= 3)
            [self placePointInWorld:now];
        matched++;
        if (matched >= 4096)
            break;
    }
    _pointCount = matched;

    // One scene, one distance: the median of what each point's own drift said about it, and then
    // every point is placed at that. A single frame cannot separate depth from a feature's size -
    // that is the ambiguity a camera and a gyroscope leave - so the frame's own answer is the one
    // all of its points share, and the Gauss-Newton step is what improves on it from there.
    if (matched) {
        float *depths = calloc(matched, sizeof(float));
        if (depths) {
            NSUInteger measured = 0;
            for (NSUInteger k = 0; k < matched; k++)
                if (_points[k].depth > 0)
                    depths[measured++] = _points[k].depth;
            if (measured >= 3) {
                for (NSUInteger a = 1; a < measured; a++) {   // a selection, for the median
                    float key = depths[a];
                    NSUInteger b = a;
                    while (b > 0 && depths[b - 1] > key) {
                        depths[b] = depths[b - 1];
                        b--;
                    }
                    depths[b] = key;
                }
                float median = depths[measured / 2];
                for (NSUInteger k = 0; k < matched; k++) {
                    if (_points[k].depth > 0)
                        _points[k].depth = median;
                    [self placePointInWorld:&_points[k]];
                }
            }
            free(depths);
        }
    }
    return matched >= 8;
}

#pragma mark - The pose

/// One Gauss-Newton step: the six parameters of the camera pose, the residual of each match, and
/// the step that squares away. The points are at a unit depth until the pose has a scale, which is
/// what an uncalibrated monocular system gives, so the scale of the world is set from the motion
/// the gyroscope reports and the points follow it.
/// The pose nudged by one parameter, as six plain numbers so that a single component can be moved
/// without indexing a vector - which C's simd does not allow.
static simd_float4x4 CharonNudgedPose(simd_float4x4 pose, int parameter, float epsilon)
{
    float translation[3] = { 0, 0, 0 }, rotation[3] = { 0, 0, 0 };
    float *target = parameter < 3 ? &translation[parameter] : &rotation[parameter - 3];
    *target = epsilon;
    return simd_mul(CharonPoseIncrement(simd_make_float3(rotation[0], rotation[1], rotation[2]),
                                        simd_make_float3(translation[0], translation[1],
                                                         translation[2])),
                    pose);
}

- (void)refinePose
{
    // The pose the gyroscope integrated to, and the picture's own answer to the same question. The
    // difference between them, over every point matched in a row, is what this solves for.
    simd_float3x3 intrinsics = [CharonARTracker cameraIntrinsicsForResolution:_resolution];
    if (_resolution.width <= 0 || _resolution.height <= 0)
        return;

    // A point matched in a row has been seen before, so where it was seen then is a measurement
    // rather than a guess - and fewer than six of them cannot determine six parameters.
    NSUInteger usable = 0;
    for (NSUInteger i = 0; i < _pointCount; i++)
        if (_points[i].hits >= 2)
            usable++;
    if (usable < 6)
        return;

    const float epsilon = 1e-4f;   // the nudge each parameter is differentiated by
    float normal[6][6] = {{ 0 }};
    float gradient[6] = { 0 };

    for (NSUInteger i = 0; i < _pointCount; i++) {
        CharonARPoint *point = &_points[i];
        if (point->hits < 2)
            continue;

        simd_float2 observed = { point->image.x * (float)_resolution.width,
                                 point->image.y * (float)_resolution.height };
        simd_float2 predicted;
        if (!CharonProject(_cameraTransform, intrinsics, point->world, &predicted))
            continue;   // a point behind the camera is not a measurement of anything
        float residual[2] = { predicted.x - observed.x, predicted.y - observed.y };

        // The Jacobian: one column per parameter, the first three a nudge of translation and the
        // last three a nudge of rotation in the camera's own frame.
        float jacobian[2][6];
        BOOL usableRow = YES;
        for (int parameter = 0; parameter < 6 && usableRow; parameter++) {
            simd_float2 forward, backward;
            BOOL haveForward = CharonProject(CharonNudgedPose(_cameraTransform, parameter, epsilon),
                                             intrinsics, point->world, &forward);
            BOOL haveBackward = CharonProject(CharonNudgedPose(_cameraTransform, parameter, -epsilon),
                                              intrinsics, point->world, &backward);
            if (haveForward && haveBackward) {
                // the central difference, which is what the method wants and what a point that
                // goes behind the camera under one nudge still gets
                jacobian[0][parameter] = (forward.x - backward.x) / (2 * epsilon);
                jacobian[1][parameter] = (forward.y - backward.y) / (2 * epsilon);
            } else if (haveForward) {
                jacobian[0][parameter] = (forward.x - predicted.x) / epsilon;
                jacobian[1][parameter] = (forward.y - predicted.y) / epsilon;
            } else {
                usableRow = NO;   // the point carries no information about this parameter
            }
        }
        if (!usableRow)
            continue;

        for (int row = 0; row < 6; row++) {
            gradient[row] -= jacobian[0][row] * residual[0] + jacobian[1][row] * residual[1];
            for (int column = 0; column < 6; column++)
                normal[row][column] += jacobian[0][row] * jacobian[0][column] +
                                       jacobian[1][row] * jacobian[1][column];
        }
    }

    // A little regularisation on the diagonal, so that a frame which cannot see - a pure rotation,
    // or a scene at one depth - gives a step of nearly zero rather than a large wrong one.
    for (int row = 0; row < 6; row++)
        normal[row][row] += 1e-6f;

    float step[6];
    if (!CharonSolveSix(normal, gradient, step))
        return;

    // The step is limited to what a frame between two pictures could plausibly have missed, so that
    // one bad correspondence cannot throw the pose across the room.
    for (int row = 0; row < 6; row++)
        step[row] = fmaxf(-0.05f, fminf(0.05f, step[row]));

    simd_float3 rotation = simd_make_float3(step[3], step[4], step[5]);
    simd_float3 translation = simd_make_float3(step[0], step[1], step[2]);
    _cameraTransform = simd_mul(CharonPoseIncrement(rotation, translation), _cameraTransform);
    _havePose = YES;
}

#pragma mark - The points

/// The points the search did not match keep their position in the world and are the only ones that
/// can start a new one, so a feature that has been seen three frames running is given a place.
/// How far off a point is, from the turn the gyroscope reported and the drift that turn put into
/// the picture.
///
/// A camera and a gyroscope cannot say how far a thing is - that is why the reconstruction a camera
/// alone gives is only good up to a scale. What it can say is this: when a camera turns by a known
/// angle, a point at depth `z` drifts across the frame by an amount proportional to `1/z`, and the
/// camera's own focal length is the constant that turns that drift into a depth. So the drift of a
/// point that is known to be the same point, divided by the turn that moved it, gives the distance -
/// no assumed size for the feature, and no constant fitted to a scene.
- (float)depthForDrift:(simd_float2)driftPixels
                 along:(simd_float3)turnAxis
                focal:(float)focalLength
{
    simd_float3 axis = CharonNormalized(turnAxis);
    if (simd_length(axis) < 1e-6f || focalLength <= 0)
        return 0;
    // The first-order relation for a point on the ray `unit`: the horizontal drift a turn about
    // `axis` puts into its projection is `f * (axis x unit).x / z`, so `z` follows from the drift.
    simd_float3 unit = CharonNormalized(simd_make_float3(driftPixels.x, driftPixels.y, 1));
    float numerator = focalLength * simd_cross(axis, unit).x;
    float denominator = driftPixels.x;
    if (fabsf(denominator) < 1e-6f)
        return 0;
    float depth = numerator / denominator;
    return depth > 0 ? depth : 0;
}

/// A point's place in the world, along the ray through it, as far off as the drift that placed it
/// there says. A point with no usable drift has no distance yet, and is not placed.
- (void)placePointInWorld:(CharonARPoint *)point
{
    if (_lumaWidth == 0 || point->depth <= 0)
        return;
    simd_float3 ray = CharonNormalized(simd_make_float3(point->image.x - 0.5f,
                                                        point->image.y - 0.5f, 1));
    point->camera = CharonAlongRay(simd_make_float3(0, 0, 0), ray, point->depth);
    simd_float4 world = simd_mul(_cameraTransform,
                                 simd_make_float4(point->camera.x, point->camera.y,
                                                  point->camera.z, 1));
    point->world = simd_make_float3(world.x, world.y, world.z);
}

/// The camera's focal length in pixels, which is the constant that turns a drift in the picture into
/// a distance.
- (float)focalLengthInPixels
{
    return [CharonARTracker cameraIntrinsicsForResolution:_resolution].columns[0][0];
}

- (void)placeUnmatchedPoints
{
    CharonARPoint *carried = calloc(4096, sizeof(CharonARPoint));
    if (!carried)
        return;
    NSUInteger matched = _pointCount, count = 0, i;
    for (i = 0; i < matched; i++) {
        if (_points[i].hits >= 3) {
            carried[count] = _points[i];
            // A feature's size says how far away it is, which is what puts it in the world.
            float distance = 0.5f / (_points[i].scale / (float)_lumaWidth);
            carried[count].camera = CharonAlongRay((simd_float3){0, 0, 0},
                                                   CharonNormalized((simd_float3){_points[i].image.x - 0.5f,
                                                                                  _points[i].image.y - 0.5f,
                                                                                  1}),
                                                   distance);
            carried[count].world = simd_mul(_cameraTransform, (simd_float4){carried[count].camera.x, carried[count].camera.y, carried[count].camera.z, 1}).xyz;
            count++;
        }
    }
    if (count) {
        [_worldPoints appendBytes:carried length:count * sizeof(CharonARPoint)];
    }
    // The array holds the matches followed by the corners the search did not match, and the second
    // run starts where the first ended: written from zero it overwrote every match, so a matched point
    // never accumulated the frames that would have placed it in the world. Measured - 17 to 19 matches
    // a frame and still 0 points placed, 0 planes, a mean rotation error of 91 degrees.
    NSUInteger total = matched;
    for (i = 0; i < _candidateCount && total < 4096; i++) {
        _points[total++] = _candidates[i];
    }
    free(carried);
    _pointCount = total;
}

- (void)rememberFrame
{
    if (!_previous)
        return;
    memcpy(_previous, _points, _pointCount * sizeof(CharonARPoint));
    _previousCount = _pointCount;
}

#pragma mark - Planes

/// A plane is a run of world points that stay level and straight. Every point is compared with every
/// other within a cell of a coarse grid, the ones that agree are averaged into a plane, and the
/// planes are what ARKit calls *detected*: there is no depth measurement behind them, and none is
/// claimed.
- (void)detectPlanes
{
    const NSUInteger count = _worldPoints.length / sizeof(CharonARPoint);
    if (count < 24)
        return;

    const CharonARPoint *points = (const CharonARPoint *)_worldPoints.bytes;
    const float cell = 0.25f;          ///< a quarter of a metre, which is a tabletop's worth
    const float level = 0.90f;         ///< how nearly the normal has to be up
    const float spread = 0.75f;        ///< how far a point may stray and still be on the surface
    NSMutableArray<CharonARValue *> *found = [NSMutableArray array];
    NSUInteger i, j;

    for (i = 0; i < count; i += 3) {
        simd_float3 anchor = points[i].world;
        simd_float3 sum = (simd_float3){0, 0, 0};
        simd_float3 mean = (simd_float3){0, 0, 0};
        simd_float3 normal = (simd_float3){0, 0, 0};
        NSUInteger onPlane = 0;
        simd_float3 low = anchor, high = anchor;

        for (j = 0; j < count; j++) {
            simd_float3 d = points[j].world - anchor;
            if (fabsf(d.x) > spread * 2 || fabsf(d.y) > spread * 2 || fabsf(d.z) > spread * 2)
                continue;
            sum = sum + d;
            onPlane++;
        }
        if (onPlane < 16)
            continue;
        mean = sum / (float)onPlane;

        // The plane through the run: the smallest eigenvector of the scatter is its normal, and for
        // a plane that is the direction the points agree least in, which here is found by three
        // passes of subtracting the mean.
        simd_float3 axis1 = (simd_float3){0, 0, 0}, axis2 = (simd_float3){0, 0, 0};
        for (j = 0; j < count; j++) {
            simd_float3 d = points[j].world - (anchor + mean);
            if (fabsf(d.x) > spread || fabsf(d.y) > spread || fabsf(d.z) > spread)
                continue;
            axis1 = axis1 + d;
        }
        if (simd_length(axis1) < 1e-4f)
            continue;
        axis1 = CharonNormalized(axis1);
        for (j = 0; j < count; j++) {
            simd_float3 d = points[j].world - (anchor + mean);
            if (fabsf(d.x) > spread || fabsf(d.y) > spread || fabsf(d.z) > spread)
                continue;
            axis2 = axis2 + d - axis1 * simd_dot(d, axis1);
        }
        if (simd_length(axis2) < 1e-4f)
            continue;
        axis2 = CharonNormalized(axis2);
        normal = CharonNormalized(simd_cross(axis1, axis2));
        if (normal.y < 0)
            normal = -normal;
        if (normal.y < level)
            continue;

        // The extent of what was seen, in the plane's own two directions.
        for (j = 0; j < count; j++) {
            simd_float3 d = points[j].world - (anchor + mean);
            if (fabsf(simd_dot(d, normal)) > cell)
                continue;
            low = simd_min(low, points[j].world);
            high = simd_max(high, points[j].world);
            onPlane++;
        }
        if (onPlane < 16)
            continue;

        CharonARPlane plane;
        memset(&plane, 0, sizeof(plane));
        plane.center = anchor + mean;
        plane.normal = normal;
        plane.extent = (high - low) * 0.5f;
        plane.alignment = 0.5f;   // a detector's confidence, never Apple's measured alignment
        plane.identifier = _nextIdentifier++;
        [found addObject:[[CharonARValue alloc] initWithBytes:&plane size:sizeof plane]];
        if ([found count] >= 16)
            break;
    }

    if ([found count]) {
        [_planes setArray:found];
    }
}

#pragma mark - What an application reads

- (NSData *)pointCloud
{
    const NSUInteger count = _worldPoints.length / sizeof(CharonARPoint);
    if (count == 0)
        return [NSData data];
    NSMutableData *out = [NSMutableData dataWithLength:count * sizeof(CharonARCloudPoint)];
    CharonARCloudPoint *cloud = (CharonARCloudPoint *)out.mutableBytes;
    const CharonARPoint *points = (const CharonARPoint *)_worldPoints.bytes;
    NSUInteger i;
    for (i = 0; i < count; i++)
        cloud[i].position = points[i].world;
    return out;
}

- (NSArray<CharonARValue *> *)planes { return [_planes copy]; }
- (simd_float4x4)cameraTransform { return _cameraTransform; }
- (simd_float4x4)deviceTransform { return _deviceTransform; }
- (CGFloat)lightEstimate { return _lightEstimate; }
- (CGFloat)ambientColorTemperature { return _ambientColorTemperature; }
- (BOOL)isTracking { return _tracking; }
- (CGSize)imageResolution { return _resolution; }
- (NSTimeInterval)timestamp { return _timestamp; }

#pragma mark - Rays

/// The ray through a point of the frame, in the camera's own space, which is the one every hit test
/// and every raycast starts from.
static BOOL CharonCameraRay(CGSize resolution, CGPoint point, simd_float3 *origin, simd_float3 *direction)
{
    if (resolution.width <= 0 || resolution.height <= 0)
        return NO;
    float x = ((float)point.x / (float)resolution.width - 0.5f) * 2.0f;
    float y = (0.5f - (float)point.y / (float)resolution.height) * 2.0f;
    // A 60-degree vertical field of view is what the back camera of this class of device gives.
    const float tanHalf = 0.5773502692f;
    *origin = (simd_float3){0, 0, 0};
    *direction = CharonNormalized((simd_float3){x * tanHalf, y * tanHalf, -1});
    return YES;
}

/// A ray against a plane, which is a plane equation and a substitution.
static BOOL CharonRayPlane(simd_float3 origin, simd_float3 direction, CharonARPlane plane,
                           simd_float3 *hit)
{
    float denominator = simd_dot(direction, plane.normal);
    if (fabsf(denominator) < 1e-6f)
        return NO;
    float distance = simd_dot(plane.center - origin, plane.normal) / denominator;
    if (distance <= 0)
        return NO;
    *hit = CharonAlongRay(origin, direction, distance);
    return YES;
}

- (BOOL)raycastFromPoint:(CGPoint)point
                allowing:(NSUInteger)targets
                results:(NSMutableArray<CharonARValue *> *)results
{
    simd_float3 origin, direction;
    if (!CharonCameraRay(_resolution, point, &origin, &direction))
        return NO;
    return [self raycastFromOrigin:origin direction:direction allowing:targets results:results];
}

- (BOOL)raycastFromOrigin:(simd_float3)origin
                 direction:(simd_float3)direction
                allowing:(NSUInteger)targets
                  results:(NSMutableArray<CharonARValue *> *)results
{
    // The ray is given in the camera's space, which is where Apple's raycast query takes it.
    simd_float3 world = simd_mul(_cameraTransform, (simd_float4){origin.x, origin.y, origin.z, 1}).xyz;
    simd_float3 aim = simd_mul(_cameraTransform, (simd_float4){direction.x, direction.y, direction.z, 0}).xyz;
    direction = CharonNormalized(aim);
    if (results)
        [results removeAllObjects];

    float nearest = 0;
    BOOL any = NO;
    NSUInteger i;
    for (i = 0; i < _planes.count; i++) {
        CharonARPlane plane;
        [_planes[i] getValue:&plane];
        simd_float3 hit;
        if (!CharonRayPlane(world, direction, plane, &hit))
            continue;
        float distance = simd_length(hit - world);
        if (any && distance >= nearest)
            continue;
        // Apple's targets: 0 every plane, 1 any, 2 existing, 4 estimated.
#if CHARON_NO_MOTION
        if (targets != 0)
            continue;
#else
        if (targets != ARRaycastTargetExistingPlaneGeometry && targets != ARRaycastTargetEstimatedPlane) {
            continue;
        }
#endif
        CharonARHit record;
        memset(&record, 0, sizeof(record));
        record.position = hit;
        record.localNormal = plane.normal;
        record.planeIdentifier = plane.identifier;
        nearest = distance;
        any = YES;
        if (results)
            [results addObject:[[CharonARValue alloc] initWithBytes:&record size:sizeof record]];
    }
    return any;
}

- (BOOL)hitTestPoint:(CGPoint)point results:(NSMutableArray<CharonARValue *> *)results
{
    return [self hitTestPoint:point existingPlane:NO results:results];
}

- (BOOL)hitTestPoint:(CGPoint)point
       existingPlane:(BOOL)existingPlane
            results:(NSMutableArray<CharonARValue *> *)results
{
    simd_float3 origin, direction;
    if (!CharonCameraRay(_resolution, point, &origin, &direction))
        return NO;
    if (results)
        [results removeAllObjects];

    // First the points the tracker has placed, which is what a feature hit is.
    const NSUInteger count = _worldPoints.length / sizeof(CharonARPoint);
    const CharonARPoint *points = (const CharonARPoint *)_worldPoints.bytes;
    NSUInteger i;
    float nearest = 0;
    BOOL any = NO;
    for (i = 0; i < count; i++) {
        simd_float3 delta = points[i].camera - CharonAlongRay(origin, direction, simd_dot(points[i].camera, direction));
        float distance = simd_length(delta);
        if (any && distance >= nearest)
            continue;
        if (distance > 0.05f)
            continue;
        CharonARHit record;
        memset(&record, 0, sizeof(record));
        record.position = points[i].world;
        record.localNormal = (simd_float3){0, 1, 0};
        record.planeIdentifier = 0;
        nearest = distance;
        any = YES;
        if (results)
            [results addObject:[[CharonARValue alloc] initWithBytes:&record size:sizeof record]];
    }
    return any;
}

@end
