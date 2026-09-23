#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

NSString *const MTLCommandBufferEncoderInfoErrorKey = @"MTLCommandBufferEncoderInfoErrorKey";

@implementation MTLCommandBufferDescriptor

- (instancetype)init
{
    if ((self = [super init]))
        self.retainedReferences = YES;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    MTLCommandBufferDescriptor *copy = [[MTLCommandBufferDescriptor alloc] init];
    copy.retainedReferences = self.retainedReferences;
    copy.errorOptions = self.errorOptions;
    return copy;
}

@end
