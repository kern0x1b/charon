#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@implementation MTLVertexAttributeDescriptor

- (id)copyWithZone:(NSZone *)zone
{
    MTLVertexAttributeDescriptor *d = [[MTLVertexAttributeDescriptor alloc] init];
    d.format = self.format;
    d.offset = self.offset;
    d.bufferIndex = self.bufferIndex;
    return d;
}

@end

@implementation MTLVertexBufferLayoutDescriptor

- (instancetype)init
{
    if ((self = [super init])) {
        self.stepFunction = MTLVertexStepFunctionPerVertex;
        self.stepRate = 1;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    MTLVertexBufferLayoutDescriptor *d = [[MTLVertexBufferLayoutDescriptor alloc] init];
    d.stride = self.stride;
    d.stepFunction = self.stepFunction;
    d.stepRate = self.stepRate;
    return d;
}

@end

@implementation MTLVertexAttributeDescriptorArray {
    NSMutableArray *_items;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        for (int i = 0; i < 31; i++)
            [_items addObject:[[MTLVertexAttributeDescriptor alloc] init]];
    }
    return self;
}

- (MTLVertexAttributeDescriptor *)objectAtIndexedSubscript:(NSUInteger)index
{
    return _items[index];
}

- (void)setObject:(MTLVertexAttributeDescriptor *)attributeDesc atIndexedSubscript:(NSUInteger)index
{
    _items[index] = [attributeDesc copy];
}

@end

@implementation MTLVertexBufferLayoutDescriptorArray {
    NSMutableArray *_items;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        for (int i = 0; i < 31; i++)
            [_items addObject:[[MTLVertexBufferLayoutDescriptor alloc] init]];
    }
    return self;
}

- (MTLVertexBufferLayoutDescriptor *)objectAtIndexedSubscript:(NSUInteger)index
{
    return _items[index];
}

- (void)setObject:(MTLVertexBufferLayoutDescriptor *)bufferDesc atIndexedSubscript:(NSUInteger)index
{
    _items[index] = [bufferDesc copy];
}

@end

@implementation MTLVertexDescriptor {
    MTLVertexAttributeDescriptorArray *_attributes;
    MTLVertexBufferLayoutDescriptorArray *_layouts;
}

+ (MTLVertexDescriptor *)vertexDescriptor
{
    return [[MTLVertexDescriptor alloc] init];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _attributes = [[MTLVertexAttributeDescriptorArray alloc] init];
        _layouts = [[MTLVertexBufferLayoutDescriptorArray alloc] init];
    }
    return self;
}

- (MTLVertexAttributeDescriptorArray *)attributes
{
    return _attributes;
}

- (MTLVertexBufferLayoutDescriptorArray *)layouts
{
    return _layouts;
}

- (void)reset
{
    _attributes = [[MTLVertexAttributeDescriptorArray alloc] init];
    _layouts = [[MTLVertexBufferLayoutDescriptorArray alloc] init];
}

- (id)copyWithZone:(NSZone *)zone
{
    MTLVertexDescriptor *d = [[MTLVertexDescriptor alloc] init];
    for (int i = 0; i < 31; i++) {
        d.attributes[i] = self.attributes[i];
        d.layouts[i] = self.layouts[i];
    }
    return d;
}

@end
