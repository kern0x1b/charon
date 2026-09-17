#import <Foundation/Foundation.h>

double charon_thread_priority_for_quality(NSQualityOfService quality)
{
    switch (quality) {
    case NSQualityOfServiceUserInteractive:
        return 1.0;
    case NSQualityOfServiceUserInitiated:
        return 0.75;
    case NSQualityOfServiceUtility:
        return 0.35;
    case NSQualityOfServiceBackground:
        return 0.0;
    default:
        return 0.5;
    }
}

NSQualityOfService charon_quality_for_thread_priority(double priority)
{
    if (priority >= 1.0)
        return NSQualityOfServiceUserInteractive;
    if (priority > 0.5)
        return NSQualityOfServiceUserInitiated;
    if (priority == 0.5)
        return NSQualityOfServiceDefault;
    if (priority > 0.0)
        return NSQualityOfServiceUtility;
    return NSQualityOfServiceBackground;
}
