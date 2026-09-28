// The 20 exported constants iOS 10.0 added, with the values HealthKit gave them.
//
// Read out of the arm64 shared cache of iOS 10.0.1, the first HealthKit image this workspace holds
// that has all of them: there is no 10.0 or 10.0.1 armv7 cache, and the armv7s slice's data pointers are
// tagged, so the 32-bit reader cannot read that one. The readers are tools/cfconst/cache32.py for an
// image already extracted, and tools/cfconst.py for a cache:
//
//   REL=10.0.1 ARCH=arm64 IMAGE=HealthKit OUT=$PWD/HK-10.0-arm64  xmake l <the extraction>
//   python3 tools/cfconst.py ~/.charon/dyld/10.0.1/dyld_shared_cache_arm64 \
//       /System/Library/Frameworks/HealthKit.framework/HealthKit _HKDocumentTypeIdentifierCDA
//
// Twelve of the twenty hold a string that is not their own name, which is the reason the values are
// read rather than written, and they are: HKMetadataKeyLapLength is "HKLapLength",
// HKMetadataKeyWeatherCondition is "HKWeatherCondition", HKMetadataKeyWeatherHumidity and
// HKMetadataKeyWeatherTemperature are "HKWeatherHumidity" and "HKWeatherTemperature",
// HKMetadataKeySwimmingLocationType and HKMetadataKeySwimmingStrokeStyle are
// "HKSwimmingLocationType" and "HKSwimmingStrokeStyle", HKPredicateKeyPathCDAAuthorName,
// HKPredicateKeyPathCDACustodianName and HKPredicateKeyPathCDAPatientName are "author_name",
// "custodian_name" and "patient_name", HKPredicateKeyPathCDATitle is "title", and
// HKPredicateKeyPathWorkoutTotalSwimmingStrokeCount and HKWorkoutSortIdentifierTotalSwimmingStrokeCount
// are both "totalSwimmingStrokeCount". The other eight hold their own names, among them
// HKDocumentTypeIdentifierCDA, which holds "HKDocumentTypeIdentifierCDA" - three sources agree on that
// one, the image, the host's own dlsym and this line, and an earlier version of this comment claimed
// otherwise.
//
// The declaration of each is the SDK's own.

#import <HealthKit/HealthKit.h>

HKCategoryTypeIdentifier const HKCategoryTypeIdentifierMindfulSession = @"HKCategoryTypeIdentifierMindfulSession";
HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierWheelchairUse = @"HKCharacteristicTypeIdentifierWheelchairUse";
NSString * const HKDetailedCDAValidationErrorKey = @"HKDetailedCDAValidationErrorKey";
HKDocumentTypeIdentifier const HKDocumentTypeIdentifierCDA = @"HKDocumentTypeIdentifierCDA";
NSString * const HKMetadataKeyLapLength = @"HKLapLength";
NSString * const HKMetadataKeySwimmingLocationType = @"HKSwimmingLocationType";
NSString * const HKMetadataKeySwimmingStrokeStyle = @"HKSwimmingStrokeStyle";
NSString * const HKMetadataKeyWeatherCondition = @"HKWeatherCondition";
NSString * const HKMetadataKeyWeatherHumidity = @"HKWeatherHumidity";
NSString * const HKMetadataKeyWeatherTemperature = @"HKWeatherTemperature";
NSString * const HKPredicateKeyPathCDAAuthorName = @"author_name";
NSString * const HKPredicateKeyPathCDACustodianName = @"custodian_name";
NSString * const HKPredicateKeyPathCDAPatientName = @"patient_name";
NSString * const HKPredicateKeyPathCDATitle = @"title";
NSString * const HKPredicateKeyPathWorkoutTotalSwimmingStrokeCount = @"totalSwimmingStrokeCount";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDistanceSwimming = @"HKQuantityTypeIdentifierDistanceSwimming";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDistanceWheelchair = @"HKQuantityTypeIdentifierDistanceWheelchair";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierPushCount = @"HKQuantityTypeIdentifierPushCount";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierSwimmingStrokeCount = @"HKQuantityTypeIdentifierSwimmingStrokeCount";
NSString * const HKWorkoutSortIdentifierTotalSwimmingStrokeCount = @"totalSwimmingStrokeCount";
