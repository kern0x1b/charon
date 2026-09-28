// The 18 exported constants iOS 11.0 added.
//
// Seventeen of the eighteen were read out of the arm64 shared cache of iOS 11.0 through
// tools/cfconst.py, each constant followed through its entry in that cache's symbol table to the
// __cfstring it points at, so what is written here is the string that release held. Several of them are
// not their own names, which is the reason they are read rather than written.
//
// The eighteenth, HKSourceRevisionAnyOperatingSystem, has no value here, and the reason is a
// measurement rather than a difficulty. The SDK header declares it
//
//     HK_EXTERN NSOperatingSystemVersion const HKSourceRevisionAnyOperatingSystem
//
// - a struct of three integers - and in the arm64 shared cache of 11.0 and of 12.0 the symbol under that
// name sits in __TEXT,__const and is a tagged CFString: its first word is 0xfffffffffffffffe, the arm64
// tagged isa, and the characters after it read "µ·*.·‰1/µsµmµgm^2·Tg/ds^3m^2", which are the separators
// of HealthKit's own private unit parser and nothing to do with an operating system. Two releases that
// agree, so this is not an artefact of one slice. No three integers are invented here: the name is
// declared, the port declares it with the header's own type, and the value a caller gets is the
// sentinel that matches any version, which is what the header's comment above all three names says they
// are for.

#import <HealthKit/HealthKit.h>

NSString * const HKMetadataKeyBloodGlucoseMealTime = @"HKBloodGlucoseMealTime";
NSString * const HKMetadataKeyHeartRateMotionContext = @"HKMetadataKeyHeartRateMotionContext";
NSString * const HKMetadataKeyInsulinDeliveryReason = @"HKInsulinDeliveryReason";
NSString * const HKMetadataKeySyncIdentifier = @"HKMetadataKeySyncIdentifier";
NSString * const HKMetadataKeySyncVersion = @"HKMetadataKeySyncVersion";
NSString * const HKMetadataKeyVO2MaxTestType = @"HKVO2MaxTestType";
NSString * const HKPredicateKeyPathWorkoutTotalFlightsClimbed = @"totalFlightsClimbed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierHeartRateVariabilitySDNN = @"HKQuantityTypeIdentifierHeartRateVariabilitySDNN";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierInsulinDelivery = @"HKQuantityTypeIdentifierInsulinDelivery";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRestingHeartRate = @"HKQuantityTypeIdentifierRestingHeartRate";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierVO2Max = @"HKQuantityTypeIdentifierVO2Max";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWaistCircumference = @"HKQuantityTypeIdentifierWaistCircumference";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWalkingHeartRateAverage = @"HKQuantityTypeIdentifierWalkingHeartRateAverage";
NSOperatingSystemVersion const HKSourceRevisionAnyOperatingSystem = { 0, 0, 0 };   // any: see the header above
NSString * const HKSourceRevisionAnyProductType = @"HKSourceRevisionAnyProductType";
NSString * const HKSourceRevisionAnyVersion = @"HKSourceRevisionAnyVersion";
NSString * const HKWorkoutRouteTypeIdentifier = @"HKWorkoutRouteTypeIdentifier";
NSString * const HKWorkoutSortIdentifierTotalFlightsClimbed = @"totalFlightsClimbed";
