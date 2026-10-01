#import "CharonVision.h"
#import <simd/simd.h>
#import <math.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wnullability-completeness"
#pragma clang diagnostic ignored "-Wprotocol"

/* Everything this file carries arrived in iOS 14.0, and it is the part of that release which is
 * arithmetic rather than a model: a point, a vector, a circle, the smallest circle around a set of
 * points, the base class a request that carries evidence over time is built on, and the two values
 * that say how often a video is analysed. None of it needs a Vision engine, and none of it needs
 * anything iOS 6 does not have - the arithmetic is doubles and the geometry is CoreGraphics, which
 * this library already links.
 *
 * What is NOT here is the part of 14.0 that runs a model: the contour, body pose, hand pose,
 * trajectory and optical flow requests, the observations only those requests produce, and the video
 * processor that would run a request over decoded video. Each of those rows says absent, and says
 * what is missing. */

static double charon_vision_squared_distance(double x1, double y1, double x2, double y2)
{
    double dx = x1 - x2, dy = y1 - y2;
    return dx * dx + dy * dy;
}

/* A point as the bounding circle works on it: two doubles, so the same code takes a VNPoint and the
 * simd_float2 buffer a contour is made of. */
typedef struct {
    double x;
    double y;
} CharonVisionXY;

/* The smallest circle that holds a set of points, found by the same three cases the algorithm is
 * written as: one point on its own, two as a diameter, three as the circle through them. `count` is
 * zero for a circle nothing has been found for yet, which is how the loops below tell "no circle"
 * from "a circle of radius zero". */
typedef struct {
    CharonVisionXY center;
    double radius;
    int count;
} CharonVisionCircle;

static CharonVisionCircle charon_vision_circle_of_one(CharonVisionXY point)
{
    CharonVisionCircle circle = {{point.x, point.y}, 0.0, 1};
    return circle;
}

static CharonVisionCircle charon_vision_circle_of_two(CharonVisionXY a, CharonVisionXY b)
{
    CharonVisionCircle circle;
    circle.center.x = (a.x + b.x) / 2.0;
    circle.center.y = (a.y + b.y) / 2.0;
    circle.radius = sqrt(charon_vision_squared_distance(a.x, a.y, b.x, b.y)) / 2.0;
    circle.count = 2;
    return circle;
}

/* Three points on one circle, unless they are on a line - and three points on a line have no circle
 * through them, so the one that holds all three is the one over the two farthest apart. */
static CharonVisionCircle charon_vision_circle_of_three(CharonVisionXY a, CharonVisionXY b, CharonVisionXY c)
{
    CharonVisionCircle circle;
    double d = 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
    if (fabs(d) < 1e-18) {
        double ab = charon_vision_squared_distance(a.x, a.y, b.x, b.y);
        double ac = charon_vision_squared_distance(a.x, a.y, c.x, c.y);
        double bc = charon_vision_squared_distance(b.x, b.y, c.x, c.y);
        if (ab >= ac && ab >= bc)
            return charon_vision_circle_of_two(a, b);
        if (ac >= bc)
            return charon_vision_circle_of_two(a, c);
        return charon_vision_circle_of_two(b, c);
    }
    double a2 = a.x * a.x + a.y * a.y;
    double b2 = b.x * b.x + b.y * b.y;
    double c2 = c.x * c.x + c.y * c.y;
    circle.center.x = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
    circle.center.y = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
    circle.radius = sqrt(charon_vision_squared_distance(circle.center.x, circle.center.y, a.x, a.y));
    circle.count = 3;
    return circle;
}

/* Points are normalized, so the radius is of the order of one and this is the slack a point may sit
 * outside the circle by and still be treated as inside it. Without it the answer depends on the
 * order the points arrive in, which the caller does not choose. */
static BOOL charon_vision_circle_holds(CharonVisionCircle circle, CharonVisionXY point)
{
    if (circle.count == 0)
        return NO;
    return charon_vision_squared_distance(circle.center.x, circle.center.y, point.x, point.y)
        <= circle.radius * circle.radius + 1e-12;
}

/* The order the points are visited in is what decides how long the three loops below take, so they
 * are shuffled first. The generator is seeded with a constant on purpose: the same points then
 * answer the same circle on every run and on every device, which a clock-seeded shuffle would not. */
static void charon_vision_shuffle(CharonVisionXY *points, NSInteger count)
{
    uint32_t seed = 0x5f3759dfu;
    for (NSInteger index = count - 1; index > 0; index--) {
        CharonVisionXY swap;
        seed = seed * 1664525u + 1013904223u;
        NSInteger other = (NSInteger)(seed % (uint32_t)(index + 1));
        swap = points[index];
        points[index] = points[other];
        points[other] = swap;
    }
}

/* The smallest circle holding every point, or a circle of count zero when there is no point. The
 * argument is shuffled, so the caller hands over a copy it does not keep. */
static CharonVisionCircle charon_vision_bounding_circle(CharonVisionXY *points, NSInteger count)
{
    CharonVisionCircle circle = {{0.0, 0.0}, 0.0, 0};
    if (count <= 0)
        return circle;
    charon_vision_shuffle(points, count);
    for (NSInteger i = 0; i < count; i++) {
        if (charon_vision_circle_holds(circle, points[i]))
            continue;
        circle = charon_vision_circle_of_one(points[i]);
        for (NSInteger j = 0; j < i; j++) {
            if (charon_vision_circle_holds(circle, points[j]))
                continue;
            circle = charon_vision_circle_of_two(points[i], points[j]);
            for (NSInteger k = 0; k < j; k++) {
                if (charon_vision_circle_holds(circle, points[k]))
                    continue;
                circle = charon_vision_circle_of_three(points[i], points[j], points[k]);
            }
        }
    }
    return circle;
}

@implementation VNPoint {
    double _x;
    double _y;
}

+ (VNPoint *)zeroPoint
{
    static VNPoint *zero;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        zero = [[VNPoint alloc] initWithX:0.0 y:0.0];
    });
    return zero;
}

+ (VNPoint *)pointByApplyingVector:(VNVector *)vector toPoint:(VNPoint *)point
{
    if (vector == nil || point == nil) {
        return nil;
    }
    return [[self alloc] initWithX:point.x + vector.x y:point.y + vector.y];
}

+ (double)distanceBetweenPoint:(VNPoint *)point1 point:(VNPoint *)point2
{
    if (point1 == nil || point2 == nil) {
        return NAN;
    }
    return [point1 distanceToPoint:point2];
}

- (instancetype)initWithX:(double)x y:(double)y
{
    if ((self = [super init])) {
        _x = x;
        _y = y;
    }
    return self;
}

- (instancetype)initWithLocation:(CGPoint)location
{
    return [self initWithX:(double)location.x y:(double)location.y];
}

- (double)distanceToPoint:(VNPoint *)point
{
    if (point == nil) {
        return NAN;
    }
    return hypot(_x - point.x, _y - point.y);
}

- (CGPoint)location
{
    return CGPointMake((CGFloat)_x, (CGFloat)_y);
}

- (double)x
{
    return _x;
}

- (double)y
{
    return _y;
}

- (id)copyWithZone:(NSZone *)zone
{
    VNPoint *copy = charon_vision_clone(self, zone);
    return copy;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_x forKey:@"x"];
    [coder encodeDouble:_y forKey:@"y"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithX:[coder decodeDoubleForKey:@"x"] y:[coder decodeDoubleForKey:@"y"]];
}

@end

@implementation VNVector {
    double _x;
    double _y;
}

+ (VNVector *)zeroVector
{
    static VNVector *zero;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        zero = [[VNVector alloc] initWithXComponent:0.0 yComponent:0.0];
    });
    return zero;
}

+ (VNVector *)unitVectorForVector:(VNVector *)vector
{
    double length;
    if (vector == nil) {
        return nil;
    }
    length = vector.length;
    /* A vector of no length has no direction to preserve, so the unit vector of one is the zero
     * vector rather than a division by zero. */
    if (length == 0.0) {
        return [self zeroVector];
    }
    return [[self alloc] initWithXComponent:vector.x / length yComponent:vector.y / length];
}

+ (VNVector *)vectorByMultiplyingVector:(VNVector *)vector byScalar:(double)scalar
{
    if (vector == nil) {
        return nil;
    }
    return [[self alloc] initWithXComponent:vector.x * scalar yComponent:vector.y * scalar];
}

+ (VNVector *)vectorByAddingVector:(VNVector *)v1 toVector:(VNVector *)v2
{
    if (v1 == nil || v2 == nil) {
        return nil;
    }
    return [[self alloc] initWithXComponent:v1.x + v2.x yComponent:v1.y + v2.y];
}

+ (VNVector *)vectorBySubtractingVector:(VNVector *)v1 fromVector:(VNVector *)v2
{
    if (v1 == nil || v2 == nil) {
        return nil;
    }
    return [[self alloc] initWithXComponent:v2.x - v1.x yComponent:v2.y - v1.y];
}

+ (double)dotProductOfVector:(VNVector *)v1 vector:(VNVector *)v2
{
    if (v1 == nil || v2 == nil) {
        return NAN;
    }
    return v1.x * v2.x + v1.y * v2.y;
}

- (instancetype)initWithXComponent:(double)x yComponent:(double)y
{
    if ((self = [super init])) {
        _x = x;
        _y = y;
    }
    return self;
}

- (instancetype)initWithR:(double)r theta:(double)theta
{
    return [self initWithXComponent:r * cos(theta) yComponent:r * sin(theta)];
}

- (instancetype)initWithVectorHead:(VNPoint *)head tail:(VNPoint *)tail
{
    if (head == nil || tail == nil) {
        return nil;
    }
    return [self initWithXComponent:head.x - tail.x yComponent:head.y - tail.y];
}

- (double)x
{
    return _x;
}

- (double)y
{
    return _y;
}

- (double)r
{
    return self.length;
}

- (double)theta
{
    /* The header says the angle of the zero vector is not defined, and says so as NaN. */
    if (_x == 0.0 && _y == 0.0) {
        return NAN;
    }
    return atan2(_y, _x);
}

- (double)length
{
    return hypot(_x, _y);
}

- (double)squaredLength
{
    return _x * _x + _y * _y;
}

- (id)copyWithZone:(NSZone *)zone
{
    VNVector *copy = charon_vision_clone(self, zone);
    return copy;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_x forKey:@"x"];
    [coder encodeDouble:_y forKey:@"y"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithXComponent:[coder decodeDoubleForKey:@"x"] yComponent:[coder decodeDoubleForKey:@"y"]];
}

@end

@implementation VNCircle {
    VNPoint *_center;
    double _radius;
}

+ (VNCircle *)zeroCircle
{
    static VNCircle *zero;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        zero = [[VNCircle alloc] initWithCenter:[VNPoint zeroPoint] radius:0.0];
    });
    return zero;
}

- (instancetype)initWithCenter:(VNPoint *)center radius:(double)radius
{
    if ((self = [super init]) && center != nil) {
        _center = center;
        _radius = radius;
    }
    return self;
}

- (instancetype)initWithCenter:(VNPoint *)center diameter:(double)diameter
{
    return [self initWithCenter:center radius:diameter / 2.0];
}

- (BOOL)containsPoint:(VNPoint *)point
{
    if (point == nil || _center == nil) {
        return NO;
    }
    /* The boundary counts as inside, which is what the header says. */
    return [_center distanceToPoint:point] <= _radius;
}

- (BOOL)containsPoint:(VNPoint *)point inCircumferentialRingOfWidth:(double)ringWidth
{
    double distance;
    /* The header describes the ring as the band between the circles of radius-delta and
     * radius+delta, and names the argument the width of that band, so the half-width it compares
     * against is ringWidth/2. */
    if (point == nil || _center == nil) {
        return NO;
    }
    distance = [_center distanceToPoint:point];
    return distance >= _radius - ringWidth / 2.0 && distance <= _radius + ringWidth / 2.0;
}

- (VNPoint *)center
{
    return _center;
}

- (double)radius
{
    return _radius;
}

- (double)diameter
{
    return _radius * 2.0;
}

- (id)copyWithZone:(NSZone *)zone
{
    VNCircle *copy = charon_vision_clone(self, zone);
    return copy;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_center forKey:@"center"];
    [coder encodeDouble:_radius forKey:@"radius"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    VNPoint *center = [coder decodeObjectOfClass:[VNPoint class] forKey:@"center"];
    if (center == nil) {
        return nil;
    }
    return [self initWithCenter:center radius:[coder decodeDoubleForKey:@"radius"]];
}

@end

@implementation VNGeometryUtils

+ (VNCircle *)boundingCircleForPoints:(NSArray<VNPoint *> *)points error:(NSError **)error
{
    NSInteger count = (NSInteger)points.count;
    CharonVisionXY *buffer;
    CharonVisionCircle circle;
    VNCircle *answer;
    if (count == 0) {
        if (error) {
            *error = charon_vision_error(VNErrorInvalidArgument, @"there are no points to draw a circle around");
        }
        return nil;
    }
    buffer = malloc(sizeof(CharonVisionXY) * (size_t)count);
    if (buffer == NULL) {
        if (error) {
            *error = charon_vision_error(VNErrorOutOfMemory, @"the points would not fit in memory");
        }
        return nil;
    }
    for (NSInteger index = 0; index < count; index++) {
        VNPoint *point = points[(NSUInteger)index];
        if (point == nil) {
            free(buffer);
            if (error) {
                *error = charon_vision_error(VNErrorInvalidArgument, @"one of the points is not a VNPoint");
            }
            return nil;
        }
        buffer[index].x = point.x;
        buffer[index].y = point.y;
    }
    circle = charon_vision_bounding_circle(buffer, count);
    free(buffer);
    answer = [[VNCircle alloc] initWithCenter:[[VNPoint alloc] initWithX:circle.center.x y:circle.center.y]
                                       radius:circle.radius];
    return answer;
}

+ (VNCircle *)boundingCircleForSIMDPoints:(simd_float2 const *)points
                               pointCount:(NSInteger)pointCount
                                    error:(NSError **)error
{
    CharonVisionXY *buffer;
    CharonVisionCircle circle;
    VNCircle *answer;
    if (pointCount <= 0 || points == NULL) {
        if (error) {
            *error = charon_vision_error(VNErrorInvalidArgument, @"there are no points to draw a circle around");
        }
        return nil;
    }
    /* The caller's buffer is const, and the algorithm reorders the points it is given, so the
     * circle is found over a copy of them. */
    buffer = malloc(sizeof(CharonVisionXY) * (size_t)pointCount);
    if (buffer == NULL) {
        if (error) {
            *error = charon_vision_error(VNErrorOutOfMemory, @"the points would not fit in memory");
        }
        return nil;
    }
    for (NSInteger index = 0; index < pointCount; index++) {
        buffer[index].x = (double)points[index].x;
        buffer[index].y = (double)points[index].y;
    }
    circle = charon_vision_bounding_circle(buffer, pointCount);
    free(buffer);
    answer = [[VNCircle alloc] initWithCenter:[[VNPoint alloc] initWithX:circle.center.x y:circle.center.y]
                                       radius:circle.radius];
    return answer;
}

@end

@implementation VNStatefulRequest {
    CMTime _frameAnalysisSpacing;
}

/* A request that is handed the same buffer over and over and keeps what it learned. The spacing
 * says how often it is allowed to look: a buffer that arrives within one spacing of the last
 * analysis is skipped, and the request says so rather than guessing from a wall clock. */
- (instancetype)initWithFrameAnalysisSpacing:(CMTime)frameAnalysisSpacing
                           completionHandler:(VNRequestCompletionHandler)completionHandler
{
    if ((self = [super initWithCompletionHandler:completionHandler])) {
        _frameAnalysisSpacing = frameAnalysisSpacing;
    }
    return self;
}

/* The base class needs no frames before it can report: it carries the evidence a subclass collects
 * and has none of its own to wait for. A request that does need frames says so by overriding this,
 * which is the whole of the interface the header gives it. */
- (NSInteger)minimumLatencyFrameCount
{
    return 0;
}

- (CMTime)frameAnalysisSpacing
{
    return _frameAnalysisSpacing;
}

- (CMTime)requestFrameAnalysisSpacing
{
    return _frameAnalysisSpacing;
}

@end

@implementation VNVideoProcessorCadence

- (id)copyWithZone:(NSZone *)zone
{
    VNVideoProcessorCadence *copy = charon_vision_clone(self, zone);
    return copy;
}

@end

@implementation VNVideoProcessorFrameRateCadence {
    NSInteger _frameRate;
}

- (instancetype)initWithFrameRate:(NSInteger)frameRate
{
    if ((self = [super init])) {
        _frameRate = frameRate;
    }
    return self;
}

- (NSInteger)frameRate
{
    return _frameRate;
}

- (id)copyWithZone:(NSZone *)zone
{
    VNVideoProcessorFrameRateCadence *copy = charon_vision_clone(self, zone);
    return copy;
}

@end

@implementation VNVideoProcessorTimeIntervalCadence {
    CFTimeInterval _timeInterval;
}

- (instancetype)initWithTimeInterval:(CFTimeInterval)timeInterval
{
    if ((self = [super init])) {
        _timeInterval = timeInterval;
    }
    return self;
}

- (CFTimeInterval)timeInterval
{
    return _timeInterval;
}

- (id)copyWithZone:(NSZone *)zone
{
    VNVideoProcessorTimeIntervalCadence *copy = charon_vision_clone(self, zone);
    return copy;
}

@end

@implementation VNVideoProcessorRequestProcessingOptions {
    VNVideoProcessorCadence *_cadence;
}

/* The cadence of a request is its own to set, and the video processor reads it per request rather
 * than once for the whole pipeline, which is why it is on the options and not on the processor. */
- (VNVideoProcessorCadence *)cadence
{
    return _cadence;
}

- (void)setCadence:(VNVideoProcessorCadence *)cadence
{
    _cadence = [cadence copy];
}

- (id)copyWithZone:(NSZone *)zone
{
    VNVideoProcessorRequestProcessingOptions *copy = charon_vision_clone(self, zone);
    return copy;
}

@end
