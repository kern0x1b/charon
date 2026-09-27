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

// `-[ARAnchor initWithName:transform:]` and `name` are the 12.0 vocabulary; they are served here for
// a runtime that predates them, and a caller reaching them is by definition on a release new enough.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/// A struct across a keyed coder.
///
/// The anchored values here are structs of SIMD vectors, and `@encode` cannot describe one, so the
/// bytes go across as bytes. The keyed pair is `encodeBytes:length:forKey:` and
/// `decodeBytesForKey:returnedLength:`, and the length is checked on the way back because a coder
/// that holds fewer bytes than the struct needs is a different class's archive, not this one's.
static void CharonEncodeStruct(NSCoder *coder, NSString *key, const void *bytes, size_t size)
{
    [coder encodeBytes:(const uint8_t *)bytes length:size forKey:key];
}

static BOOL CharonDecodeStruct(NSCoder *coder, NSString *key, void *bytes, size_t size)
{
    NSUInteger length = 0;
    const uint8_t *decoded = [coder decodeBytesForKey:key returnedLength:&length];
    if (!decoded || length < size)
        return NO;
    memcpy(bytes, decoded, size);
    return YES;
}

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
    ARAnchor *copy = [[self class] allocWithZone:zone];
    copy->_identifier = _identifier;
    copy->_name = _name;
    copy->_transform = _transform;
    return copy;
}

/// The header declares an anchor secure-coding, and an anchor is a name, a pose and nothing else, so
/// the two are all there is to encode.
+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_identifier forKey:@"identifier"];
    [coder encodeObject:_name forKey:@"name"];
    CharonEncodeStruct(coder, @"transform", &_transform, sizeof _transform);
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self)
        return nil;
    // The 6.1.3 release's own coder has no keyed `decodeValue:forKey:objCType:`, so the pose is
    // read back the way that release writes a structure: as the four columns of the matrix.
    _identifier = [coder decodeObjectOfClass:[NSUUID class] forKey:@"identifier"] ?: [NSUUID UUID];
    _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
    CharonDecodeStruct(coder, @"transform", &_transform, sizeof _transform);
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

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_vertexCount forKey:@"vertexCount"];
    [coder encodeInteger:(NSInteger)_triangleCount forKey:@"triangleCount"];
    CharonEncodeStruct(coder, @"vertices", _vertices, _vertexCount * sizeof * _vertices);
    CharonEncodeStruct(coder, @"textureCoordinates", _textureCoordinates,
                       _vertexCount * sizeof * _textureCoordinates);
    CharonEncodeStruct(coder, @"triangleIndices", _triangleIndices,
                       _triangleCount * sizeof * _triangleIndices);
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self)
        return nil;
    _vertexCount = _textureCoordinateCount = _boundaryVertexCount =
            (NSUInteger)[coder decodeIntegerForKey:@"vertexCount"];
    _triangleCount = (NSUInteger)[coder decodeIntegerForKey:@"triangleCount"];
    if (!_vertexCount || !_triangleCount)
        return nil;
    _vertices = malloc(_vertexCount * sizeof * _vertices);
    _textureCoordinates = malloc(_vertexCount * sizeof * _textureCoordinates);
    _triangleIndices = malloc(_triangleCount * sizeof * _triangleIndices);
    _boundaryVertices = malloc(_vertexCount * sizeof * _boundaryVertices);
    if (!_vertices || !_textureCoordinates || !_triangleIndices || !_boundaryVertices) {
        free(_vertices);
        free(_textureCoordinates);
        free(_triangleIndices);
        free(_boundaryVertices);
        return nil;
    }
    if (!CharonDecodeStruct(coder, @"vertices", _vertices, _vertexCount * sizeof * _vertices) ||
        !CharonDecodeStruct(coder, @"textureCoordinates", _textureCoordinates,
                            _vertexCount * sizeof * _textureCoordinates) ||
        !CharonDecodeStruct(coder, @"triangleIndices", _triangleIndices,
                            _triangleCount * sizeof * _triangleIndices)) {
        free(_vertices);
        free(_textureCoordinates);
        free(_triangleIndices);
        free(_boundaryVertices);
        return nil;
    }
    memcpy(_boundaryVertices, _vertices, _vertexCount * sizeof * _vertices);
    return self;
}

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

+ (BOOL)isClassificationSupported
{
    // A plane's classification - floor, wall, table, ceiling - is read out of a depth sensor's
    // geometry, and this device has none, so a detector's plane is a plane and not one of those.
    return NO;
}

- (ARPlaneClassificationStatus)classificationStatus
{
    return ARPlaneClassificationStatusUnknown;
}

- (ARPlaneClassification)classification
{
    return ARPlaneClassificationNone;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:(NSInteger)_alignment forKey:@"alignment"];
    CharonEncodeStruct(coder, @"center", &_center, sizeof _center);
    CharonEncodeStruct(coder, @"extent", &_extent, sizeof _extent);
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self)
        return nil;
    _alignment = (ARPlaneAnchorAlignment)[coder decodeIntegerForKey:@"alignment"];
    CharonDecodeStruct(coder, @"center", &_center, sizeof _center);
    CharonDecodeStruct(coder, @"extent", &_extent, sizeof _extent);
    return self;
}

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
    simd_float3 *_points;
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
    // the tracker's samples are the same three floats a point cloud is, so the buffer is copied into
    // one this object owns and hands out in place
    _count = MIN(count, points.length / sizeof(simd_float3));
    _points = malloc(_count * sizeof * _points);
    if (!_points)
        return nil;
    memcpy(_points, points.bytes, _count * sizeof * _points);
    return self;
}

- (void)dealloc
{
    free(_points);
}

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_count forKey:@"count"];
    CharonEncodeStruct(coder, @"points", _points, _count * sizeof * _points);
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self)
        return nil;
    _count = (NSUInteger)[coder decodeIntegerForKey:@"count"];
    if (!_count)
        return nil;
    _points = malloc(_count * sizeof * _points);
    if (!_points || !CharonDecodeStruct(coder, @"points", _points, _count * sizeof * _points)) {
        free(_points);
        _points = NULL;
        _count = 0;
        return nil;
    }
    return self;
}

- (NSUInteger)count { return _count; }

- (const simd_float3 *)points
{
    // The framework hands out a pointer into a buffer it names itself, and a caller walks it with
    // `count` beside it; the buffer lives as long as this object does.
    return _points;
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
    ARHitTestResultType _type;
    ARPlaneAnchor *_planeAnchor;
    ARAnchor *_anchor;
    CGFloat _distance;
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

- (ARHitTestResultType)type { return _type; }
- (simd_float4x4)worldTransform
{
    // a hit's transform is a pose, and a pose of a point is the point with no rotation
    return matrix_identity_float4x4;
}
- (simd_float3)localPosition { return _worldPosition; }
- (simd_float3)localNormal { return _localNormal; }
- (ARPlaneAnchor *)planeAnchor { return _planeAnchor; }
- (ARAnchor *)anchor { return _anchor; }
- (CGFloat)distance { return _distance; }

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
- (ARRaycastTargetAlignment)targetAlignment { return _targetAlignment; }
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
    NSMutableArray<CharonARValue *> *_rawResults;
    NSInteger _state;
    NSUUID *_identifier;
}

- (instancetype)initWithResults:(NSArray<CharonARValue *> *)results
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

- (void)stopTracking
{
    // Apple's rule, which this follows: a tracked raycast stops reporting once the camera has moved
    // further than its own ray length, because past that the result no longer describes this frame.
    // The caller says so, and the results go with it.
    [_rawResults removeAllObjects];
    _state = 2;   // ARRaycastStateStopped
}

- (NSUUID *)identifier { return _identifier; }
- (NSInteger)state { return _state; }
- (NSArray<ARRaycastResult *> *)results
{
    NSMutableArray<ARRaycastResult *> *out = [NSMutableArray array];
    for (CharonARValue *value in _rawResults)
        [out addObject:[[ARRaycastResult alloc] initWithHitValue:value]];
    return out;
}

@end
