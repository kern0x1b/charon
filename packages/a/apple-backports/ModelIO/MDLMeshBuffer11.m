#import <ModelIO/ModelIO.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// A mesh buffer is the memory one attribute or one index range of a mesh lives in. The buffers here
// are backed by an NSMutableData, which is what the port's own allocator hands out and what every
// mesh the port builds or reads ends up holding: a real addressable range of the length the mesh says
// it has, copyable, and mappable.

@implementation MDLMeshBufferZoneDefault {
    NSUInteger _capacity;
    id<MDLMeshBufferAllocator> _allocator;
}

@synthesize capacity = _capacity;
@synthesize allocator = _allocator;

- (void)charon_setCapacity:(NSUInteger)capacity allocator:(id<MDLMeshBufferAllocator>)allocator
{
    _capacity = capacity;
    if (_allocator != allocator) {
        _allocator = allocator;
    }
}

- (void)dealloc
{
}

@end
