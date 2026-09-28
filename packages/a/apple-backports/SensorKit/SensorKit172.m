#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 17.2, the properties that arrived then.
@implementation SRSpeechMetrics
@dynamic sessionIdentifier, sessionFlags, timestamp, audioLevel, speechExpression, timeSinceAudioStart;
CHARON_VALUE_PROPERTY(NSString *, sessionIdentifier)
CHARON_SCALAR_PROPERTY(SRSpeechMetricsSessionFlags, sessionFlags)
CHARON_VALUE_PROPERTY(NSDate *, timestamp)
CHARON_VALUE_PROPERTY(SRAudioLevel *, audioLevel)
CHARON_VALUE_PROPERTY(SRSpeechExpression *, speechExpression)
CHARON_SCALAR_PROPERTY(NSTimeInterval, timeSinceAudioStart)
@end
@implementation SRSpeechMetrics (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
