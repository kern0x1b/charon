#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 17.0, the properties that arrived then.
@implementation SRAudioLevel
@dynamic timeRange, loudness;
CHARON_STRUCT_PROPERTY(CMTimeRange, timeRange)
CHARON_SCALAR_PROPERTY(double, loudness)
@end
@implementation SRAudioLevel (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
// -productType is declared in the (CharonSensorKit170) category of CharonSensorKit.h, because the 16.4
// SDK does not have it, and a property a category declares is implemented in a category.
@implementation SRDevice (CharonSensorKit170)
@dynamic productType;
CHARON_VALUE_PROPERTY(NSString *, productType)
@end
@implementation SRDevice (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRFaceMetrics
@dynamic version, sessionIdentifier, context, wholeFaceExpressions, partialFaceExpressions;
CHARON_VALUE_PROPERTY(NSString *, version)
CHARON_VALUE_PROPERTY(NSString *, sessionIdentifier)
CHARON_SCALAR_PROPERTY(SRFaceMetricsContext, context)
CHARON_VALUE_PROPERTY(NSArray *, wholeFaceExpressions)
CHARON_VALUE_PROPERTY(NSArray *, partialFaceExpressions)
@end
@implementation SRFaceMetrics (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRFaceMetricsExpression
@dynamic identifier, value;
CHARON_VALUE_PROPERTY(NSString *, identifier)
CHARON_SCALAR_PROPERTY(double, value)
@end
@implementation SRFaceMetricsExpression (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRSpeechExpression
@dynamic version, timeRange, confidence, mood, valence, activation, dominance;
CHARON_VALUE_PROPERTY(NSString *, version)
CHARON_STRUCT_PROPERTY(CMTimeRange, timeRange)
CHARON_SCALAR_PROPERTY(double, confidence)
CHARON_SCALAR_PROPERTY(double, mood)
CHARON_SCALAR_PROPERTY(double, valence)
CHARON_SCALAR_PROPERTY(double, activation)
CHARON_SCALAR_PROPERTY(double, dominance)
@end
@implementation SRSpeechExpression (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRSpeechMetrics
@dynamic sessionIdentifier, sessionFlags, timestamp, audioLevel, speechExpression;
CHARON_VALUE_PROPERTY(NSString *, sessionIdentifier)
CHARON_SCALAR_PROPERTY(SRSpeechMetricsSessionFlags, sessionFlags)
CHARON_VALUE_PROPERTY(NSDate *, timestamp)
CHARON_VALUE_PROPERTY(SRAudioLevel *, audioLevel)
CHARON_VALUE_PROPERTY(SRSpeechExpression *, speechExpression)
@end
@implementation SRSpeechMetrics (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRWristTemperature
@dynamic timestamp, value, condition, errorEstimate;
CHARON_VALUE_PROPERTY(NSDate *, timestamp)
CHARON_VALUE_PROPERTY(NSMeasurement *, value)
CHARON_SCALAR_PROPERTY(SRWristTemperatureCondition, condition)
CHARON_VALUE_PROPERTY(NSMeasurement *, errorEstimate)
@end
@implementation SRWristTemperature (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRWristTemperatureSession
@dynamic startDate, duration, version, temperatures;
CHARON_VALUE_PROPERTY(NSDate *, startDate)
CHARON_SCALAR_PROPERTY(NSTimeInterval, duration)
CHARON_VALUE_PROPERTY(NSString *, version)
CHARON_VALUE_PROPERTY(NSEnumerator *, temperatures)
@end
@implementation SRWristTemperatureSession (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end

// The four string constants of iOS 17.0,
// declared at SRSensors.h:265, :276, :295 and :307,
// named from CharonSensorKitNames.h rather than written here: an object carries the API of
// one release alone, while the values are one list that the host comparison in
// tests/backports/host/sensorkit-names walks whole.

#define CHARON_SENSORKIT_NAMES_17_0
#import "CharonSensorKitNames.h"
