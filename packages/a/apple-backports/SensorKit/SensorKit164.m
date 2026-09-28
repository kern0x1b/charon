#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 16.4, the properties that arrived then.
@implementation SRApplicationUsage
@dynamic supplementalCategories, relativeStartTime;
CHARON_VALUE_PROPERTY(NSArray *, supplementalCategories)
CHARON_SCALAR_PROPERTY(NSTimeInterval, relativeStartTime)
@end
@implementation SRApplicationUsage (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRDeviceUsageReport
@dynamic version;
CHARON_VALUE_PROPERTY(NSString *, version)
@end
@implementation SRDeviceUsageReport (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRKeyboardMetrics
CHARON_VALUE_PROPERTY(NSArray *, sessionIdentifiers)
CHARON_VALUE_PROPERTY(SRKeyboardProbabilityMetric *, touchUpDown)
CHARON_VALUE_PROPERTY(NSArray *, longWordTouchUpDown)
@end
@implementation SRKeyboardMetrics (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRMediaEvent
@dynamic mediaIdentifier, eventType;
CHARON_VALUE_PROPERTY(NSString *, mediaIdentifier)
CHARON_SCALAR_PROPERTY(SRMediaEventType, eventType)
@end
@implementation SRMediaEvent (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRSupplementalCategory
@dynamic identifier;
CHARON_VALUE_PROPERTY(NSString *, identifier)
@end
@implementation SRSupplementalCategory (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRTextInputSession
@dynamic sessionIdentifier;
CHARON_VALUE_PROPERTY(NSString *, sessionIdentifier)
@end
@implementation SRTextInputSession (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRWristDetection
@dynamic onWristDate, offWristDate;
CHARON_VALUE_PROPERTY(NSDate *, onWristDate)
CHARON_VALUE_PROPERTY(NSDate *, offWristDate)
@end
@implementation SRWristDetection (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
