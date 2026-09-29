#import "MTLTypeReflectionInternal.h"

// The 11.0 half of the reflection classes: a pipeline buffer descriptor and the array of them.
//
// MTLPipeline.h places both at 11.0, and they are the two that describe how a stage's buffers are
// BOUND rather than what they are - a mutability, and a place to keep a descriptor per index.
//
// What the plist carries, once more, decides the members. It writes a function's arguments and nothing
// about a pipeline's bindings, so a buffer descriptor here is NOT built from the file: the mutability
// is MTLMutabilityDefault - the enumeration's own zero and what a descriptor the port did not author
// means - and the array is empty for the same reason the binding lists are empty in MTLReflection8.m,
// which is the documented absence and not a fabricated binding.

@implementation MTLPipelineBufferDescriptor

{
    MTLMutability _mutability;
}

// The mutability, and the enum's own default for a descriptor this port did not author: the plist
// carries no bindings, so there is nothing to say a buffer is mutable or immutable, and
// MTLMutabilityDefault is the enumeration's zero (MTLPipeline.h:20).
- (instancetype)init
{
    if ((self = [super init]))
        _mutability = MTLMutabilityDefault;
    return self;
}

- (MTLMutability)mutability
{
    return _mutability;
}

- (void)setMutability:(MTLMutability)mutability
{
    _mutability = mutability;
}

// The protocol is <NSCopying> and the copy is the descriptor with the same mutability - a copy that
// dropped it would not be a copy of anything the caller can use.
- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    MTLPipelineBufferDescriptor *copy = [[[self class] alloc] init];
    copy.mutability = _mutability;
    return copy;
}

@end

@implementation MTLPipelineBufferDescriptorArray

{
    NSMutableDictionary *_descriptors;
}

- (instancetype)init
{
    if ((self = [super init]))
        _descriptors = [NSMutableDictionary dictionary];
    return self;
}

// Both subscript forms read and write the array, and the array starts EMPTY for the reason above: the
// plist carries no bindings, so there is no descriptor for any index. A caller that sets one gets it
// back, which is what the header's two methods promise. The storage is a DICTIONARY keyed by index, not
// a padded array: padding an NSMutableArray fills the gaps with NSNull, and a gap that answers a
// non-nil object is an entry nobody set. nil CLEARS, which is what the header's nullable set says.
- (MTLPipelineBufferDescriptor *)objectAtIndexedSubscript:(NSUInteger)bufferIndex
{
    return _descriptors[@(bufferIndex)];
}

- (void)setObject:(MTLPipelineBufferDescriptor *)buffer atIndexedSubscript:(NSUInteger)bufferIndex
{
    if (!buffer)
        [_descriptors removeObjectForKey:@(bufferIndex)];   // nil is the header's own nullable: it CLEARS
    else
        _descriptors[@(bufferIndex)] = buffer;
}

@end
