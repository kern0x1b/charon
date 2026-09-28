#import "CharonSensorKit.h"
#import "CharonSensorKitValue.h"
#import "../CharonValueStore.h"

// SensorKit of iOS 17.4, the properties that arrived then.
@implementation SRElectrocardiogramData
@dynamic flags, value;
CHARON_SCALAR_PROPERTY(SRElectrocardiogramDataFlags, flags)
CHARON_VALUE_PROPERTY(NSMeasurement *, value)
@end
@implementation SRElectrocardiogramData (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRElectrocardiogramSample
@dynamic date, frequency, session, lead, data;
CHARON_VALUE_PROPERTY(NSDate *, date)
CHARON_VALUE_PROPERTY(NSMeasurement *, frequency)
CHARON_VALUE_PROPERTY(SRElectrocardiogramSession *, session)
CHARON_SCALAR_PROPERTY(SRElectrocardiogramLead, lead)
CHARON_VALUE_PROPERTY(NSArray *, data)
@end
@implementation SRElectrocardiogramSample (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRElectrocardiogramSession
@dynamic state, sessionGuidance, identifier;
CHARON_SCALAR_PROPERTY(SRElectrocardiogramSessionState, state)
CHARON_SCALAR_PROPERTY(SRElectrocardiogramSessionGuidance, sessionGuidance)
CHARON_VALUE_PROPERTY(NSString *, identifier)
@end
@implementation SRElectrocardiogramSession (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRPhotoplethysmogramAccelerometerSample
@dynamic nanosecondsSinceStart, samplingFrequency, x, y, z;
CHARON_SCALAR_PROPERTY(int64_t, nanosecondsSinceStart)
CHARON_VALUE_PROPERTY(NSMeasurement *, samplingFrequency)
CHARON_VALUE_PROPERTY(NSMeasurement *, x)
CHARON_VALUE_PROPERTY(NSMeasurement *, y)
CHARON_VALUE_PROPERTY(NSMeasurement *, z)
@end
@implementation SRPhotoplethysmogramAccelerometerSample (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRPhotoplethysmogramOpticalSample
@dynamic emitter, activePhotodiodeIndexes, signalIdentifier, nominalWavelength, effectiveWavelength, samplingFrequency, nanosecondsSinceStart, backgroundNoiseOffset, conditions;
CHARON_SCALAR_PROPERTY(NSInteger, emitter)
CHARON_VALUE_PROPERTY(NSIndexSet *, activePhotodiodeIndexes)
CHARON_SCALAR_PROPERTY(NSInteger, signalIdentifier)
CHARON_VALUE_PROPERTY(NSMeasurement *, nominalWavelength)
CHARON_VALUE_PROPERTY(NSMeasurement *, effectiveWavelength)
CHARON_VALUE_PROPERTY(NSMeasurement *, samplingFrequency)
CHARON_SCALAR_PROPERTY(int64_t, nanosecondsSinceStart)
CHARON_VALUE_PROPERTY(NSNumber *, backgroundNoiseOffset)
CHARON_VALUE_PROPERTY(NSArray *, conditions)
@end
@implementation SRPhotoplethysmogramOpticalSample (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
@implementation SRPhotoplethysmogramSample
@dynamic startDate, nanosecondsSinceStart, usage, opticalSamples, accelerometerSamples, temperature;
CHARON_VALUE_PROPERTY(NSDate *, startDate)
CHARON_SCALAR_PROPERTY(int64_t, nanosecondsSinceStart)
CHARON_VALUE_PROPERTY(NSArray *, usage)
CHARON_VALUE_PROPERTY(NSArray *, opticalSamples)
CHARON_VALUE_PROPERTY(NSArray *, accelerometerSamples)
CHARON_VALUE_PROPERTY(NSMeasurement *, temperature)
@end
@implementation SRPhotoplethysmogramSample (CharonSensorKitValue)
CHARON_SENSORKIT_VALUE_STORE_IMPLEMENTATION
@end
