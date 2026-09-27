// HMAccessoryCategory, of iOS 9.0: what an accessory's category is, by type.
//
// **What is not here, and why.** -localizedDescription is a localized string: the value the release
// returns is the one its own localization table holds for the running language, not a fixed English
// name. The host has no HomeKit in its dyld cache and no release on this machine ships a HomeKit
// resource bundle this port could read, so there is nothing to read the value from, and a name written
// here would be one no release ships -- a value that looks right and describes nothing. The property
// is registered absent with that reason rather than answered with a guess. See
// facts/HomeKit/HMAccessoryCategory.md.
#import "CharonHomeKitInternal.h"

@implementation HMAccessoryCategory

@synthesize charon_categoryType = _charon_categoryType;

- (instancetype)init
{
    self = [super init];
    return self;
}

- (NSString *)categoryType
{
    return [self.charon_categoryType copy];
}

@end

HMAccessoryCategory *CharonHomeKitAccessoryCategory(NSString *categoryType)
{
    HMAccessoryCategory *category = [[HMAccessoryCategory alloc] init];
    category.charon_categoryType = categoryType;
    return category;
}
