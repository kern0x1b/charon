#import "CharonContacts.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation CNSaveRequest {
    NSMutableArray *_charonAdded;
    NSMutableArray *_charonUpdated;
    NSMutableArray *_charonDeleted;
}

@dynamic transactionAuthor, shouldRefetchContacts;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _charonAdded = [NSMutableArray array];
        _charonUpdated = [NSMutableArray array];
        _charonDeleted = [NSMutableArray array];
    }
    return self;
}

- (void)addContact:(CNMutableContact *)contact toContainerWithIdentifier:(NSString *)identifier
{
    if (contact)
        [_charonAdded addObject:@[contact, identifier ?: @""]];
}

- (void)updateContact:(CNMutableContact *)contact
{
    if (contact)
        [_charonUpdated addObject:contact];
}

- (void)deleteContact:(CNMutableContact *)contact
{
    if (contact)
        [_charonDeleted addObject:contact];
}

- (NSArray *)charon_added { return _charonAdded; }
- (NSArray *)charon_updated { return _charonUpdated; }
- (NSArray *)charon_deleted { return _charonDeleted; }

@end
