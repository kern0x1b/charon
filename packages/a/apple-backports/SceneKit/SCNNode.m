#import "CharonSCN.h"

@implementation SCNNode
{
    NSMutableArray<SCNNode *> *_childNodes;
    NSMutableArray<SCNParticleSystem *> *_particleSystems;
    __weak SCNNode *_parentNode;
    SCNVector3 _boundingBoxMin;
    SCNVector3 _boundingBoxMax;
    BOOL _hasExplicitBoundingBox;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _childNodes = [NSMutableArray array];
        _particleSystems = [NSMutableArray array];
        _position = SCNVector3Make(0, 0, 0);
        _rotation = SCNVector4Make(0, 0, 1, 0);
        _orientation = SCNVector4Make(0, 0, 0, 1);
        _scale = SCNVector3Make(1, 1, 1);
        _opacity = 1;
        _categoryBitMask = 1;
        _castsShadow = YES;
    }
    return self;
}

+ (instancetype)node
{
    return [[self alloc] init];
}

@synthesize name = _name;
@synthesize light = _light;
@synthesize camera = _camera;
@synthesize geometry = _geometry;
@synthesize position = _position;
@synthesize rotation = _rotation;
@synthesize orientation = _orientation;
@synthesize scale = _scale;
@synthesize hidden = _hidden;
@synthesize opacity = _opacity;
@synthesize renderingOrder = _renderingOrder;
@synthesize castsShadow = _castsShadow;
@synthesize categoryBitMask = _categoryBitMask;
@synthesize movabilityHint = _movabilityHint;
@synthesize physicsField = _physicsField;

- (NSArray<SCNNode *> *)childNodes
{
    return [_childNodes copy];
}

- (void)addChildNode:(SCNNode *)child
{
    [child removeFromParentNode];
    [_childNodes addObject:child];
    child->_parentNode = self;
}

- (SCNNode *)parentNode
{
    return _parentNode;
}

- (void)removeFromParentNode
{
    if (_parentNode == nil) {
        return;
    }
    [_parentNode->_childNodes removeObject:self];
    _parentNode = nil;
}

- (SCNNode *)childNodeWithName:(NSString *)name recursively:(BOOL)recursively
{
    for (SCNNode *child in _childNodes) {
        if ([child.name isEqualToString:name]) {
            return child;
        }
        if (recursively) {
            SCNNode *found = [child childNodeWithName:name recursively:YES];
            if (found) {
                return found;
            }
        }
    }
    return nil;
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
        _light = [coder decodeObjectOfClass:[SCNLight class] forKey:@"light"];
        _camera = [coder decodeObjectOfClass:[SCNCamera class] forKey:@"camera"];
        _geometry = [coder decodeObjectOfClass:[SCNGeometry class] forKey:@"geometry"];
        _physicsField = [coder decodeObjectOfClass:[SCNPhysicsField class] forKey:@"physicsField"];
        _position = [coder containsValueForKey:@"position"] ? [CharonSCNCoding decodeVector3:coder forKey:@"position"] : SCNVector3Make(0, 0, 0);
        _rotation = [coder containsValueForKey:@"rotation"] ? [CharonSCNCoding decodeVector4:coder forKey:@"rotation"] : SCNVector4Make(0, 0, 1, 0);
        _orientation = [coder containsValueForKey:@"orientation"] ? [CharonSCNCoding decodeVector4:coder forKey:@"orientation"] : SCNVector4Make(0, 0, 0, 1);
        _scale = [coder containsValueForKey:@"scale"] ? [CharonSCNCoding decodeVector3:coder forKey:@"scale"] : SCNVector3Make(1, 1, 1);
        _hidden = [coder decodeBoolForKey:@"hidden"];
        _opacity = [coder containsValueForKey:@"opacity"] ? [coder decodeDoubleForKey:@"opacity"] : 1;
        _renderingOrder = [coder decodeIntegerForKey:@"renderingOrder"];
        _castsShadow = [coder containsValueForKey:@"castsShadow"] ? [coder decodeBoolForKey:@"castsShadow"] : YES;
        _categoryBitMask = [coder containsValueForKey:@"categoryBitMask"] ? [coder decodeIntegerForKey:@"categoryBitMask"] : 1;

        SCNParticleSystem *particleSystem = [coder decodeObjectOfClass:[SCNParticleSystem class] forKey:@"particleSystem"];
        if (particleSystem) {
            [_particleSystems addObject:particleSystem];
        }
        NSArray<SCNParticleSystem *> *particleSystems = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [SCNParticleSystem class], nil] forKey:@"particleSystems"];
        if (particleSystems.count) {
            [_particleSystems addObjectsFromArray:particleSystems];
        }

        NSArray<SCNNode *> *children = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [SCNNode class], nil] forKey:@"childNodes"];
        for (SCNNode *child in children) {
            [self addChildNode:child];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_light forKey:@"light"];
    [coder encodeObject:_camera forKey:@"camera"];
    [coder encodeObject:_geometry forKey:@"geometry"];
    [coder encodeObject:_physicsField forKey:@"physicsField"];
    [CharonSCNCoding encodeVector3:_position coder:coder forKey:@"position"];
    [CharonSCNCoding encodeVector4:_rotation coder:coder forKey:@"rotation"];
    [CharonSCNCoding encodeVector4:_orientation coder:coder forKey:@"orientation"];
    [CharonSCNCoding encodeVector3:_scale coder:coder forKey:@"scale"];
    [coder encodeBool:_hidden forKey:@"hidden"];
    [coder encodeDouble:_opacity forKey:@"opacity"];
    [coder encodeInteger:_renderingOrder forKey:@"renderingOrder"];
    [coder encodeBool:_castsShadow forKey:@"castsShadow"];
    [coder encodeInteger:_categoryBitMask forKey:@"categoryBitMask"];
    [coder encodeObject:[_particleSystems copy] forKey:@"particleSystems"];
    [coder encodeObject:[_childNodes copy] forKey:@"childNodes"];
}

- (id)copyWithZone:(NSZone *)zone
{
    SCNNode *copy = [[SCNNode allocWithZone:zone] init];
    copy->_name = [_name copy];
    copy->_light = _light;
    copy->_camera = _camera;
    copy->_geometry = _geometry;
    copy->_physicsField = _physicsField;
    copy->_position = _position;
    copy->_rotation = _rotation;
    copy->_orientation = _orientation;
    copy->_scale = _scale;
    copy->_hidden = _hidden;
    copy->_opacity = _opacity;
    copy->_renderingOrder = _renderingOrder;
    copy->_castsShadow = _castsShadow;
    copy->_categoryBitMask = _categoryBitMask;
    copy->_boundingBoxMin = _boundingBoxMin;
    copy->_boundingBoxMax = _boundingBoxMax;
    copy->_hasExplicitBoundingBox = _hasExplicitBoundingBox;
    for (SCNParticleSystem *system in _particleSystems) {
        [copy->_particleSystems addObject:system];
    }
    for (SCNNode *child in _childNodes) {
        [copy addChildNode:[child copy]];
    }
    return copy;
}

@end

@implementation SCNNode (SCNParticleSystemSupport)

- (void)addParticleSystem:(SCNParticleSystem *)system
{
    [self->_particleSystems addObject:system];
}

- (void)removeAllParticleSystems
{
    [self->_particleSystems removeAllObjects];
}

- (void)removeParticleSystem:(SCNParticleSystem *)system
{
    [self->_particleSystems removeObject:system];
}

- (NSArray<SCNParticleSystem *> *)particleSystems
{
    return self->_particleSystems.count ? [self->_particleSystems copy] : nil;
}

@end
