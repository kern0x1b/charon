#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static char CharonQueueQualityKey;
static char CharonQueueUnderlyingKey;

static void charon_note_queue_scheduling(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSLog(@"an NSOperationQueue of iOS 6 runs its operations on threads of its own: the quality of service and the underlying queue of iOS 8 are remembered but do not steer that scheduling");
    });
}

@implementation NSOperationQueue (CharonQualityOfService)

- (NSQualityOfService)qualityOfService
{
    NSNumber *quality = objc_getAssociatedObject(self, &CharonQueueQualityKey);
    return quality ? (NSQualityOfService)quality.integerValue : NSQualityOfServiceDefault;
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService
{
    charon_note_queue_scheduling();
    objc_setAssociatedObject(self, &CharonQueueQualityKey, @(qualityOfService), OBJC_ASSOCIATION_RETAIN);
}

- (dispatch_queue_t)underlyingQueue
{
    return objc_getAssociatedObject(self, &CharonQueueUnderlyingKey);
}

- (void)setUnderlyingQueue:(dispatch_queue_t)underlyingQueue
{
    charon_note_queue_scheduling();
    objc_setAssociatedObject(self, &CharonQueueUnderlyingKey, underlyingQueue, OBJC_ASSOCIATION_RETAIN);
}

@end
