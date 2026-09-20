#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation CharonMetalQueue

@synthesize label;

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

- (id<MTLCommandBuffer>)commandBuffer
{
    return (id<MTLCommandBuffer>)[[CharonMetalCommandBuffer alloc] init];
}

- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences
{
    return [self commandBuffer];
}

@end

@implementation CharonMetalCommandBuffer {
    id<MTLDrawable> _drawable;
    NSMutableArray *_completed;
    MTLCommandBufferStatus _status;
    BOOL _committed;
}

@synthesize label;

- (instancetype)init
{
    if ((self = [super init])) {
        _completed = [NSMutableArray array];
        _status = MTLCommandBufferStatusNotEnqueued;
    }
    return self;
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

- (id<MTLCommandQueue>)commandQueue
{
    return nil;
}

- (MTLCommandBufferStatus)status
{
    return _status;
}

- (NSError *)error
{
    return nil;
}

- (void)enqueue
{
}

- (void)commit
{
    if (_committed)
        return;
    _committed = YES;
    CharonMetalDevice *device = [CharonMetalDevice shared];
    [device acquire];
    if (_drawable)
        [_drawable present];
    glFlush();
    [device relinquish];
    _status = MTLCommandBufferStatusCompleted;
    for (void (^handler)(id<MTLCommandBuffer>) in _completed)
        handler(self);
}

- (void)addScheduledHandler:(MTLCommandBufferHandler)block
{
    block(self);
}

- (void)addCompletedHandler:(MTLCommandBufferHandler)block
{
    [_completed addObject:[block copy]];
}

- (void)presentDrawable:(id<MTLDrawable>)drawable
{
    _drawable = drawable;
}

- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)presentationTime
{
    _drawable = drawable;
}

- (void)presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)duration
{
    _drawable = drawable;
}

- (void)waitUntilScheduled
{
}

- (void)waitUntilCompleted
{
    CharonMetalDevice *device = [CharonMetalDevice shared];
    [device acquire];
    glFinish();
    [device relinquish];
}

- (id<MTLComputeCommandEncoder>)computeCommandEncoder
{
    NSLog(@"Metal: the graphics of this device run no compute functions");
    return nil;
}

- (id<MTLBlitCommandEncoder>)blitCommandEncoder
{
    NSLog(@"Metal: a blit command encoder has no form in this port yet");
    return nil;
}

- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
{
    return (id<MTLRenderCommandEncoder>)[[CharonMetalEncoder alloc] initWithDescriptor:renderPassDescriptor];
}

@end
