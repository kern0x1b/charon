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
    @synthesize transform = _transform;
- (instancetype)initWithName:(NSString *)name transform:(simd_float4x4)transform
{
    self = [super init];
    if (!self)
        return nil;
    _identifier = [[NSUUID alloc] init];
    _name = [name copy];
    _transform = transform;
    return self;
}

- (instancetype)initWithAnchor:(ARAnchor *)anchor
{
    // Copying an anchor gives a new identity at the same place: a new name, a new UUID, and the
    // transform it was at, which is what a caller duplicating an anchor expects it to mean.
    if (![anchor isKindOfClass:[ARAnchor class]])
        return nil;
    return [self initWithName:anchor.name transform:anchor.transform];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[self class] allocWithZone:zone];
}

/// The header declares an anchor secure-coding, and an anchor is a name, a pose and nothing else, so
/// the two are all there is to encode.
+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_identifier forKey:@"identifier"];
    // a matrix is a struct of vectors and `@encode` cannot describe one, so the sixteen floats go
    // across as the bytes they are
    [coder encodeBytes:&_transform length:sizeof _transform forKey:@"transform"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self)
        return nil;
    // The 6.1.3 release's own coder has no keyed `decodeValue:forKey:objCType:`, so the pose is
    // read back the way that release writes a structure: as the four columns of the matrix.
    _identifier = [coder decodeObjectOfClass:[NSUUID class] forKey:@"identifier"] ?: [NSUUID UUID];
    NSValue *packed = [coder decodeObjectOfClass:[NSValue class] forKey:@"transform"];
    if (packed)
        [packed getValue:&_transform];
    return self;
}


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

/// A plane is a quad, so its geometry is four corners and the six indices that join them.
enum { kPlaneQuadCorners = 4, kPlaneQuadTriangles = 6 };

@implementation ARPlaneGeometry
{
    simd_float3 *_vertices;
    simd_float2 *_textureCoordinates;
    int16_t *_triangleIndices;
    simd_float3 *_boundaryVertices;
}
    @synthesize vertices = _vertices;
    @synthesize textureCoordinates = _textureCoordinates;
    @synthesize triangleIndices = _triangleIndices;
    @synthesize boundaryVertices = _boundaryVertices;

    @synthesize vertexCount = _vertexCount;
    @synthesize textureCoordinateCount = _textureCoordinateCount;
    @synthesize triangleCount = _triangleCount;
    @synthesize boundaryVertexCount = _boundaryVertexCount;



/// The geometry of a plane is C buffers, not objects: the framework declares the vertices, the
/// texture coordinates and the triangle indices as pointers into memory a renderer reads in place,
/// and a caller walks them with the counts beside them. So the buffers are the storage, they are
/// filled from the plane the detector found, and they live as long as this object does.
- (instancetype)initWithPlaneValue:(CharonARValue *)value
{
    self = [super init];
    if (!self)
        return nil;
    CharonARPlane plane;
    if (![value getValue:&plane])
        return nil;

    // One plane is a quad, and a quad is what a plane detector's rectangle is: four corners, six
    // indices, and the four texture coordinates that go with the corners.
    _vertexCount = kPlaneQuadCorners;
    _textureCoordinateCount = kPlaneQuadCorners;
    _triangleCount = kPlaneQuadTriangles;
    _boundaryVertexCount = kPlaneQuadCorners;

    simd_float3 corners[kPlaneQuadCorners];
    simd_float2 coordinates[kPlaneQuadCorners] = {
        {0.0f, 0.0f}, {1.0f, 0.0f}, {0.0f, 1.0f}, {1.0f, 1.0f},
    };
    int16_t indices[kPlaneQuadTriangles] = {0, 2, 1, 1, 2, 3};
    // The detector gives a centre, a normal and a half-extent, and the quad's corners follow from an
    // orthonormal pair in the plane. The pair is built out of the normal by crossing it with the
    // world axis it is least parallel to, so the corners are in the plane for any normal at all.
    simd_float3 seed = fabsf(plane.normal.y) < 0.9f ? (simd_float3){0.0f, 1.0f, 0.0f}
                                                   : (simd_float3){1.0f, 0.0f, 0.0f};
    simd_float3 along = simd_normalize(simd_cross(plane.normal, seed));
    simd_float3 across = simd_normalize(simd_cross(plane.normal, along));
    for (size_t i = 0; i < kPlaneQuadCorners; i++) {
        float u = (i == 1 || i == 3) ? 1.0f : -1.0f;
        float v = (i >= 2) ? 1.0f : -1.0f;
        corners[i] = plane.center + along * (u * plane.extent.x) + across * (v * plane.extent.y);
    }

    _vertices = malloc(kPlaneQuadCorners * sizeof * _vertices);
    _textureCoordinates = malloc(kPlaneQuadCorners * sizeof * _textureCoordinates);
    _triangleIndices = malloc(kPlaneQuadTriangles * sizeof * _triangleIndices);
    _boundaryVertices = malloc(kPlaneQuadCorners * sizeof * _boundaryVertices);
    if (!_vertices || !_textureCoordinates || !_triangleIndices || !_boundaryVertices) {
        free(_vertices);
        free(_textureCoordinates);
        free(_triangleIndices);
        free(_boundaryVertices);
        return nil;
    }
    memcpy(_vertices, corners, sizeof corners);
    memcpy(_textureCoordinates, coordinates, sizeof coordinates);
    memcpy(_triangleIndices, indices, sizeof indices);
    memcpy(_boundaryVertices, corners, sizeof corners);
    return self;
}

- (void)dealloc
{
    free(_vertices);
    free(_textureCoordinates);
    free(_triangleIndices);
    free(_boundaryVertices);
}

- (const simd_float3 *)vertices { return _vertices; }
- (const simd_float2 *)textureCoordinates { return _textureCoordinates; }
- (const int16_t *)triangleIndices { return _triangleIndices; }
- (const simd_float3 *)boundaryVertices { return _boundaryVertices; }

@end

// `ARPlaneAnchor.geometry` is declared by the 11.3 headers and is implemented here for a runtime
// that predates them; a caller reaching it is by definition on a release new enough for the answer.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

@implementation ARPlaneAnchor
{
    ARPlaneAnchorAlignment _alignment;
    simd_float3 _center;
    simd_float3 _extent;
    ARPlaneGeometry *_geometry;
}
    @synthesize alignment = _alignment;
    @synthesize center = _center;



- (instancetype)initWithPlaneValue:(CharonARValue *)value
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
        CharonARValue *value = [[CharonARValue alloc] initWithBytes:&plane size:sizeof plane];
        _geometry = [[ARPlaneGeometry alloc] initWithPlaneValue:value];
    }
    return _geometry;
}

@end

#pragma clang diagnostic pop

@implementation ARPointCloud
{
    NSData *_points;
    NSUInteger _count;
}
    @synthesize count = _count;
    @synthesize points = _points;
    @synthesize identifiers = _identifiers;



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
    @synthesize type = _type;
    @synthesize distance = _distance;
    @synthesize localTransform = _localTransform;
    @synthesize worldTransform = _worldTransform;
    @synthesize anchor = _anchor;



- (instancetype)initWithHitValue:(CharonARValue *)value
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
    @synthesize origin = _origin;
    @synthesize direction = _direction;
    @synthesize target = _target;
    @synthesize targetAlignment = _targetAlignment;



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
    @synthesize worldTransform = _worldTransform;
    @synthesize target = _target;
    @synthesize targetAlignment = _targetAlignment;
    @synthesize anchor = _anchor;



- (instancetype)initWithHitValue:(CharonARValue *)value
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
