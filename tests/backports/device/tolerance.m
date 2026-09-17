#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "check.h"

static NSString *image_of(void *address)
{
    Dl_info info;
    return dladdr(address, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

int main(void)
{
    @autoreleasepool {
        NSTimer *once = [NSTimer timerWithTimeInterval:10 target:[NSObject new] selector:@selector(description) userInfo:nil repeats:NO];
        NSTimer *repeating = [NSTimer timerWithTimeInterval:10 target:[NSObject new] selector:@selector(description) userInfo:nil repeats:YES];
        CHECK(&CFRunLoopTimerSetTolerance != NULL && &CFRunLoopTimerGetTolerance != NULL, "tolerance functions are bound");
        CHECK_EQUAL(image_of(&CFRunLoopTimerSetTolerance), @"libFoundationBackports.dylib", "tolerance functions come from the backports library");
        CHECK(once.tolerance == 0, "a new timer has no tolerance");
        once.tolerance = -3;
        CHECK(CFRunLoopTimerGetTolerance((__bridge CFRunLoopTimerRef)once) == 0, "a negative tolerance becomes zero");
        CFRunLoopTimerSetTolerance((__bridge CFRunLoopTimerRef)once, 2.5);
        CHECK(once.tolerance == 2.5, "the CF setter and the NSTimer getter share the value");
        once.tolerance = 100;
        CHECK(once.tolerance == 100, "a one-shot timer keeps a tolerance longer than its interval");
        repeating.tolerance = 100;
        CHECK(repeating.tolerance == 5, "a repeating timer caps tolerance at half its interval");
        __block int fired = 0;
        NSTimer *soon = [NSTimer scheduledTimerWithTimeInterval:0.05 target:[NSBlockOperation blockOperationWithBlock:^{ fired++; }] selector:@selector(main) userInfo:nil repeats:NO];
        soon.tolerance = 0.01;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        CHECK(fired == 1, "a timer with a tolerance still fires");
    }
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures;
}
