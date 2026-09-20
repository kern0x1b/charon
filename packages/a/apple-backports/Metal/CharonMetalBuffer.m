#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation CharonMetalBuffer {
    void *_bytes;
    NSUInteger _length;
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

- (void)dealloc
{
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
