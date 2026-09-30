#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 16.4, the properties that arrived then.
@implementation SRApplicationUsage (CharonSensorKit164)
@dynamic supplementalCategories, relativeStartTime;
CHARON_VALUE_PROPERTY(NSArray *, supplementalCategories)
CHARON_SCALAR_PROPERTY(NSTimeInterval, relativeStartTime)
@end
@implementation SRApplicationUsage (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRMediaEvent
@dynamic mediaIdentifier, eventType;
CHARON_VALUE_PROPERTY(NSString *, mediaIdentifier)
CHARON_SCALAR_PROPERTY(SRMediaEventType, eventType)
// The SDK's own header declares this class conforming, so the port owes the three archiving methods,
// and -copyWithZone: where the header says NSCopying. The archiver walks the same property list the
// representation does, through CharonValueStore's own pair, so a value archived and read back lands in
// the store under the property's own name and nothing has to be written out by hand for it.
+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    CharonValueEncode(self, coder);
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        CharonValueDecode(self, coder, CharonValueDecodableClasses(@"SR"));
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    // A value object: the copy is a new object with the same values under the same names. A copy that
    // shared the store would be two names for one value, which is the opposite of what a copy is.
    id copy = [[[self class] allocWithZone:zone] init];
    NSDictionary *values = CharonValueStore(self);
    for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id held = values[key];
        CharonValueStore(copy)[key] = [held conformsToProtocol:@protocol(NSCopying)] ? [held copy] : held;
    }
    return copy;
}

@end
@implementation SRMediaEvent (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRSupplementalCategory
@dynamic identifier;
CHARON_VALUE_PROPERTY(NSString *, identifier)
// The SDK's own header declares this class conforming, so the port owes the three archiving methods,
// and -copyWithZone: where the header says NSCopying. The archiver walks the same property list the
// representation does, through CharonValueStore's own pair, so a value archived and read back lands in
// the store under the property's own name and nothing has to be written out by hand for it.
+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    CharonValueEncode(self, coder);
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        CharonValueDecode(self, coder, CharonValueDecodableClasses(@"SR"));
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    // A value object: the copy is a new object with the same values under the same names. A copy that
    // shared the store would be two names for one value, which is the opposite of what a copy is.
    id copy = [[[self class] allocWithZone:zone] init];
    NSDictionary *values = CharonValueStore(self);
    for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id held = values[key];
        CharonValueStore(copy)[key] = [held conformsToProtocol:@protocol(NSCopying)] ? [held copy] : held;
    }
    return copy;
}

@end
@implementation SRSupplementalCategory (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end

// The single string constant of iOS 16.4,
// declared at SRSensors.h:246,
// named from CharonSensorKitNames.h rather than written here: an object carries the API of
// one release alone, while the values are one list that the host comparison in
// tests/backports/host/sensorkit-names walks whole.

#define CHARON_SENSORKIT_NAMES_16_4
#import "CharonSensorKitNames.h"
