#import "CharonSCN.h"

@implementation SCNGeometry
{
    SCNVector3 _boundingBoxMin;
    SCNVector3 _boundingBoxMax;
    BOOL _hasExplicitBoundingBox;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _materials = @[];
    }
    return self;
}

+ (instancetype)geometry
{
    return [[self alloc] init];
}

@synthesize name = _name;
@synthesize materials = _materials;

- (SCNMaterial *)firstMaterial
{
    return _materials.firstObject;
}

- (void)setFirstMaterial:(SCNMaterial *)firstMaterial
{
    _materials = firstMaterial ? @[firstMaterial] : @[];
}

- (NSArray<SCNGeometrySource *> *)geometrySources
{
    return @[];
}

- (NSArray<SCNGeometryElement *> *)geometryElements
{
    return @[];
}

#pragma mark - SCNBoundingVolume

- (BOOL)getBoundingBoxMin:(SCNVector3 *)min max:(SCNVector3 *)max
{
    if (!_hasExplicitBoundingBox) {
        return NO;
    }
    if (min) {
        *min = _boundingBoxMin;
    }
    if (max) {
        *max = _boundingBoxMax;
    }
    return YES;
}

- (void)setBoundingBoxMin:(SCNVector3 *)min max:(SCNVector3 *)max
{
    if (min == NULL || max == NULL) {
        _hasExplicitBoundingBox = NO;
        return;
    }
    _boundingBoxMin = *min;
    _boundingBoxMax = *max;
    _hasExplicitBoundingBox = YES;
}

- (BOOL)getBoundingSphereCenter:(SCNVector3 *)center radius:(CGFloat *)radius
{
    if (!_hasExplicitBoundingBox) {
        return NO;
    }
    SCNVector3 mid = SCNVector3Make((_boundingBoxMin.x + _boundingBoxMax.x) / 2,
                                     (_boundingBoxMin.y + _boundingBoxMax.y) / 2,
                                     (_boundingBoxMin.z + _boundingBoxMax.z) / 2);
    float dx = _boundingBoxMax.x - mid.x, dy = _boundingBoxMax.y - mid.y, dz = _boundingBoxMax.z - mid.z;
    if (center) {
        *center = mid;
    }
    if (radius) {
        *radius = sqrt(dx * dx + dy * dy + dz * dz);
    }
    return YES;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        NSArray<SCNMaterial *> *materials = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [SCNMaterial class], nil] forKey:@"materials"];
        _materials = materials ?: @[];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_materials forKey:@"materials"];
}

- (id)copyWithZone:(NSZone *)zone
{
    SCNGeometry *copy = [[[self class] allocWithZone:zone] init];
    copy->_name = [_name copy];
    copy->_materials = [_materials copy];
    copy->_boundingBoxMin = _boundingBoxMin;
    copy->_boundingBoxMax = _boundingBoxMax;
    copy->_hasExplicitBoundingBox = _hasExplicitBoundingBox;
    return copy;
}

@end
