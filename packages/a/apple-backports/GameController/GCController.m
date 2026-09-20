#import <GameController/GameController.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation GCController

@dynamic controllerPausedHandler, attachedToDevice, snapshot, playerIndex, battery, physicalInputProfile;
@dynamic gamepad, microGamepad, extendedGamepad, motion, light, haptics;
@dynamic vendorName, productCategory, handlerQueue;

+ (NSArray *)controllers
{
    return @[];
}

+ (void)startWirelessControllerDiscoveryWithCompletionHandler:(void (^)(void))completionHandler
{
    void (^kept)(void) = [completionHandler copy];
    if (!kept)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        kept();
    });
}

+ (void)stopWirelessControllerDiscovery
{
}

@end
