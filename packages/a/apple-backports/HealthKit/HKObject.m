// HKObject: the root of what the store keeps, and of what a query finds.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

@implementation HKObject {
    NSUUID *_UUID;
    HKSource *_source;
    NSDictionary *_metadata;
    HKCorrelation *_correlation;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

// The private constructor every class of this framework builds itself with. The store is its only
// caller: an HKObject is made by the process that saves it, and nowhere else, so the public -init is
// the one the header marks unavailable.
- (instancetype)charon_initWithUUID:(NSUUID *)uuid source:(HKSource *)source metadata:(NSDictionary *)metadata
{
    HKObject *fresh = [super init];
    if (fresh) {
        fresh->_UUID = [uuid copy] ?: [[NSUUID UUID] copy];
        fresh->_source = (HKSource *)[source copy];
        fresh->_metadata = [metadata copy];
    }
    return fresh;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSUUID *uuid = [coder decodeObjectOfClass:[NSUUID class] forKey:@"UUID"];
    HKSource *source = [coder decodeObjectOfClass:[HKSource class] forKey:@"source"];
    NSSet *classes = [NSSet setWithObjects:[NSString class], [NSNumber class], [NSDate class], [HKQuantity class], nil];
    NSDictionary *metadata = [coder decodeObjectOfClasses:classes forKey:@"metadata"];
    return [self charon_initWithUUID:uuid source:source metadata:metadata];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_UUID forKey:@"UUID"];
    [coder encodeObject:_source forKey:@"source"];
    [coder encodeObject:_metadata forKey:@"metadata"];
}

// A copy of an object of this class: the same facts, under the same class, with the identity the
// class keeps of its own. Every class of this framework that the store can keep answers it, so a copy
// is never the same object under another name and never a bare HKObject.
- (instancetype)charon_copyForStore
{
    return [self charon_initWithUUID:_UUID source:_source metadata:_metadata];
}

- (NSUUID *)UUID
{
    return _UUID;
}

- (HKSource *)source
{
    return _source;
}

- (NSDictionary *)metadata
{
    return _metadata;
}

// The correlation this object belongs to, which is nil for one that belongs to none. The key path
// HKPredicateKeyPathCorrelation holds - "correlation", read out of iOS 8.0's own image - is this
// path, and the store fills it in for a sample the correlated table names, so that a predicate built
// by +[HKQuery predicateForObjectsFromSource:] and its neighbours walks a real relationship instead
// of being answered by the store beside it.
- (nullable HKCorrelation *)charon_correlation
{
    return _correlation;
}

- (void)charon_setCorrelation:(nullable HKCorrelation *)correlation
{
    _correlation = correlation;
}

#pragma mark - The store

- (NSString *)charon_storeTypeIdentifier
{
    return @"";
}

- (NSInteger)charon_storeKind
{
    return 0;
}

// The archive is the release's own NSKeyedArchiver over the class's own NSSecureCoding, so what a
// row holds is exactly what the header's archiving contract writes and nothing of this port's shape.
- (NSData *)charon_storeArchive
{
    return [NSKeyedArchiver archivedDataWithRootObject:self];
}

+ (instancetype)charon_objectFromArchive:(NSData *)archive type:(HKObjectType *)type store:(CharonHKStore *)store
{
    if (!archive.length || ![self supportsSecureCoding])
        return nil;
    NSKeyedUnarchiver *coder = [[NSKeyedUnarchiver alloc] initForReadingWithData:archive];
    id object = [[self alloc] charon_objectWithCoder:coder];
    [coder finishDecoding];
    return object;
}

// -initWithCoder: is the class's own, so that a class of this framework with facts of its own reads
// them back itself; HKObject has none.
- (instancetype)charon_objectWithCoder:(NSCoder *)coder
{
    return [self initWithCoder:coder];
}

#pragma mark - Describing

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@", NSStringFromClass(self.class), _UUID.UUIDString];
}

@end
