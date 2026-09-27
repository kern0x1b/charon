// HMAction, of iOS 8.0: what an action set holds. It is the base of the one action HomeKit names --
// HMCharacteristicWriteAction, which writes a value to a characteristic -- and carries the identifier
// the set's own list of actions is keyed by.
//
// One release's API per object file, which is what the band machinery needs.
#import "CharonHomeKitInternal.h"

@implementation HMAction
@synthesize charon_identifier = _charon_identifier;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _charon_identifier = [CharonHomeKitNewIdentifier() copy];
        CharonHomeKitRecord(@"actions", _charon_identifier);
    }
    return self;
}

- (NSString *)uniqueIdentifier
{
    return _charon_identifier;
}

@end

HMAction *CharonHomeKitAction(NSString *identifier, NSString *homeIdentifier)
{
    HMAction *action = [[HMAction alloc] init];
    action.charon_identifier = identifier;
    return action;
}
