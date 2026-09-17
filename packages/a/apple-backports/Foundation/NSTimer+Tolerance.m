#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static char charon_tolerance_key;

CFTimeInterval CFRunLoopTimerGetTolerance(CFRunLoopTimerRef timer)
{
    NSNumber *tolerance = objc_getAssociatedObject((__bridge id)timer, &charon_tolerance_key);
    return tolerance.doubleValue;
}

void CFRunLoopTimerSetTolerance(CFRunLoopTimerRef timer, CFTimeInterval tolerance)
{
    CFTimeInterval accepted = tolerance > 0 ? tolerance : 0;
    if (CFRunLoopTimerDoesRepeat(timer))
        accepted = MIN(accepted, CFRunLoopTimerGetInterval(timer) / 2);
    objc_setAssociatedObject((__bridge id)timer, &charon_tolerance_key, @(accepted), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation NSTimer (CharonTolerance)

- (NSTimeInterval)tolerance
{
    return CFRunLoopTimerGetTolerance((__bridge CFRunLoopTimerRef)self);
}

- (void)setTolerance:(NSTimeInterval)tolerance
{
    CFRunLoopTimerSetTolerance((__bridge CFRunLoopTimerRef)self, tolerance);
}

@end
