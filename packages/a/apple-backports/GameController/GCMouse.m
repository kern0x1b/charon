#import <GameController/GameController.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation GCMouse

@dynamic mouseInput, handlerQueue, vendorName, productCategory;

+ (NSArray *)mice
{
    return @[];
}

+ (GCMouse *)current
{
    return nil;
}

@end
