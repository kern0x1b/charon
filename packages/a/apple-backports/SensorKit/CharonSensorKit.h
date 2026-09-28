#ifndef CHARON_SENSORKIT_H
#define CHARON_SENSORKIT_H

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <SensorKit/SensorKit.h>

// What the lowered 16.4 SDK this package builds against cannot name, written out here so that an
// application compiled against SDK 26.2 finds the classes and the types it expects.
//
// SensorKit arrived in iOS 14 and the build's SDK is four minor versions behind the one this package
// develops against, so nineteen of the framework's thirty-eight classes are absent from those headers
// and twenty-five of its property types are absent with them: the string enumerations SensorKit names
// its values with, the option masks, the one plain typedef, and the one struct. Each is spelled here as
// the SDK 26.2 header spells it - the same superclass, the same selector, the same property name and
// type, no ivars - and the availability annotations are left out, which is what the other three
// redeclarations in this package do (CharonMetricKit.h, CharonSecurityUI.h, CharonAVAudioBuffer.h):
// they would be refused against this deployment target and they mean nothing in a translation unit that
// is not an application's.
//
// No header text is copied here and no enumerator is invented. A value of one of the enumerations is
// produced by the system reading a sensor, and there is no system here that does that, so the port never
// has to name one; an application that receives a value from a payload and puts it in one of these
// properties carries the value with it, and the property's type is what the header promises.

NS_ASSUME_NONNULL_BEGIN

// MARK: - The twenty-five types the build's SDK does not declare

// The one plain typedef: a time in seconds since the reference date, which is what CFAbsoluteTime is.
typedef CFTimeInterval SRAbsoluteTime;

// The one struct: a chromaticity reading as the two coordinates the sensor reports.
typedef struct {
    Float32 x;
    Float32 y;
} SRAmbientLightChromaticity;

// The string enumerations, in the order the headers declare them.
typedef NSString *SRSensor;
typedef NSString *SRAmbientLightSensorPlacement;
typedef NSString *SRAuthorizationStatus;
typedef NSString *SRCrownOrientation;
typedef NSString *SRDeletionReason;
typedef NSString *SRLocationCategory;
typedef NSString *SRMediaEventType;
typedef NSString *SRNotificationEvent;
typedef NSString *SRTextInputSessionType;
typedef NSString *SRWristLocation;
typedef NSString *SRAcousticSettingsSampleLifetime;
typedef NSString *SRAcousticSettingsAccessibilityBackgroundSoundsName;
typedef NSString *SRAcousticSettingsAccessibilityHeadphoneAccommodationsMediaEnhanceApplication;
typedef NSString *SRAcousticSettingsAccessibilityHeadphoneAccommodationsMediaEnhanceBoosting;
typedef NSString *SRAcousticSettingsAccessibilityHeadphoneAccommodationsMediaEnhanceTuning;

// The integer enumerations.
typedef NSInteger SRFaceMetricsContext;
typedef NSInteger SRElectrocardiogramLead;

// The option masks.
typedef NSUInteger SRElectrocardiogramDataFlags;
typedef NSUInteger SRSpeechMetricsSessionFlags;
typedef NSUInteger SRWristTemperatureCondition;

// The two session-state enumerations, which the 26.2 headers spell with their own integer type.
typedef NSInteger SRElectrocardiogramSessionGuidance;
typedef NSInteger SRElectrocardiogramSessionState;

// MARK: - The nineteen classes the build's SDK does not declare

@class SRAcousticSettingsAccessibility;
@class SRAcousticSettingsAccessibilityBackgroundSounds;
@class SRAcousticSettingsAccessibilityHeadphoneAccommodations;
@class SRAcousticSettingsMusicEQ;
@class SRAudioLevel;
@class SRElectrocardiogramSample;
@class SRElectrocardiogramSession;
@class SRFaceMetricsExpression;
@class SRPhotoplethysmogramAccelerometerSample;
@class SRPhotoplethysmogramOpticalSample;
@class SRPhotoplethysmogramSample;
@class SRSleepSession;
@class SRSpeechExpression;
@class SRWristTemperature;

// The acoustic settings: what the application asked the system to measure, and what it was told. Every
// one of these is an application-written statement rather than a reading, which is why the class exists
// at all - a port that invented readings for it would be inventing the readings.
@interface SRAcousticSettings : NSObject
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibility *accessibilitySettings;
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsMusicEQ *musicEQSettings;
@property (nonatomic, readonly, assign) SRAcousticSettingsSampleLifetime audioExposureSampleLifetime;
@property (nonatomic, readonly, assign) BOOL environmentalSoundMeasurementsEnabled;
@property (nonatomic, readonly, strong, nullable) NSNumber *headphoneSafetyAudioLevel;
@end

@interface SRAcousticSettingsAccessibility : NSObject
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibilityBackgroundSounds *backgroundSounds;
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibilityHeadphoneAccommodations *headphoneAccommodations;
@property (nonatomic, readonly, assign) double leftRightBalance;
@property (nonatomic, readonly, assign) BOOL monoAudioEnabled;
@end

@interface SRAcousticSettingsAccessibilityBackgroundSounds : NSObject
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibilityBackgroundSoundsName soundName;
@property (nonatomic, readonly, assign) BOOL enabled;
@property (nonatomic, readonly, assign) BOOL playWithMediaEnabled;
@property (nonatomic, readonly, assign) BOOL stopOnLockEnabled;
@property (nonatomic, readonly, assign) double relativeVolume;
@property (nonatomic, readonly, assign) double relativeVolumeWithMedia;
@end

@interface SRAcousticSettingsAccessibilityHeadphoneAccommodations : NSObject
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibilityHeadphoneAccommodationsMediaEnhanceApplication mediaEnhanceApplication;
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibilityHeadphoneAccommodationsMediaEnhanceBoosting mediaEnhanceBoosting;
@property (nonatomic, readonly, strong, nullable) SRAcousticSettingsAccessibilityHeadphoneAccommodationsMediaEnhanceTuning mediaEnhanceTuning;
@property (nonatomic, readonly, assign) BOOL enabled;
@end

@interface SRAcousticSettingsMusicEQ : NSObject
@property (nonatomic, readonly, assign) BOOL lateNightModeEnabled;
@property (nonatomic, readonly, assign) BOOL soundCheckEnabled;
@end

// A loudness reading over a stretch of audio, and the stretch it covers.
@interface SRAudioLevel : NSObject
@property (nonatomic, readonly, assign) double loudness;
@property (nonatomic, readonly, assign) CMTimeRange timeRange;
@end

// An electrocardiogram recording: the flags of the recording, and a channel of it.
@interface SRElectrocardiogramData : NSObject
@property (nonatomic, readonly, assign) SRElectrocardiogramDataFlags flags;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitVoltage *> *value;
@end

@interface SRElectrocardiogramSample : NSObject
@property (nonatomic, readonly, strong, nullable) SRElectrocardiogramSession *session;
@property (nonatomic, readonly, strong, nullable) NSDate *date;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitFrequency *> *frequency;
@property (nonatomic, readonly, strong, nullable) NSArray<NSNumber *> *data;
@property (nonatomic, readonly, assign) SRElectrocardiogramLead lead;
@end

@interface SRElectrocardiogramSession : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *identifier;
@property (nonatomic, readonly, assign) SRElectrocardiogramSessionState state;
@property (nonatomic, readonly, assign) SRElectrocardiogramSessionGuidance sessionGuidance;
@end

// The face metrics a TrueDepth camera reports. -faceAnchor is declared by ARKit, which this package
// does not carry, so the port has no such type to answer with and that property is registered absent
// (registry/SensorKit/ios14.json) rather than carried as a name that could only ever read nil.
@interface SRFaceMetrics : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *identifier;
@property (nonatomic, readonly, copy, nullable) NSString *version;
@property (nonatomic, readonly, copy, nullable) NSString *sessionIdentifier;
@property (nonatomic, readonly, assign) SRFaceMetricsContext context;
@property (nonatomic, readonly, strong, nullable) NSArray<SRFaceMetricsExpression *> *wholeFaceExpressions;
@property (nonatomic, readonly, strong, nullable) NSArray<SRFaceMetricsExpression *> *partialFaceExpressions;
@end

@interface SRFaceMetricsExpression : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *identifier;
@property (nonatomic, readonly, assign) double value;
@end

// The photoplethysmogram - a pulse reading from the watch's optical sensor - and its two channels.
@interface SRPhotoplethysmogramSample : NSObject
@property (nonatomic, readonly, strong, nullable) NSDate *startDate;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitTemperature *> *temperature;
@property (nonatomic, readonly, strong, nullable) NSArray<SRPhotoplethysmogramAccelerometerSample *> *accelerometerSamples;
@property (nonatomic, readonly, strong, nullable) NSArray<SRPhotoplethysmogramOpticalSample *> *opticalSamples;
@property (nonatomic, readonly, strong, nullable) NSArray<NSString *> *usage;
@property (nonatomic, readonly, assign) int64_t nanosecondsSinceStart;
@end

@interface SRPhotoplethysmogramAccelerometerSample : NSObject
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitAcceleration *> *x;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitAcceleration *> *y;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitAcceleration *> *z;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitFrequency *> *samplingFrequency;
@property (nonatomic, readonly, assign) int64_t nanosecondsSinceStart;
@end

@interface SRPhotoplethysmogramOpticalSample : NSObject
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitLength *> *samplingFrequency;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitLength *> *nominalWavelength;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitLength *> *effectiveWavelength;
@property (nonatomic, readonly, strong, nullable) NSIndexSet *activePhotodiodeIndexes;
@property (nonatomic, readonly, strong, nullable) NSArray<NSString *> *conditions;
@property (nonatomic, readonly, strong, nullable) NSNumber *backgroundNoiseOffset;
@property (nonatomic, readonly, assign) NSInteger emitter;
@property (nonatomic, readonly, assign) NSInteger signalIdentifier;
@property (nonatomic, readonly, assign) int64_t nanosecondsSinceStart;
@end

// A night of sleep, and the speech the microphone heard in it. -soundClassification is declared by
// SoundAnalysis and -speechRecognition by Speech, neither of which this package carries, so those two
// are registered absent and the rest of the class is real.
@interface SRSleepSession : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *identifier;
@property (nonatomic, readonly, strong, nullable) NSDate *startDate;
@property (nonatomic, readonly, assign) NSTimeInterval duration;
@end

@interface SRSpeechExpression : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *version;
@property (nonatomic, readonly, assign) double activation;
@property (nonatomic, readonly, assign) double confidence;
@property (nonatomic, readonly, assign) double dominance;
@property (nonatomic, readonly, assign) double mood;
@property (nonatomic, readonly, assign) double valence;
@property (nonatomic, readonly, assign) CMTimeRange timeRange;
@end

@interface SRSpeechMetrics : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *sessionIdentifier;
@property (nonatomic, readonly, strong, nullable) NSDate *timestamp;
@property (nonatomic, readonly, strong, nullable) SRAudioLevel *audioLevel;
@property (nonatomic, readonly, strong, nullable) SRSpeechExpression *speechExpression;
@property (nonatomic, readonly, assign) NSTimeInterval timeSinceAudioStart;
@property (nonatomic, readonly, assign) SRSpeechMetricsSessionFlags sessionFlags;
@end

// A wrist-temperature reading, and the session of readings that share a state. -temperatures is an
// NSEnumerator that this release has no way to produce, so the property is carried and reads nil.
@interface SRWristTemperature : NSObject
@property (nonatomic, readonly, strong, nullable) NSDate *timestamp;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitTemperature *> *value;
@property (nonatomic, readonly, strong, nullable) NSMeasurement<NSUnitTemperature *> *errorEstimate;
@property (nonatomic, readonly, assign) SRWristTemperatureCondition condition;
@end

@interface SRWristTemperatureSession : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *version;
@property (nonatomic, readonly, strong, nullable) NSDate *startDate;
@property (nonatomic, readonly, strong, nullable) NSEnumerator<SRWristTemperature *> *temperatures;
@property (nonatomic, readonly, assign) NSTimeInterval duration;
@end

NS_ASSUME_NONNULL_END

#endif
