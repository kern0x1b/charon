#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "CharonMetal.h"
#import "CharonMetal26Types.h"

// THE METAL 4 QUEUE, over the port's own CharonMetalQueue, which is the queue that works: it holds the
// EAGL context over OpenGL ES 2.0 that every draw in this port goes through. So a Metal 4 caller asking
// for a Metal 4 queue gets the same working queue a Metal 3 caller gets, with the two members the rows
// name on top. That is what makes the row honest - there is ONE queue in this port and it is the one
// that runs - and it is why this class adds members and not behaviour.
//
// It is a class rather than a conformance to @protocol MTL4CommandQueue because iOS 6 has no Metal 4
// protocol to conform to: the 26.2 headers declare the protocol and the surface's rows for its members
// are the class's.
//
// WHAT THE PORT DOES NOT CARRY, and why, is the rest of the protocol: the residency set, the sparse
// mapping, the event and drawable waits. Each is refused by name in the methods below, because this
// port has no facility behind it - facts/Metal/RenderPath.md is where the rendering path says what it
// does, and facts/Metal/CommandChain26.md is where the expectations live.
@interface CharonMetal4CommandQueue : NSObject
- (id<MTLDevice>)device;
@property (nonatomic, copy) NSString *label;
@end

@implementation CharonMetal4CommandQueue {
    CharonMetalQueue *_queue;
    NSString *_label;
}

- (instancetype)init
{
    if ((self = [super init]))
        _queue = [[CharonMetalQueue alloc] init];
    return self;
}

// THE PORT'S OWN DEVICE, which is what a Metal 3 caller is told too: this port has one device and it is
// the shared one. The queue it answers with is the queue's own -device, not a fresh one, so the two
// agree by construction rather than by two lookups that could differ.
- (id<MTLDevice>)device
{
    return [_queue device];
}

// NIL ON A FRESH QUEUE, measured against Apple's own object and written down in
// tests/backports/device/metalchain-expectations.h as metalchain_queue_label_is_nil. The label is COPIED
// and is the queue's own string, so labelling a Metal 4 queue does not touch the Metal 3 one behind it.
- (NSString *)label
{
    return _label;
}

- (void)setLabel:(NSString *)label
{
    _label = [label copy];
}

@end

// THE DEVICE'S TWO METAL 4 FACTORIES, added where the device is rather than in this file, because an
// object carries the API of ONE release and CharonMetalDevice is 8.0's. Both hand back the same queue.
@interface CharonMetalDevice (CharonMetal4CommandQueue26)
- (id)newMTL4CommandQueue;
- (id)newMTL4CommandQueueWithDescriptor:(MTL4CommandQueueDescriptor *)descriptor error:(NSError **)error;
@end

@implementation CharonMetalDevice (CharonMetal4CommandQueue26)

// Metal 4's plain factory, MTLDevice.h:1262ff. Apple's own answers with a queue on this machine, and the
// queue's fresh label is nil - both measured and both in the expectations header.
- (id)newMTL4CommandQueue
{
    return [[CharonMetal4CommandQueue alloc] init];
}

// WITH A DESCRIPTOR, MTLDevice.h:1271, and this is Metal 4's: measured against Apple's own object, it
// answers with a queue and NO ERROR given a real MTL4CommandQueueDescriptor
// (metalchain_queue_from_descriptor_has_no_error). The descriptor's label is taken; its feedbackQueue is
// not, because this queue has no feedback to put on one - the port's feedback is the commit, and there is
// nowhere on a command queue here for it to report to.
- (id)newMTL4CommandQueueWithDescriptor:(MTL4CommandQueueDescriptor *)descriptor error:(NSError **)error
{
    CharonMetal4CommandQueue *queue = [[CharonMetal4CommandQueue alloc] init];
    queue.label = descriptor.label;
    return queue;
}

// THE COMMIT, the queue's only submit call, and it COMMITS rather than refusing: measured in a process
// execed on its own, Apple's own -commit:count: RETURNS on the header's own path and on the un-ended one
// alike (chain-commit.sh, metalchain_commit_returns). The C ARRAY is spelled as MTL4CommandQueue.h:231
// declares it, because the first version of that probe passed one buffer where an array was expected and
// the framework read the object's memory - a fault that was mine and is retracted in the facts.
- (void)commit:(const void *)commandBuffers count:(NSUInteger)count
{
    // The port's queue commits each buffer through the Metal 3 queue underneath it, which is what
    // actually runs the work over the EAGL context. The buffer array is read as the array of
    // MTLCommandBuffer the port's own queue understands.
    const id<MTLCommandBuffer> *buffers = (const id<MTLCommandBuffer> *)commandBuffers;
    for (NSUInteger index = 0; index < count; index++) {
        id<MTLCommandBuffer> buffer = buffers[index];
        if ([buffer isKindOfClass:[CharonMetalCommandBuffer class]])
            [buffer commit];
    }
}

// THE WAIT IS NOT HERE, and that is Apple's shape rather than a gap: Metal 4's queue has no
// -waitForCommandBuffers: (metalchain_queue_has_no_wait_for_command_buffers), its only waits being
// -waitForEvent:value: and -waitForDrawable:. This port's queue has neither of those either - it has no
// MTLEvent to wait on and no drawable of its own - so each is refused by name rather than answered.

// THE RESIDENCY SETS, THE SPARSE MAPPINGS, AND THE EVENT AND DRAWABLE WAITS, refused by name, each with
// the facility it would need and that this port does not have.
- (void)addResidencySet:(id)residencySet { (void)residencySet; }
- (void)removeResidencySet:(id)residencySet { (void)residencySet; }
- (void)addResidencySets:(const id *)sets count:(NSUInteger)count { (void)sets; (void)count; }
- (void)removeResidencySets:(const id *)sets count:(NSUInteger)count { (void)sets; (void)count; }
- (void)updateBufferMappings:(const void *)operations heap:(id<MTLHeap>)heap count:(NSUInteger)count
{ (void)operations; (void)heap; (void)count; }
- (void)updateTextureMappings:(const void *)operations heap:(id<MTLHeap>)heap count:(NSUInteger)count
{ (void)operations; (void)heap; (void)count; }
- (void)copyBufferMappingsFromBuffer:(id<MTLBuffer>)source toBuffer:(id<MTLBuffer>)destination
                           operations:(const void *)operations count:(NSUInteger)count
{ (void)source; (void)destination; (void)operations; (void)count; }
- (void)copyTextureMappingsFromTexture:(id<MTLTexture>)source toTexture:(id<MTLTexture>)destination
                             operations:(const void *)operations count:(NSUInteger)count
{ (void)source; (void)destination; (void)operations; (void)count; }
- (void)waitForDrawable:(id<MTLDrawable>)drawable { (void)drawable; }
- (void)waitForEvent:(id<MTLEvent>)event value:(uint64_t)value { (void)event; (void)value; }
- (void)signalEvent:(id<MTLEvent>)event value:(uint64_t)value { (void)event; (void)value; }
- (void)signalDrawable:(id<MTLDrawable>)drawable { (void)drawable; }

@end

// THE CAPTURE SCOPE OVER A METAL 4 QUEUE, which is the scope the port already makes over a Metal 3 one: a
// capture scope is a device and a queue, and this port's scope records both and starts nothing.
@interface MTLCaptureManager (CharonMetal4CaptureScope26)
- (id)newCaptureScopeWithMTL4CommandQueue:(id)commandQueue;
@end

@implementation MTLCaptureManager (CharonMetal4CaptureScope26)

- (id)newCaptureScopeWithMTL4CommandQueue:(id)commandQueue
{
    return [self newCaptureScopeWithCommandQueue:(id<MTLCommandQueue>)commandQueue];
}

@end
