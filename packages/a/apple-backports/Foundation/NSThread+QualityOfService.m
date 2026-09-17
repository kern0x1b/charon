#import <Foundation/Foundation.h>

double charon_thread_priority_for_quality(NSQualityOfService quality);
NSQualityOfService charon_quality_for_thread_priority(double priority);

@implementation NSThread (CharonQualityOfService)

- (NSQualityOfService)qualityOfService
{
    return charon_quality_for_thread_priority(self.threadPriority);
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService
{
    self.threadPriority = charon_thread_priority_for_quality(qualityOfService);
}

@end
