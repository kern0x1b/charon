/* descriptors26-chain.m - the top of the Metal 4 command chain, against Apple's own objects.
 *
 * WHAT IS MEASURED HERE, and why this family is only as far as it is. Apple 4 IS present on this
 * machine and a live queue can be made through -[MTLDevice newMTL4CommandQueue], so the queue and the
 * two descriptors have an oracle. Two things do not:
 *
 *   * -[MTLDevice newCommandQueueWithDescriptor:] RAISES on this SDK. Apple's own queue sends
 *     -disableIOFencing to the descriptor and the SDK's own MTL4CommandQueueDescriptor does not
 *     implement it, so the framework refuses itself.
 *   * -[MTL4CommandQueue beginCommandBufferWithAllocator:] is NOT IMPLEMENTED on Apple's own queue
 *     here, so there is no live Metal 4 command buffer to compare against and nothing below it either.
 *
 * Both are measured in this file's own output further down, from APPLE'S side, so the claim is a
 * measurement and not an excuse.
 *
 * NO DEVICE IS CREATED BY THIS CASE beyond what MTLCreateSystemDefaultDevice gives, and every side is
 * asked by its own name: the port's classes and its two device factories are compiled under other
 * names so that both copies are in one binary.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#include <dlfcn.h>

/* The port's classes, under the names the harness compiles them with. The queue is NOT among them: it
 * is a wrapper over the port's CharonMetalQueue, which holds an EAGL context, and OpenGLES/EAGL.h is a
 * device framework - so this binary could not compile it, and that is the queue's reason, not the
 * absence of one on this machine. */
@interface charonHost_MTL4CommandQueueDescriptor : NSObject <NSCopying>
@property (nonatomic, copy) id label;
@end
@interface charonHost_MTL4CommandBufferOptions : NSObject <NSCopying>
@property (nonatomic, retain) id logState;
@end

static int failures;
static int checks;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (ok) printf("  ok   %s\n", [what UTF8String]);
    else { printf("  FAIL %s\n", [what UTF8String]); failures++; }
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        checks++;
        if (NSClassFromString(@"ZZZNoSuchNameCharonR16") == nil)
            printf("  ok   the control: ZZZNoSuchNameCharonR16 is not a class of this framework\n");
        else {
            printf("  FAIL the control: ZZZNoSuchNameCharonR16 exists, so this harness's answers mean nothing\n");
            failures++;
        }

        /* THE ERROR DOMAIN'S VALUE, read out of Apple's own framework through an asm label. dlsym was
         * the first spelling and it read the ADDRESS OF THE VARIABLE as an object pointer - a Bus error
         * before any output at all, measured. */
        extern NSString *const MTL4CommandQueueErrorDomain __asm__("_MTL4CommandQueueErrorDomain");
        /* The port's error domain is the SAME SYMBOL on both sides - one object defines one name - so it is
 * read once and there is nothing to compare. What is compared is that the name resolves to a string at
 * all, which is what makes it usable as a domain. */
        checks++;
        if (dlsym(RTLD_DEFAULT, "ZZZNoSuchNameCharonR16") == NULL)
            printf("  ok   the control: ZZZNoSuchNameCharonR16 is not a symbol of anything loaded\n");
        else {
            printf("  FAIL the control: ZZZNoSuchNameCharonR16 was found\n");
            failures++;
        }
        check([MTL4CommandQueueErrorDomain isKindOfClass:[NSString class]],
              @"MTL4CommandQueueErrorDomain resolves to a string");
        printf("  ok   MTL4CommandQueueErrorDomain -> %s\n",
               [[MTL4CommandQueueErrorDomain description] UTF8String]);

        printf("the two descriptors, fresh, on both sides\n");
        {
            MTL4CommandQueueDescriptor *host = [[MTL4CommandQueueDescriptor alloc] init];
            charonHost_MTL4CommandQueueDescriptor *port = [[charonHost_MTL4CommandQueueDescriptor alloc] init];
            check(host.label == nil && port.label == nil, @"queue descriptor: label is nil on both sides");
            check([host respondsToSelector:@selector(feedbackQueue)] &&
                  [port respondsToSelector:@selector(feedbackQueue)],
                  @"queue descriptor: feedbackQueue is a member on both sides");
            id hostQueue = [host valueForKey:@"feedbackQueue"];
            id portQueue = [port valueForKey:@"feedbackQueue"];
            check(hostQueue == nil && portQueue == nil,
                  @"queue descriptor: feedbackQueue is nil on both sides");
            /* THE LABEL IS COPIED, which is what the header's `copy` says and what a reader depends on:
             * changing the string handed in must not change what the descriptor reads back. */
            NSMutableString *mutable = [NSMutableString stringWithString:@"first"];
            host.label = mutable; port.label = mutable;
            [mutable appendString:@"-changed"];
            check(![host.label isEqualToString:@"first-changed"] && ![port.label isEqualToString:@"first-changed"],
                  @"queue descriptor: the label is a copy, so changing the caller's string changes neither");
            MTL4CommandQueueDescriptor *hostCopy = [host copy];
            charonHost_MTL4CommandQueueDescriptor *portCopy = [port copy];
            /* THE COPY CARRIES WHAT THE DESCRIPTOR HOLDS, and this assertion said otherwise the first
             * time: it compared the copy against the caller's MUTATED string, and measured against
             * Apple's own object the copy reads back the label as it stood when it was set - "first",
             * not "first-changed". The copy is compared to each side's own descriptor, which is what
             * "carries the label" means. */
            id hostCopied = [hostCopy valueForKey:@"label"];
            id portCopied = [portCopy valueForKey:@"label"];
            check([hostCopied isEqual:[host valueForKey:@"label"]] &&
                  [portCopied isEqual:[port valueForKey:@"label"]],
                  @"queue descriptor: a copy carries the label each side holds");
        }
        {
            MTL4CommandBufferOptions *host = [[MTL4CommandBufferOptions alloc] init];
            charonHost_MTL4CommandBufferOptions *port = [[charonHost_MTL4CommandBufferOptions alloc] init];
            check([host valueForKey:@"logState"] == nil && [port valueForKey:@"logState"] == nil,
                  @"buffer options: logState is nil on both sides");
            check([[host copy] valueForKey:@"logState"] == nil,
                  @"buffer options: APPLE's copy carries the member, which is nil here");
            check([[port copy] valueForKey:@"logState"] == nil,
                  @"buffer options: the PORT's copy carries it too, which is nil here");
        }

        printf("AND WHY THE QUEUE IS NOT IN THIS CASE, measured from Apple's side\n");
        {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            check(device != nil, @"this machine has a Metal device");
            /* A LIVE METAL 4 QUEUE EXISTS HERE - so the absence of one is not the reason the queue is
             * out of this case, and saying so is what makes the real reason visible. */
            id appleQueue = [device performSelector:NSSelectorFromString(@"newMTL4CommandQueue")];
            check(appleQueue != nil, @"APPLE's device answers -newMTL4CommandQueue, so a live queue is possible here");
            id appleFreshLabel = [appleQueue valueForKey:@"label"];
            check(appleFreshLabel == nil,
                  @"and its fresh label is nil, which is the queue's own measured default");
            /* THE FIRST REASON: APPLE'S OWN QUEUE REFUSES ITS OWN DESCRIPTOR on this SDK. */
            @try {
                Class descriptorClass = NSClassFromString(@"MTL4CommandQueueDescriptor");
                id (*make)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
                id refused = make(device, NSSelectorFromString(@"newCommandQueueWithDescriptor:"),
                                  [[descriptorClass alloc] init]);
                printf("       APPLE's newCommandQueueWithDescriptor: -> %s\n", refused ? "a queue" : "nil");
            } @catch (NSException *why) {
                printf("  ok   APPLE's own -newCommandQueueWithDescriptor: RAISES here: %s\n",
                       [[why reason] UTF8String]);
            }
            /* THE SECOND, and the one that decides the whole chain: THERE IS NO COMMAND BUFFER TO BEAT. */
            @try {
                id (*begin)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
                id buffer = begin(appleQueue, NSSelectorFromString(@"beginCommandBufferWithAllocator:"), nil);
                printf("       APPLE's beginCommandBufferWithAllocator: -> %s\n", buffer ? "a buffer" : "nil");
            } @catch (NSException *why) {
                printf("  ok   APPLE's own queue does not implement -beginCommandBufferWithAllocator: here: %s\n",
                       [[why reason] UTF8String]);
            }
        }

        printf("%d checks\n", checks);
    }
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("all checks passed\n");
    return 0;
}