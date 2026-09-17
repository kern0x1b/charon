#import <Foundation/Foundation.h>
#import <objc/runtime.h>

double charon_thread_priority_for_quality(NSQualityOfService quality);

static char CharonOperationQualityKey;

@implementation NSOperation (CharonQualityOfService)

- (NSQualityOfService)qualityOfService
{
    NSNumber *quality = objc_getAssociatedObject(self, &CharonOperationQualityKey);
    return quality ? (NSQualityOfService)quality.integerValue : NSQualityOfServiceDefault;
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService
{
    objc_setAssociatedObject(self, &CharonOperationQualityKey, @(qualityOfService), OBJC_ASSOCIATION_RETAIN);
    self.threadPriority = charon_thread_priority_for_quality(qualityOfService);
}

@end
