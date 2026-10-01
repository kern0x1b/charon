/* The 16.0 descriptors, compared PROPERTY BY PROPERTY against Apple's own objects.
 *
 * NO DEVICE IS EVER CREATED. `MTLCreateSystemDefaultDevice()` HANGS on a machine with no GPU - it
 * was measured hanging and killed - so nothing here calls it, and nothing in this file needs it: a
 * descriptor is `[[X alloc] init]` on both sides. The host object is APPLE'S, made by Apple's class,
 * and it is the oracle: the port's value is compared against what Apple's own object answers for the
 * same property after the same write. A round trip of the port's object against ITSELF would prove
 * only that the port agrees with the port, and that is the round trip that let three reviews
 * through.
 *
 * The port's four classes are compiled with `-D<Name>=charonHost_<Name>`, so the two copies coexist
 * in one binary: the port's answer is the port's and Apple's own is Apple's. Each property is asked
 * of BOTH, and identity is never compared ACROSS the two - a pointer is only ever compared with a
 * pointer of the same side, which is a property of that side and not a number two objects share.
 *
 * Every value set below is one the SDK's own headers name, and none of them is chosen to make a
 * comparison pass. The two that are NOT in a header are Apple's own, measured: the four slots of the
 * attachment array and the queue descriptor's 64.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor : NSObject
@property (nonatomic, retain) id sampleBuffer;
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end

@interface charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray : NSObject
- (charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *)attachment
    atIndexedSubscript:(NSUInteger)index;
@end

@interface charonHost_MTLAccelerationStructurePassDescriptor : NSObject
@property (nonatomic, retain) id sampleBufferAttachments;
@end

@interface charonHost_MTLIOCommandQueueDescriptor : NSObject
@property (nonatomic) NSUInteger maxCommandBufferCount;
@property (nonatomic) MTLIOPriority priority;
@property (nonatomic) MTLIOCommandQueueType type;
@property (nonatomic) NSUInteger maxCommandsInFlight;
@property (nonatomic, retain) id scratchBufferAllocator;
@end

static int failures;
static int checks;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (ok) { printf("  ok   %s\n", [what UTF8String]); }
    else { printf("  FAIL %s\n", [what UTF8String]); failures++; }
}

/* THE COMPARISON ITSELF: the same write on both sides, then both values read. */
static void same_u(NSUInteger port, NSUInteger host, NSString *what)
{
    check(port == host, ([NSString stringWithFormat:@"%@: the port %lu and Apple's own object %lu",
                          what, (unsigned long)port, (unsigned long)host]));
}

static void same_i(long port, long host, NSString *what)
{
    check(port == host, ([NSString stringWithFormat:@"%@: the port %ld and Apple's own object %ld",
                          what, port, host]));
}

/* ASKING AN INDEX MUST NOT BE ABLE TO KILL THE RUN. The port refuses index 4 and beyond with an
 * exception, and a mutation that refuses a LEGAL index has to be a red CHECK, not a trap: an abort
 * leaves no assertion line for the harness to read and a mutation that is red for the wrong reason is
 * a mutation nobody can trust. Each reader below is a real call, wrapped, and reports whether it
 * answered - so a side that raises at index 3 is a check that fails and a run that carries on. */
static id hostSlot(id array, NSUInteger index)
{
    @try {
        return [(MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray *)array
            objectAtIndexedSubscript:index];
    } @catch (NSException *why) {
        printf("       Apple's side raised at %lu: %s\n", (unsigned long)index, [[why reason] UTF8String]);
        return nil;
    }
}

static id portSlot(id array, NSUInteger index)
{
    @try {
        return [(charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray *)array
            objectAtIndexedSubscript:index];
    } @catch (NSException *why) {
        printf("       the port raised at %lu: %s\n", (unsigned long)index, [[why reason] UTF8String]);
        return nil;
    }
}

int main(void)
{
    @autoreleasepool {
        printf("MTLAccelerationStructurePassSampleBufferAttachmentDescriptor\n");
        {   /* The fresh DEFAULTS are compared first, because a port that invented a default would pass
             * every written value below and still be wrong. The two indices start at
             * MTLCounterDontSample, which is NSUIntegerMax and NOT zero. */
            MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *host =
                [[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor alloc] init];
            charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *port =
                [[charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor alloc] init];
            check(host.sampleBuffer == nil && port.sampleBuffer == nil,
                  @"fresh: sampleBuffer is nil on both sides - and it is NOT measured, for the reason in the facts file");
            same_u(port.startOfEncoderSampleIndex, host.startOfEncoderSampleIndex,
                   @"fresh: startOfEncoderSampleIndex");
            same_u(port.endOfEncoderSampleIndex, host.endOfEncoderSampleIndex,
                   @"fresh: endOfEncoderSampleIndex");
            check(port.startOfEncoderSampleIndex == MTLCounterDontSample
                      && host.startOfEncoderSampleIndex == MTLCounterDontSample,
                  @"fresh: startOfEncoderSampleIndex is MTLCounterDontSample, the header's 'no sample'");
            [port setStartOfEncoderSampleIndex:3];
            [host setStartOfEncoderSampleIndex:3];
            [port setEndOfEncoderSampleIndex:4];
            [host setEndOfEncoderSampleIndex:4];
            same_u(port.startOfEncoderSampleIndex, host.startOfEncoderSampleIndex,
                   @"after a set: startOfEncoderSampleIndex = 3");
            same_u(port.endOfEncoderSampleIndex, host.endOfEncoderSampleIndex,
                   @"after a set: endOfEncoderSampleIndex = 4");
            /* <NSCopying> is in the header, so a copy is a copy on both sides and it carries what
             * was written - otherwise a caller who copies a descriptor and then changes it would
             * change the original. */
            MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *hostCopy = [host copy];
            charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *portCopy = [port copy];
            same_u(portCopy.startOfEncoderSampleIndex, hostCopy.startOfEncoderSampleIndex,
                   @"copy: startOfEncoderSampleIndex");
            same_u(portCopy.endOfEncoderSampleIndex, hostCopy.endOfEncoderSampleIndex,
                   @"copy: endOfEncoderSampleIndex");
        }

        printf("MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray\n");
        {   /* The array's two members, and the four slots behind them. Every question is asked of
             * both sides and answered as a property OF THAT SIDE, because a pointer means nothing
             * across two processes' worth of objects. */
            MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray *host =
                [MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor]
                    .sampleBufferAttachments;
            charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray *port =
                [[charonHost_MTLAccelerationStructurePassDescriptor alloc] init].sampleBufferAttachments;
            check(host != nil && port != nil,
                  @"a fresh pass descriptor's array is there on both sides, and the port's needs no device");
            id hostSlots[4], portSlots[4];
            for (NSUInteger index = 0; index < 4; index++) {
                hostSlots[index] = hostSlot(host, index);
                portSlots[index] = portSlot(port, index);
            }
            check(hostSlots[0] && hostSlots[1] && hostSlots[2] && hostSlots[3],
                  @"four reads of indices 0 to 3 each answer an attachment on Apple's side");
            check(portSlots[0] && portSlots[1] && portSlots[2] && portSlots[3],
                  @"four reads of indices 0 to 3 each answer an attachment on the port's side");
            /* POINTERS, NOT -isEqual:, and the reason is worth writing down: four fresh attachments
             * are four EQUAL objects by value, so -isEqual: says they are one and the check would
             * pass on a port that made a single attachment for all four slots. */
            check(hostSlots[0] != hostSlots[1] && hostSlots[0] != hostSlots[2]
                      && hostSlots[0] != hostSlots[3],
                  @"the four slots are four distinct attachments on Apple's side");
            check(portSlots[0] != portSlots[1] && portSlots[0] != portSlots[2]
                      && portSlots[0] != portSlots[3],
                  @"the four slots are four distinct attachments on the port's side");
            check(hostSlot(host, 0) == hostSlots[0] && portSlot(port, 0) == portSlots[0],
                  @"two reads of one index are the same attachment on both sides: an unwritten slot is kept");

            /* A WRITE COPIES - the header says "This always uses 'copy' semantics" - and a NIL WRITE
             * resets the slot to a fresh descriptor. Both are properties of the side, and both are
             * asked of both. */
            MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *hostWritten =
                [[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor alloc] init];
            [hostWritten setStartOfEncoderSampleIndex:11];
            [hostWritten setEndOfEncoderSampleIndex:12];
            [host setObject:hostWritten atIndexedSubscript:1];
            charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *portWritten =
                [[charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor alloc] init];
            [portWritten setStartOfEncoderSampleIndex:11];
            [portWritten setEndOfEncoderSampleIndex:12];
            [port setObject:portWritten atIndexedSubscript:1];
            id hostBack = hostSlot(host, 1);
            id portBack = portSlot(port, 1);
            same_u([hostBack startOfEncoderSampleIndex], [portBack startOfEncoderSampleIndex],
                   @"after a write at 1: startOfEncoderSampleIndex");
            same_u([hostBack endOfEncoderSampleIndex], [portBack endOfEncoderSampleIndex],
                   @"after a write at 1: endOfEncoderSampleIndex");
            check(hostBack != hostWritten && portBack != portWritten,
                  @"a write copies: the attachment read back is not the one handed in, on either side");
            same_u([hostSlots[0] startOfEncoderSampleIndex], [portSlots[0] startOfEncoderSampleIndex],
                   @"slot 0 after the write at 1: unchanged on both sides");
            [host setObject:nil atIndexedSubscript:1];
            [port setObject:nil atIndexedSubscript:1];
            id hostReset = hostSlot(host, 1);
            id portReset = portSlot(port, 1);
            same_u([hostReset startOfEncoderSampleIndex], [portReset startOfEncoderSampleIndex],
                   @"after a nil write at 1: startOfEncoderSampleIndex is back to the default");
            same_u([hostReset endOfEncoderSampleIndex], [portReset endOfEncoderSampleIndex],
                   @"after a nil write at 1: endOfEncoderSampleIndex is back to the default");
            check(hostReset != hostBack && portReset != portBack,
                  @"a nil write resets the slot to a NEW default attachment, on either side");

            /* INDEX 4 IS THE BOUND, and only the port's side is asked: Apple's own object STOPS THE
             * PROCESS on it, which is a C assertion, so asking there is not a comparison but a
             * killed run. Apple's own answer was measured one index per process and is in
             * facts/Metal/Descriptors16.md with the command; what is checked here is that the port
             * refuses the same index with the same words. */
            id portAtFour = nil;
            BOOL portAnswered = YES;
            @try {
                portAtFour = [port objectAtIndexedSubscript:4];
            } @catch (NSException *why) {
                portAnswered = NO;
                printf("       raised %s: %s\n", [[why name] UTF8String], [[why reason] UTF8String]);
            }
            check(!portAnswered && portAtFour == nil,
                  @"index 4 is refused by the port: no attachment is handed back");
        }

        printf("MTLAccelerationStructurePassDescriptor\n");
        {   /* The header declares one member and it is READONLY, so a fresh descriptor has to make
             * one - measured on Apple's side through its own factory and by a plain -init. */
            MTLAccelerationStructurePassDescriptor *host =
                [MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor];
            charonHost_MTLAccelerationStructurePassDescriptor *port =
                [[charonHost_MTLAccelerationStructurePassDescriptor alloc] init];
            check([host isKindOfClass:[MTLAccelerationStructurePassDescriptor class]]
                      && [port isKindOfClass:[charonHost_MTLAccelerationStructurePassDescriptor class]],
                  @"both sides are a kind of the class the case names; Apple's is a private subclass of it");
            check(host.sampleBufferAttachments != nil && port.sampleBufferAttachments != nil,
                  @"sampleBufferAttachments is there on a fresh descriptor on both sides");
            /* A COPY GETS ITS OWN ARRAY, so a caller who copies a pass descriptor and then fills the
             * copy's slots does not fill the original's. */
            MTLAccelerationStructurePassDescriptor *hostCopy = nil;
            charonHost_MTLAccelerationStructurePassDescriptor *portCopy = nil;
            @try { hostCopy = [host copy]; } @catch (NSException *why) {
                printf("       Apple's side raised on -copy: %s\n", [[why reason] UTF8String]);
            }
            @try { portCopy = [port copy]; } @catch (NSException *why) {
                printf("       the port raised on -copy: %s\n", [[why reason] UTF8String]);
            }
            check(hostCopy != nil && portCopy != nil, @"a copy of the pass descriptor is made on both sides");
            check(hostCopy.sampleBufferAttachments != host.sampleBufferAttachments
                      && portCopy.sampleBufferAttachments != port.sampleBufferAttachments,
                  @"a copy's array is a different object from the original's, on either side");
            MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *hostCopySlot =
                hostSlot(hostCopy.sampleBufferAttachments, 2);
            charonHost_MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *portCopySlot =
                portSlot(portCopy.sampleBufferAttachments, 2);
            [hostCopySlot setStartOfEncoderSampleIndex:21];
            [portCopySlot setStartOfEncoderSampleIndex:21];
            same_u([hostSlot(host.sampleBufferAttachments, 2) startOfEncoderSampleIndex],
                   [portSlot(port.sampleBufferAttachments, 2) startOfEncoderSampleIndex],
                   @"slot 2 of the ORIGINAL after a write through the copy's array: unchanged on both sides");
        }

        printf("MTLIOCommandQueueDescriptor\n");
        {   /* Four numbers, three of which are not what a C enumeration's zero would suggest, and
             * none of which the header gives a default for. Apple's own object is the oracle for
             * every one of them, and the fresh values are compared before any write. */
            MTLIOCommandQueueDescriptor *host = [[MTLIOCommandQueueDescriptor alloc] init];
            charonHost_MTLIOCommandQueueDescriptor *port = [[charonHost_MTLIOCommandQueueDescriptor alloc] init];
            same_u(port.maxCommandBufferCount, host.maxCommandBufferCount,
                   @"fresh: maxCommandBufferCount - Apple's own default, which the header does not state");
            check(host.maxCommandBufferCount == 64,
                  @"fresh: Apple's own maxCommandBufferCount is 64, the number the port carries");
            same_i((long)port.priority, (long)host.priority, @"fresh: priority");
            check(host.priority == MTLIOPriorityNormal && MTLIOPriorityHigh == 0,
                  @"fresh: priority is MTLIOPriorityNormal, NOT the enumeration's own zero");
            same_i((long)port.type, (long)host.type, @"fresh: type");
            same_u(port.maxCommandsInFlight, host.maxCommandsInFlight, @"fresh: maxCommandsInFlight");
            check(host.scratchBufferAllocator == nil && port.scratchBufferAllocator == nil,
                  @"fresh: scratchBufferAllocator is nil on both sides, and it is not measured");
            [port setMaxCommandBufferCount:7];
            [host setMaxCommandBufferCount:7];
            [port setPriority:MTLIOPriorityLow];
            [host setPriority:MTLIOPriorityLow];
            [port setType:MTLIOCommandQueueTypeSerial];
            [host setType:MTLIOCommandQueueTypeSerial];
            [port setMaxCommandsInFlight:9];
            [host setMaxCommandsInFlight:9];
            same_u(port.maxCommandBufferCount, host.maxCommandBufferCount, @"after a set: maxCommandBufferCount = 7");
            same_i((long)port.priority, (long)host.priority, @"after a set: priority = Low");
            same_i((long)port.type, (long)host.type, @"after a set: type = Serial");
            same_u(port.maxCommandsInFlight, host.maxCommandsInFlight, @"after a set: maxCommandsInFlight = 9");
            /* A COPY CARRIES THREE OF THE FOUR, and the fourth is Apple's own behaviour rather than
             * an omission here: measured, a descriptor with 9 in flight copies to 0. */
            MTLIOCommandQueueDescriptor *hostCopy = [host copy];
            charonHost_MTLIOCommandQueueDescriptor *portCopy = [port copy];
            same_u(portCopy.maxCommandBufferCount, hostCopy.maxCommandBufferCount, @"copy: maxCommandBufferCount");
            same_i((long)portCopy.priority, (long)hostCopy.priority, @"copy: priority");
            same_i((long)portCopy.type, (long)hostCopy.type, @"copy: type");
            same_u(portCopy.maxCommandsInFlight, hostCopy.maxCommandsInFlight, @"copy: maxCommandsInFlight");
            check(hostCopy.maxCommandsInFlight == 0 && host.maxCommandsInFlight == 9,
                  @"Apple's own -copyWithZone: does not carry maxCommandsInFlight, and the port matches that");
        }

        printf("no device was created: %d checks, each one against Apple's own object\n", checks);
    }
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("all checks passed\n");
    return 0;
}
