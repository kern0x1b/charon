#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 16.0, the classes that arrived then: an object carries API of one release, so
// these are apart from 16.4's.
@implementation SRDeviceUsageReport (CharonSensorKit164)
@dynamic version;
CHARON_VALUE_PROPERTY(NSString *, version)
@end
@implementation SRKeyboardMetrics (CharonSensorKit164)
CHARON_VALUE_PROPERTY(NSArray *, sessionIdentifiers)
CHARON_VALUE_PROPERTY(SRKeyboardProbabilityMetric *, touchUpDown)
CHARON_VALUE_PROPERTY(NSArray *, longWordTouchUpDown)
@end
@implementation SRTextInputSession (CharonSensorKit164)
@dynamic sessionIdentifier;
CHARON_VALUE_PROPERTY(NSString *, sessionIdentifier)
@end
@implementation SRWristDetection (CharonSensorKit164)
@dynamic onWristDate, offWristDate;
CHARON_VALUE_PROPERTY(NSDate *, onWristDate)
CHARON_VALUE_PROPERTY(NSDate *, offWristDate)
@end
