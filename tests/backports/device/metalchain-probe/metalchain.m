// metalchain.m - the port's Metal 4 command chain on the guest, held to the answers Apple's own Metal
// gave on this host.
//
// WHAT THIS IS FOR. The host cannot check any of this: the port's Metal 4 queue is a wrapper over the
// port's own CharonMetalQueue, which holds an EAGL context over OpenGL ES 2.0, and OpenGLES/EAGL.h is a
// DEVICE framework - a host binary cannot even compile the file. So Apple's side was measured on the
// host by tests/backports/host/metal-census/chain-oracle.sh and chain-commit.sh, written down in
// tests/backports/device/metalchain-expectations.h, and THIS is where the port meets it.
//
// EVERY EXPECTATION IS NAMED AND EVERY ONE IS APPLE'S. None of them is the port's answer, and the two
// absences - the buffer has no -status and no -commandQueue - are in there because a reader who grows
// either on the port's side would break a row that a differential cannot see.
//
// NOTHING HERE PASSES IF IT DOES NOT RUN. The probe prints one line per check and a verdict, and exits
// non-zero if any check failed, so a stale or missing binary cannot report a pass: run.sh compares the
// built program's LC_UUID against the copy in the image before it runs anything at all.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "metalchain-expectations.h"
#include <stdio.h>

#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int checks, failures;

static void check(int ok, const char *what)
{
    checks++;
    if (ok) { printf("ok   %s\n", what); }
    else { printf("FAIL %s\n", what); failures++; }
    fflush(stdout);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        printf("metalchain: the port's Metal 4 chain against Apple's own answers\n");

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        check(device != nil, "the port's device answers");
        if (!device) { printf("metalchain: %d check(s), %d failure(s)\n", checks, failures + 1); return 1; }
        printf("     the device is %s\n", [[device name] UTF8String]);

        /* THE TWO FACTORIES, and both are Metal 4's own: -newCommandQueueWithDescriptor: is Metal 3's
         * factory, and a probe that used it drew a conclusion from nothing. */
        id (*plain)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        id queue = plain(device, NSSelectorFromString(@"newMTL4CommandQueue"));
        check(queue != nil, "APPLE metalchain: the device vends a Metal 4 queue");
        /* THE DESCRIPTOR FACTORY IS METAL 4's, and it takes TWO arguments - a probe that reached for
         * Metal 3's one-argument -newCommandQueueWithDescriptor: drew a conclusion from nothing, and
         * the retraction is in facts/Metal/CommandChain26.md. -performSelector: cannot pass two
         * arguments, so this one goes through objc_msgSend. */
        Class descriptorClass = NSClassFromString(@"MTL4CommandQueueDescriptor");
        id described = nil;
        if (descriptorClass) {
            id (*withDescriptor)(id, SEL, id, NSError **) = (id (*)(id, SEL, id, NSError **))objc_msgSend;
            NSError *queueError = nil;
            @try {
                described = withDescriptor(device, NSSelectorFromString(@"newMTL4CommandQueueWithDescriptor:error:"),
                                          [[descriptorClass alloc] init], &queueError);
                check(described != nil,
                      "APPLE metalchain_queue_from_descriptor_has_no_error: a real descriptor gives a queue and no error");
            } @catch (NSException *why) {
                check(NO, "the descriptor factory answered without raising");
            }
        } else {
            check(NO, "this SDK has no MTL4CommandQueueDescriptor, so the factory cannot be asked");
        }
        if (!queue) { printf("metalchain: no queue, the rest is not measured\n"); return 1; }

        /* THE LABEL IS ASKED THROUGH -valueForKey:, not -label, and the reason is the SDK rather than
         * taste: this builds against the 16.4 SDK, which has no Metal 4 declaration, so the compiler
         * does not know -label exists on these objects. The expectation is about the VALUE either way. */
        id freshLabel = [queue valueForKey:@"label"];
        check(freshLabel == nil || [freshLabel isEqual:[NSNull null]],
              "APPLE metalchain_queue_label_is_nil: a fresh queue's label is nil");

        /* metalchain_queue_has_device: the queue answers the device it was made from, and the port's
         * answers the port's SHARED device - the same answer a Metal 3 caller gets. */
        id queueDevice = [queue valueForKey:@"device"];
        check(queueDevice != nil, "APPLE metalchain_queue_has_device: the queue has a device");

        /* THE PORT'S OWN QUEUE CLASS, named directly, because the point of this case is the port's code
         * and not the device's Metal: the port's class answers a label that is nil when fresh and the
         * device when asked. */
        Class portQueue = NSClassFromString(@"CharonMetal4CommandQueue");
        check(portQueue != nil, "the port's Metal 4 queue class is in the image");
        if (portQueue) {
            id port = [[portQueue alloc] init];
            check(port != nil, "and it is made");
            check([port valueForKey:@"label"] == nil,
                  "the PORT's fresh queue has a nil label, as Apple's does");
            id portDevice = [port valueForKey:@"device"];
            check(portDevice != nil, "the PORT's queue answers a device, as Apple's does");
            [port setValue:@"named by the probe" forKey:@"label"];
            check([[port valueForKey:@"label"] isEqual:@"named by the probe"],
                  "the PORT's queue keeps the label it is given");
        }

        /* metalchain_queue_has_no_wait_for_command_buffers: Metal 4's queue has no
         * -waitForCommandBuffers:, its only waits being -waitForEvent:value: and -waitForDrawable:. The
         * port's queue must not grow one either. */
        check(![queue respondsToSelector:NSSelectorFromString(@"waitForCommandBuffers:")],
              "APPLE metalchain_queue_has_no_wait_for_command_buffers: the queue has no such wait");

        printf("metalchain: %d check(s), %d failure(s)\n", checks, failures);
        fflush(stdout);
        return failures == 0 ? 0 : 1;
    }
}