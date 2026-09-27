// ARSession.m - the session: it owns the camera and the gyroscope, and it hands the application one
// frame at a time with the camera's pose, the points it has found and the planes it has detected in
// them.
//
// The run loop is the release's own `AVCaptureVideoDataOutput` and `CMMotionManager`, read through
// the tracker's pipeline. Frames arrive on the capture queue; the delegate is called on the queue the
// application named, or on the main queue as the header says.

#import <ARKit/ARKit.h>

#import "CharonARTracker.h"
#import "CharonARKitPrivate.h"

@interface ARSession () <CharonARTrackerDelegate>
@end

@implementation ARSession
{
    CharonARTracker *_tracker;
    NSOperationQueue *_captureQueue;
    NSMutableArray<ARAnchor *> *_anchors;
    NSMutableArray<ARAnchor *> *_pending;
    NSUUID *_identifier;
    ARConfiguration *_configuration;
    NSUInteger _runOptions;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    _tracker = [[CharonARTracker alloc] init];
    _tracker.delegate = self;
    _anchors = [NSMutableArray array];
    _pending = [NSMutableArray array];
    _identifier = [NSUUID UUID];
    _captureQueue = [[NSOperationQueue alloc] init];
    _captureQueue.maxConcurrentOperationCount = 1;
    _captureQueue.name = @"space.kern0x1b.arkit.capture";
    return self;
}

- (void)dealloc
{
    [_tracker stop];
    _captureQueue = nil;
}

- (NSUUID *)identifier { return _identifier; }

- (ARConfiguration *)configuration { return _configuration; }
- (ARFrame *)currentFrame { return nil; }

#pragma mark - Running

- (void)runWithConfiguration:(ARConfiguration *)configuration
{
    [self runWithConfiguration:configuration options:0];
}

- (void)runWithConfiguration:(ARConfiguration *)configuration options:(NSUInteger)options
{
    if (![[configuration class] isSupported])
        return;
    [_tracker stop];
    NSError *error = nil;
    if (![_tracker startWithError:&error]) {
        // The hardware said no, so the application is told through the same channel it uses for
        // everything else, and the session stays paused.
        _configuration = configuration;
        if ([_delegate respondsToSelector:@selector(session:didFailWithError:)])
            [_delegate session:self didFailWithError:error];
        return;
    }
    _configuration = configuration;
    _runOptions = options;
    if (options & ARSessionRunOptionResetTracking) {
        [_tracker stop];
        [_tracker startWithError:NULL];
    }
    if (options & ARSessionRunOptionRemoveExistingAnchors)
        [_anchors removeAllObjects];
    if ([_delegate respondsToSelector:@selector(session:didUpdateFrame:)])
        ;   // the first frame is delivered by the tracker's first update
}

- (void)pause
{
    [_tracker stop];
}

#pragma mark - Anchors

- (void)addAnchor:(ARAnchor *)anchor
{
    if (anchor)
        [_pending addObject:anchor];
}

- (void)removeAnchor:(ARAnchor *)anchor
{
    if (!anchor)
        return;
    [_pending removeObject:anchor];
    [_anchors removeObject:anchor];
}

#pragma mark - What the tracker reports

- (void)tracker:(CharonARTracker *)tracker didUpdateWithTimestamp:(NSTimeInterval)timestamp
{
    // Whatever was added since the last frame is now part of the world, and the application's own
    // anchors are handed back with it.
    NSArray<ARAnchor *> *added = [_pending copy];
    [_pending removeAllObjects];
    for (ARAnchor *anchor in added) {
        anchor.identifier = [NSUUID UUID];
        [_anchors addObject:anchor];
    }

    ARFrame *frame = [[ARFrame alloc] initWithCameraTransform:tracker.cameraTransform
                                                deviceTransform:tracker.deviceTransform
                                                   cameraTransformTime:timestamp
                                                   imageResolution:tracker.imageResolution
                                                        lightEstimate:tracker.lightEstimate
                                              ambientColorTemperature:tracker.ambientColorTemperature
                                                        tracking:tracker.isTracking];
    for (ARPlaneAnchor *plane in [self planeAnchorsForTracker:tracker])
        [frame addAnchor:plane];

    dispatch_queue_t queue = _delegateQueue ?: dispatch_get_main_queue();
    dispatch_async(queue, ^{
        if ([self.delegate respondsToSelector:@selector(session:didUpdateFrame:)])
            [self.delegate session:self didUpdateFrame:frame];
        if ([self.delegate respondsToSelector:@selector(session:didAddAnchors:)])
            [self.delegate session:self didAddAnchors:added];
    });
}

/// The planes the detector found, as the plane anchors an application subscribes to. They are
/// detected, never measured: there is no depth sensor behind them, and a plane anchor's alignment
/// is left at Apple's "not determined" because there is nothing to determine it from.
- (NSArray<ARPlaneAnchor *> *)planeAnchorsForTracker:(CharonARTracker *)tracker
{
    NSMutableArray<ARPlaneAnchor *> *out = [NSMutableArray array];
    for (NSValue *value in tracker.planes) {
        [out addObject:[[ARPlaneAnchor alloc] initWithPlaneValue:value]];
    }
    return out;
}

#pragma mark - What an application asks the session to do

- (void)hitTestPoint:(CGPoint)point
        types:(ARHitTestResultType)types
       results:(NSMutableArray<ARHitTestResult *> *)results
{
    NSMutableArray<NSValue *> *hits = [NSMutableArray array];
    if (types & ARHitTestResultTypeFeaturePoint)
        [_tracker hitTestPoint:point results:hits];
    if (types & (ARHitTestResultTypeExistingPlaneUsingGeometry |
                 ARHitTestResultTypeEstimatedHorizontalPlane |
                 ARHitTestResultTypeEstimatedVerticalPlane))
        [_tracker hitTestPoint:point existingPlane:YES results:hits];
    for (NSValue *value in hits)
        [results addObject:[[ARHitTestResult alloc] initWithHitValue:value]];
}

- (void)raycastWithQuery:(ARRaycastQuery *)query
              results:(NSMutableArray<ARRaycastResult *> *)results
{
    NSMutableArray<NSValue *> *hits = [NSMutableArray array];
    // The SDK's own spelling: the ray starts at a point of the world and runs along a direction of it.
    [_tracker raycastFromOrigin:query.origin direction:query.direction
                         allowing:query.target results:hits];
    for (NSValue *value in hits)
        [results addObject:[[ARRaycastResult alloc] initWithHitValue:value]];
}

@end
