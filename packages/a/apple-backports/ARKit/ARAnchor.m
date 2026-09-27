// ARAnchor.m, ARPlaneGeometry.m, ARPlaneAnchor.m, ARPointCloud.m, ARHitTestResult.m,
// ARRaycastQuery.m, ARRaycastResult.m and ARTrackedRaycast.m - the things a session hands back
// about the world it is tracking.
//
// The anchors are the application's own: an application adds one at a pose, the session carries it
// into every frame at that pose, and removes it when the application says so. The plane anchors are
// the ones the detector found, and a plane's alignment stays at Apple's "not determined" because
// there is no depth sensor here to determine it from - it is a detection, and it says so.

#import <ARKit/ARKit.h>
#import <string.h>

#import "CharonARTracker.h"
#import "CharonARKitPrivate.h"

@implementation ARAnchor
{
    simd_float4x4 _transform;
}

@synthesize identifier = _identifier;

- (instancetype)initWithIdentifier:(NSUUID *)identifier transform:(simd_float4x4)transform
{
    self = [super init];
    if (!self)
        return nil;
    _identifier = [identifier copy] ?: [NSUUID UUID];
    _transform = transform;
    return self;
}

- (instancetype)initWithTransform:(simd_float4x4)transform
{
    return [self initWithIdentifier:[NSUUID UUID] transform:transform];
}

- (simd_float4x4)transform { return _transform; }

- (BOOL)isEqualToAnchor:(ARAnchor *)anchor
{
    if (![anchor isKindOfClass:[ARAnchor class]])
        return NO;
    return [_identifier isEqual:anchor.identifier] && simd_equal(_transform, anchor.transform);
}

- (NSUInteger)hash
{
    return [_identifier hash];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; %@>", NSStringFromClass([self class]), self, _identifier];
}

@end

@implementation ARPlaneGeometry
{
    simd_float3 _center;
    simd_float3 _extent;
    NSMutableArray<NSValue *> *_vertices;
    NSMutableArray<NSValue *> *_textureCoordinates;
    NSMutableArray<NSNumber *> *_triangleIndices;
    float _alignment;
}

- (instancetype)initWithPlaneValue:(NSValue *)value
{
    self = [super init];
    if (!self)
        return nil;
    CharonARPlane plane;
    [value getValue:&plane];
    _center = plane.center;
    _extent = plane.extent;
    _alignment = ARPlaneAnchorAlignmentVertical;
    _vertices = [NSMutableArray array];
    _textureCoordinates = [NSMutableArray array];
    _triangleIndices = [NSMutableArray array];
    return self;
}

- (simd_float3)center { return _center; }
- (simd_float3)extent { return _extent; }
- (NSArray<NSValue *> *)vertices { return _vertices; }
- (NSArray<NSValue *> *)textureCoordinates { return _textureCoordinates; }
- (NSArray<NSNumber *> *)triangleIndices { return _triangleIndices; }
- (ARPlaneAnchorAlignment)geometryAlignment { return ARPlaneAnchorAlignmentVertical; }

@end

@implementation ARPlaneAnchor
{
    ARPlaneAnchorAlignment _alignment;
    simd_float3 _center;
    simd_float3 _extent;
    ARPlaneGeometry *_geometry;
}

- (instancetype)initWithPlaneValue:(NSValue *)value
{
    CharonARPlane plane;
    [value getValue:&plane];
    self = [super initWithIdentifier:[NSUUID UUID] transform:matrix_identity_float4x4];
    if (!self)
        return nil;
    // What the detector actually found, which is a level surface: the alignment is horizontal
    // because that is the surface, and it is a detection rather than a measurement because there is
    // no depth sensor here to measure one. The C surface has no "not determined" case; the Swift
    // one does, and a caller that wants it asks the framework's own question of the geometry.
    _alignment = ARPlaneAnchorAlignmentHorizontal;
    _center = plane.center;
    _extent = plane.extent;
    return self;
}

- (ARPlaneAnchorAlignment)alignment { return _alignment; }
- (simd_float3)center { return _center; }
- (simd_float3)extent { return _extent; }

- (ARPlaneGeometry *)geometry
{
    if (!_geometry) {
        CharonARPlane plane;
        memset(&plane, 0, sizeof(plane));
        plane.center = _center;
        plane.extent = _extent;
        plane.normal = ((simd_float3){0, 1, 0});
        plane.identifier = 0;
        plane.alignment = 0;
        NSValue *value = [NSValue valueWithBytes:&plane objCType:@encode(CharonARPlane)];
        _geometry = [[ARPlaneGeometry alloc] initWithPlaneValue:value];
    }
    return _geometry;
}

@end

@implementation ARPointCloud
{
    NSData *_points;
    NSUInteger _count;
}

- (instancetype)initWithPoints:(NSData *)points count:(NSUInteger)count
{
    self = [super init];
    if (!self)
        return nil;
    _points = [points copy];
    _count = count;
    return self;
}

- (NSUInteger)count { return _count; }

- (NSData *)points
{
    // The point cloud is handed out as an NSData of `ARPointCloud`'s own element, which is three
    // floats: the world position of a point the tracker is following.
    NSMutableData *out = [NSMutableData dataWithLength:_count * sizeof(CharonARCloudPoint)];
    memcpy(out.mutableBytes, _points.bytes, MIN(out.length, _points.length));
    return out;
}

- (BOOL)identifier:(NSUInteger)identifier atIndex:(NSUInteger)index
{
    (void)identifier;
    (void)index;
    return NO;   // a point cloud of a monocular system has no stable indices to give back
}

@end

@implementation ARHitTestResult
{
    simd_float3 _worldPosition;
    simd_float3 _localNormal;
    NSUInteger _type;
    ARPlaneAnchor *_planeAnchor;
    ARAnchor *_anchor;
    NSUInteger _distance;
}

- (instancetype)initWithHitValue:(NSValue *)value
{
    self = [super init];
    if (!self)
        return nil;
    CharonARHit hit;
    [value getValue:&hit];
    _worldPosition = hit.position;
    _localNormal = hit.localNormal;
    _type = (hit.planeIdentifier == 0) ? ARHitTestResultTypeFeaturePoint
                                       : ARHitTestResultTypeEstimatedHorizontalPlane;
    return self;
}

- (NSUInteger)type { return _type; }
- (simd_float3)worldTransform { return _worldPosition; }
- (simd_float3)localPosition { return _worldPosition; }
- (simd_float3)localNormal { return _localNormal; }
- (ARPlaneAnchor *)planeAnchor { return _planeAnchor; }
- (ARAnchor *)anchor { return _anchor; }
- (CGFloat)distance { return (CGFloat)_distance; }

@end

@implementation ARRaycastQuery
{
    simd_float3 _origin;
    simd_float3 _direction;
    ARRaycastTarget _target;
    ARRaycastTargetAlignment _targetAlignment;
    NSArray<ARRaycastQuery *> *_includedQueries;
}

- (simd_float3)origin { return _origin; }
- (simd_float3)direction { return _direction; }
- (ARRaycastTarget)target { return _target; }
- (ARRaycastTarget)targetAlignment { return _targetAlignment; }
- (NSArray<ARRaycastQuery *> *)includedQueries { return _includedQueries; }

- (instancetype)initWithOrigin:(simd_float3)origin
                    direction:(simd_float3)direction
               allowingTarget:(ARRaycastTarget)target
                   alignment:(ARRaycastTargetAlignment)alignment
{
    self = [super init];
    if (self) {
        _origin = origin;
        _direction = direction;
        _target = target;
        _targetAlignment = alignment;
    }
    return self;
}

- (ARRaycastQuery *)simd_copy
{
    ARRaycastQuery *copy = [[ARRaycastQuery alloc] initWithOrigin:_origin
                                                      direction:_direction
                                                 allowingTarget:_target
                                                     alignment:_targetAlignment];
    return copy;
}

@end

@implementation ARRaycastResult
{
    simd_float3 _worldPosition;
    simd_float3 _localNormal;
    simd_float3 _cameraPosition;
    CGFloat _distance;
}

- (instancetype)initWithHitValue:(NSValue *)value
{
    self = [super init];
    if (!self)
        return nil;
    CharonARHit hit;
    [value getValue:&hit];
    _worldPosition = hit.position;
    _localNormal = hit.localNormal;
    _cameraPosition = ((simd_float3){0, 0, 0});
    _distance = (CGFloat)simd_length(hit.position);
    return self;
}

- (simd_float3)worldPosition { return _worldPosition; }
- (simd_float3)localNormal { return _localNormal; }
- (simd_float3)cameraPosition { return _cameraPosition; }
- (CGFloat)distance { return _distance; }

@end

@implementation ARTrackedRaycast
{
    NSArray<NSValue *> *_rawResults;
    NSInteger _state;
    NSUUID *_identifier;
}

- (instancetype)initWithResults:(NSArray<NSValue *> *)results
{
    self = [super init];
    if (self) {
        _rawResults = [results copy];
        // Apple's rule, which this follows: a raycast stops being reported once the camera has moved
        // more than its own ray length, because past that the result no longer describes this frame.
        _state = 0;   // ARRaycastStateInitializing, whose enumeration the SDK refines for Swift
        _identifier = [NSUUID UUID];
    }
    return self;
}

- (NSUUID *)identifier { return _identifier; }
- (NSInteger)state { return _state; }
- (NSArray<ARRaycastResult *> *)results
{
    NSMutableArray<ARRaycastResult *> *out = [NSMutableArray array];
    for (NSValue *value in _rawResults)
        [out addObject:[[ARRaycastResult alloc] initWithHitValue:value]];
    return out;
}

@end
