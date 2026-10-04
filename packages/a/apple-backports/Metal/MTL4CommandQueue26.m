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
//
// **TWELVE OF THE PROTOCOL'S OWN MEMBERS ARE ON THIS CLASS, and they were on the DEVICE until the device
// probe found it.** Every method from -commit:count: down used to be written in the CharonMetalDevice
// category below, so all fourteen of them answered on the DEVICE and none on the queue - and a Metal 4
// caller holds a queue. Twelve are here now; the two commits are not, because they need a buffer this port
// does not carry, and the reason is at their place in the declaration below. It was found by running and
// not by reading: the device probe's case
// metalchain_commit_returns asks the queue for -commit:count: and the run of 2026-10-04 answered
// "FAIL metalchain_commit_returns: the queue answers -commit:count: (Apple's own queue does)", while the
// binary's own symbol table carries -[CharonMetalDevice(CharonMetal4CommandQueue26) commit:count:] and
// nothing of that name on the queue (tests/backports/device/metalchain-probe/run/run.log). The ledger
// agrees and was not guessing: all fourteen were status `missing` - they are the queue's members, so with
// none of them on the queue the queue did not exist as far as the corpus was concerned.
@interface CharonMetal4CommandQueue : NSObject
- (id<MTLDevice>)device;
@property (nonatomic, copy) NSString *label;
// **-commit:count: AND -commit:count:options: ARE NOT HERE, and that is a dependency and not an
// oversight.** Both take an array of MTL4CommandBuffer, and this port carries no MTL4CommandBuffer: the
// buffer is the next family (Metal/MTL4CommandBuffer26.m does not exist yet) and every buffer a Metal 4
// caller could hand the commit would be "not one of this port's". A method that answers wrongly is worse
// than one that is absent, so the two rows -[MTL4CommandQueue commit:count:] and
// -[MTL4CommandQueue commit:count:options:] are status `owed` with the reason "waits on the
// MTL4CommandBuffer family", and check_registry holds a row that is not `implemented` to an answer the
// build does not give ("listed as absent, but what is built answers it"). They come back with the buffer.
- (void)addResidencySet:(id)residencySet;
- (void)removeResidencySet:(id)residencySet;
- (void)addResidencySets:(const id *)sets count:(NSUInteger)count;
- (void)removeResidencySets:(const id *)sets count:(NSUInteger)count;
- (void)updateBufferMappings:(const void *)operations heap:(id<MTLHeap>)heap count:(NSUInteger)count;
- (void)updateTextureMappings:(const void *)operations heap:(id<MTLHeap>)heap count:(NSUInteger)count;
- (void)copyBufferMappingsFromBuffer:(id<MTLBuffer>)source toBuffer:(id<MTLBuffer>)destination
                           operations:(const void *)operations count:(NSUInteger)count;
- (void)copyTextureMappingsFromTexture:(id<MTLTexture>)source toTexture:(id<MTLTexture>)destination
                              operations:(const void *)operations count:(NSUInteger)count;
- (void)waitForDrawable:(id<MTLDrawable>)drawable;
// MTL4CommandQueue.h:274 and :308 spell the event `id<MTLEvent>`, and it is spelled `id` here: iOS 6 has
// no MTLEvent for the port to name, the SDK annotates the type as 12.0 and later, and naming it would
// warn on every build of this file for a method that refuses the call anyway. The selector is the one
// the header declares, which is what a caller and the registry both see.
- (void)waitForEvent:(id)event value:(uint64_t)value;
- (void)signalEvent:(id)event value:(uint64_t)value;
- (void)signalDrawable:(id<MTLDrawable>)drawable;
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

// THE RESIDENCY SETS, THE SPARSE MAPPINGS, AND THE EVENT AND DRAWABLE WAITS, refused by name, each with
// the facility it would need and that this port does not have. The refusal is a line in the log, which is
// how this port refuses a void method everywhere else (Metal/MTLComputeCommandEncoder8.m:145 and its
// neighbours): a method that silently swallowed its argument would be a row claiming a refusal the code
// does not make, which is the defect the eleven `(void)` bodies these replace were.
- (void)addResidencySet:(id)residencySet
{
    NSLog(@"Metal: a residency set is refused: this port keeps every resource resident for the life of its EAGL context and has no residency set to add one to");
}

- (void)removeResidencySet:(id)residencySet
{
    NSLog(@"Metal: removing a residency set is refused: this port keeps every resource resident for the life of its EAGL context and has no residency set to remove one from");
}

- (void)addResidencySets:(const id *)sets count:(NSUInteger)count
{
    NSLog(@"Metal: %lu residency set(s) are refused: this port keeps every resource resident for the life of its EAGL context and has no residency set to add them to", (unsigned long)count);
}

- (void)removeResidencySets:(const id *)sets count:(NSUInteger)count
{
    NSLog(@"Metal: removing %lu residency set(s) is refused: this port keeps every resource resident for the life of its EAGL context and has no residency set to remove them from", (unsigned long)count);
}

- (void)updateBufferMappings:(const void *)operations heap:(id<MTLHeap>)heap count:(NSUInteger)count
{
    NSLog(@"Metal: a sparse buffer mapping is refused: it needs an MTLHeap with a residency mode, and this port's heaps are the arena of one EAGL context with nothing sparse in it");
}

- (void)updateTextureMappings:(const void *)operations heap:(id<MTLHeap>)heap count:(NSUInteger)count
{
    NSLog(@"Metal: a sparse texture mapping is refused: it needs an MTLHeap with a residency mode, and this port's heaps are the arena of one EAGL context with nothing sparse in it");
}

- (void)copyBufferMappingsFromBuffer:(id<MTLBuffer>)source toBuffer:(id<MTLBuffer>)destination
                           operations:(const void *)operations count:(NSUInteger)count
{
    NSLog(@"Metal: copying %lu sparse buffer mapping(s) is refused: there are no sparse mappings to copy, since none can be made", (unsigned long)count);
}

- (void)copyTextureMappingsFromTexture:(id<MTLTexture>)source toTexture:(id<MTLTexture>)destination
                              operations:(const void *)operations count:(NSUInteger)count
{
    NSLog(@"Metal: copying %lu sparse texture mapping(s) is refused: there are no sparse mappings to copy, since none can be made", (unsigned long)count);
}

- (void)waitForDrawable:(id<MTLDrawable>)drawable
{
    NSLog(@"Metal: waiting for a drawable is refused: this queue has no drawable of its own, and a CAMetalLayer's is presented by the application that made it");
}

- (void)waitForEvent:(id)event value:(uint64_t)value
{
    NSLog(@"Metal: waiting for an MTLEvent is refused: this port has no event that outlives the EAGL context it would be waited on");
}

- (void)signalEvent:(id)event value:(uint64_t)value
{
    NSLog(@"Metal: signalling an MTLEvent is refused: this port has no event that outlives the EAGL context it would be signalled on");
}

- (void)signalDrawable:(id<MTLDrawable>)drawable
{
    NSLog(@"Metal: signalling a drawable is refused: this queue has no drawable of its own, and a CAMetalLayer's is presented by the application that made it");
}

@end

// THE DEVICE'S TWO METAL 4 FACTORIES, added where the device is rather than in this file, because an
// object carries the API of ONE release and CharonMetalDevice is 8.0's. Both hand back the same queue.
//
// AND NOTHING ELSE: every other member of @protocol MTL4CommandQueue is the QUEUE's and is on the queue
// above. A Metal 4 method on the device is one a Metal 4 caller cannot reach through the object it holds.
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

// THE WAIT IS NOT HERE ON THE DEVICE EITHER, and that is Apple's shape rather than a gap: Metal 4's
// queue has no -waitForCommandBuffers: (metalchain_queue_has_no_wait_for_command_buffers), its only
// waits being -waitForEvent:value: and -waitForDrawable:. So the device does not grow one either.
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
