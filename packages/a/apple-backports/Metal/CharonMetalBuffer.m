#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation CharonMetalBuffer {
    void *_bytes;
    NSUInteger _length;
    __strong CharonMetalHeap *_heap;
    NSUInteger _heapOffset;
}

@synthesize label;

- (instancetype)initWithLength:(NSUInteger)length bytes:(const void *)bytes
{
    if ((self = [super init])) {
        _length = length;
        _bytes = calloc(1, length ? length : 1);
        if (bytes)
            memcpy(_bytes, bytes, length);
    }
    return self;
}

// A buffer of a heap is a view into the heap's allocation: its bytes are the heap's, the heap is
// held for as long as the view is, and the heap frees the bytes when the last view is gone.
- (instancetype)initWithHeap:(CharonMetalHeap *)heap offset:(NSUInteger)offset length:(NSUInteger)length
{
    if ((self = [super init])) {
        _heap = heap;
        _heapOffset = offset;
        _length = length;
        _bytes = (uint8_t *)[heap charonBytesAtOffset:offset];
    }
    return self;
}

// MTLResource's own properties, answered as the SDK declares them: the heap the resource was created
// from, nil when it was not created from one, and the offset inside it.
- (id<MTLHeap>)heap
{
    return _heap;
}

- (NSUInteger)heapOffset
{
    return _heapOffset;
}

- (void)dealloc
{
    if (!_heap)
        free(_bytes);
}

- (void *)bytes
{
    return _bytes;
}

- (void *)contents
{
    return _bytes;
}

- (NSUInteger)length
{
    return _length;
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

- (MTLResourceOptions)resourceOptions
{
    return MTLResourceStorageModeShared;
}

- (MTLStorageMode)storageMode
{
    return MTLStorageModeShared;
}

- (MTLCPUCacheMode)cpuCacheMode
{
    return MTLCPUCacheModeDefaultCache;
}

- (void)didModifyRange:(NSRange)range
{
}

- (BOOL)setPurgeableState:(MTLPurgeableState)state
{
    return NO;
}

@end
