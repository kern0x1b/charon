#import <ModelIO/ModelIO.h>
#import <simd/simd.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@interface MDLObjectContainer ()
// The object this container is the children of, held without retaining it: an object owns its own
// children, so a container that retained its owner and its owner's children kept both alive.
@property (nonatomic, assign) MDLObject *charon_owner;
@end

// An object is a named node with a transform, a set of components keyed by the protocol each of them
// answers to, and children. Everything the port places in a scene - a mesh, a voxel array, a light, a
// camera - is one of these. iOS 6 has no ModelIO at all, so the whole of it is the port's own.

@implementation MDLObject {
    NSMutableArray<id<MDLComponent>> *_components;
    __unsafe_unretained MDLObject *_parent;
    MDLObject *_instance;
    id<MDLObjectContainerComponent> _children;
    id<MDLTransformComponent> _transform;
    BOOL _hidden;
}

@synthesize name = _name;

- (instancetype)init
{
    if ((self = [super init])) {
        _components = [[NSMutableArray alloc] init];
        _name = @"";
    }
    return self;
}

- (void)dealloc
{
    [_components release];
    [_name release];
    [_instance release];
    [_children release];
    [_transform release];
    [super dealloc];
}

- (NSArray<id<MDLComponent>> *)components
{
    return [[_components copy] autorelease];
}

- (void)setComponent:(id<MDLComponent>)component forProtocol:(Protocol *)protocol
{
    for (NSUInteger k = 0; k < _components.count; k++)
        if ([_components[k] conformsToProtocol:protocol]) {
            [_components removeObjectAtIndex:k];
            break;
        }
    if (component)
        [_components addObject:component];
}

- (id<MDLComponent>)componentConformingToProtocol:(Protocol *)protocol
{
    for (id<MDLComponent> component in _components)
        if ([component conformsToProtocol:protocol])
            return component;
    return nil;
}

- (id<MDLComponent>)objectForKeyedSubscript:(Protocol *)key
{
    return [self componentConformingToProtocol:key];
}

- (void)setObject:(id<MDLComponent>)obj forKeyedSubscript:(Protocol *)key
{
    [self setComponent:obj forProtocol:key];
}

- (MDLObject *)parent
{
    return _parent;
}

- (void)setParent:(MDLObject *)parent
{
    _parent = parent;
}

- (MDLObject *)instance
{
    return _instance;
}

- (void)setInstance:(MDLObject *)instance
{
    if (_instance != instance) {
        [_instance release];
        _instance = [instance retain];
    }
}

- (id<MDLTransformComponent>)transform
{
    return _transform;
}

- (void)setTransform:(id<MDLTransformComponent>)transform
{
    if (_transform != transform) {
        [_transform release];
        _transform = [transform retain];
    }
}

- (id<MDLObjectContainerComponent>)children
{
    if (!_children) {
        MDLObjectContainer *container = [[MDLObjectContainer alloc] init];
        container.charon_owner = self;
        _children = container;
    }
    return _children;
}

- (void)setChildren:(id<MDLObjectContainerComponent>)children
{
    if (_children != children) {
        [_children release];
        _children = [children retain];
    }
    // A container that is not the object's own one still makes its objects children of this object.
    if ([children isKindOfClass:[MDLObjectContainer class]])
        [(MDLObjectContainer *)children setCharon_owner:self];
    for (MDLObject *child in [_children objects])
        if (child.parent != self)
            [child setParent:self];
}

- (BOOL)hidden
{
    return _hidden;
}

- (void)setHidden:(BOOL)hidden
{
    _hidden = hidden;
}

- (void)addChild:(MDLObject *)child
{
    if (!child)
        return;
    [[self children] addObject:child];
    [child setParent:self];
}

- (NSString *)path
{
    if (!_parent)
        return [NSString stringWithFormat:@"/%@", self.name];
    return [_parent.path stringByAppendingFormat:@"/%@", self.name];
}

- (MDLObject *)objectAtPath:(NSString *)path
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [path componentsSeparatedByString:@"/"])
        if (part.length)
            [parts addObject:part];
    if (!parts.count)
        return self;
    if (![parts[0] isEqualToString:self.name])
        return nil;
    MDLObject *at = self;
    for (NSUInteger k = 1; k < parts.count; k++) {
        MDLObject *next = nil;
        for (MDLObject *child in at.children.objects)
            if ([child.name isEqualToString:parts[k]]) {
                next = child;
                break;
            }
        if (!next)
            return nil;
        at = next;
    }
    return at;
}

- (void)enumerateChildObjectsOfClass:(Class)objectClass
                                root:(MDLObject *)root
                          usingBlock:(void (^)(MDLObject *, BOOL *))block
                         stopPointer:(BOOL *)stopPointer
{
    for (MDLObject *child in root.children.objects) {
        if (stopPointer && *stopPointer)
            return;
        if (!objectClass || [child isKindOfClass:objectClass])
            block(child, stopPointer);
        if (stopPointer && *stopPointer)
            return;
        [self enumerateChildObjectsOfClass:objectClass root:child usingBlock:block stopPointer:stopPointer];
    }
}

// The box of a node is the union of the boxes of its children, each brought into this node's own
// space by the transform of the whole chain above it. A node with no children has no box of its own.
- (MDLAxisAlignedBoundingBox)boundingBoxAtTime:(NSTimeInterval)time
{
    MDLAxisAlignedBoundingBox result = {{INFINITY, INFINITY, INFINITY}, {-INFINITY, -INFINITY, -INFINITY}};
    for (MDLObject *child in self.children.objects) {
        if (child.hidden)
            continue;
        matrix_float4x4 global = [MDLTransform globalTransformWithObject:child atTime:time];
        MDLAxisAlignedBoundingBox box = [child boundingBoxAtTime:time];
        if (box.minBounds[0] > box.maxBounds[0])
            continue;
        for (int corner = 0; corner < 8; corner++) {
            vector_float3 point = {(corner & 1) ? box.maxBounds.x : box.minBounds.x, (corner & 2) ? box.maxBounds.y : box.minBounds.y,
                                   (corner & 4) ? box.maxBounds.z : box.minBounds.z};
            vector_float4 transformed = simd_mul(global, (vector_float4){point.x, point.y, point.z, 1});
            result.minBounds = simd_min(result.minBounds, transformed.xyz);
            result.maxBounds = simd_max(result.maxBounds, transformed.xyz);
        }
    }
    if (result.minBounds[0] > result.maxBounds[0]) {
        result.minBounds = (vector_float3){0, 0, 0};
        result.maxBounds = (vector_float3){0, 0, 0};
    }
    return result;
}

@end

@implementation MDLObjectContainer {
    NSMutableArray<MDLObject *> *_objects;
}

- (instancetype)init
{
    if ((self = [super init]))
        _objects = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [_objects release];
    [super dealloc];
}

- (void)addObject:(MDLObject *)object
{
    if (!object || [_objects containsObject:object])
        return;
    [_objects addObject:object];
    // An object put in a container is a child of the object that container belongs to.
    if (self.charon_owner && object.parent != self.charon_owner)
        [object setParent:self.charon_owner];
}

- (void)removeObject:(MDLObject *)object
{
    if ([_objects containsObject:object]) {
        [_objects removeObject:object];
        if (object.parent == self.charon_owner)
            [object setParent:nil];
    }
}

- (MDLObject *)objectAtIndexedSubscript:(NSUInteger)index
{
    return index < _objects.count ? _objects[index] : nil;
}

- (NSUInteger)count
{
    return _objects.count;
}

- (NSArray<MDLObject *> *)objects
{
    return [[_objects copy] autorelease];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)length
{
    return [_objects countByEnumeratingWithState:state objects:buffer count:length];
}

@end
