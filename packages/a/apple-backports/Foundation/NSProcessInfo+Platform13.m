#import <Foundation/Foundation.h>

/* The three flags that say which kind of Apple platform the process is running on, and the low power
   mode. Every one of them answers NO on the port's own release, and that is the whole answer rather
   than a stub: an iPhone 4S is not a Mac, not a Mac Catalyst app and not a Vision Pro app, and iOS
   6.1.3 has no low power mode to be in -- the mode arrived with iOS 9 and the hardware it needs with
   iPhone 6, so on this release the honest answer is the same one a device without the feature gives. */

@implementation NSProcessInfo (CharonPlatform)

- (BOOL)iOSAppOnMac
{
    return NO;
}

- (BOOL)macCatalystApp
{
    return NO;
}

- (BOOL)iOSAppOnVision
{
    return NO;
}

- (BOOL)lowPowerModeEnabled
{
    return NO;
}

@end
