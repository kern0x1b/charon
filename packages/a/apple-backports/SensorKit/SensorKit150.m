#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 15.0, the properties that arrived then.
@implementation SRApplicationUsage (CharonSensorKit150)
@dynamic reportApplicationIdentifier, textInputSessions;
CHARON_VALUE_PROPERTY(NSString *, reportApplicationIdentifier)
CHARON_VALUE_PROPERTY(NSArray *, textInputSessions)
@end
@implementation SRApplicationUsage (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRKeyboardMetrics (CharonSensorKit150)
CHARON_VALUE_PROPERTY(NSArray *, inputModes)
-(NSInteger)totalPauses { NSNumber *boxed = [self charon_valueForKey:@"totalPauses"];
    return boxed ? (NSInteger)[boxed longLongValue] : (NSInteger)0; }
-(void)charon_setTotalPauses:(NSInteger)value { [self charon_setValue:@(value) forKey:@"totalPauses"]; }
-(NSInteger)totalPathPauses { NSNumber *boxed = [self charon_valueForKey:@"totalPathPauses"];
    return boxed ? (NSInteger)[boxed longLongValue] : (NSInteger)0; }
-(void)charon_setTotalPathPauses:(NSInteger)value { [self charon_setValue:@(value) forKey:@"totalPathPauses"]; }
-(double)typingSpeed { NSNumber *boxed = [self charon_valueForKey:@"typingSpeed"];
    return boxed ? (double)[boxed longLongValue] : (double)0; }
-(void)charon_setTypingSpeed:(double)value { [self charon_setValue:@(value) forKey:@"typingSpeed"]; }
-(double)pathTypingSpeed { NSNumber *boxed = [self charon_valueForKey:@"pathTypingSpeed"];
    return boxed ? (double)[boxed longLongValue] : (double)0; }
-(void)charon_setPathTypingSpeed:(double)value { [self charon_setValue:@(value) forKey:@"pathTypingSpeed"]; }
-(NSInteger)totalTypingEpisodes { NSNumber *boxed = [self charon_valueForKey:@"totalTypingEpisodes"];
    return boxed ? (NSInteger)[boxed longLongValue] : (NSInteger)0; }
-(void)charon_setTotalTypingEpisodes:(NSInteger)value { [self charon_setValue:@(value) forKey:@"totalTypingEpisodes"]; }
@end
@implementation SRTextInputSession
@dynamic duration, sessionType;
CHARON_SCALAR_PROPERTY(NSTimeInterval, duration)
CHARON_SCALAR_PROPERTY(SRTextInputSessionType, sessionType)
@end
@implementation SRTextInputSession (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end

// The two string constants of iOS 15.0,
// declared at SRSensors.h:194 and :213,
// named from CharonSensorKitNames.h rather than written here: an object carries the API of
// one release alone, while the values are one list that the host comparison in
// tests/backports/host/sensorkit-names walks whole.

#define CHARON_SENSORKIT_NAMES_15_0
#import "CharonSensorKitNames.h"
