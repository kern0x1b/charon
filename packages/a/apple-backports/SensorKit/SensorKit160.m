#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 16.0, the classes that arrived then: an object carries API of one release, so
// these are apart from 16.4's.
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
