// The 110 exported constants iOS 8 added, with the values HealthKit itself gave them.
//
// Every value below was read out of the armv7 shared cache of iOS 8.0, not assumed: the image was
// extracted with modules/apple/dyld.lua's extract() and each constant followed through its entry in
// the image's own symbol table to the __cfstring that entry points at, so what is written here is
// the string that release held (~/.charon/dyld/8.0/dyld_shared_cache_armv7, HealthKit.framework).
// The reader is .agent-work/runs/api-kits/cfconst32.py and its output hk8.0.constvalues. A name
// iOS 8.0 exported that the SDK headers do not declare is Apple's private and is not here; a name
// the SDK declares that iOS 8.0 did not have came later and is carried in the group of its own
// release. The declaration of each is the SDK's own.

#import <HealthKit/HealthKit.h>

HKCategoryTypeIdentifier const HKCategoryTypeIdentifierSleepAnalysis = @"HKCategoryTypeIdentifierSleepAnalysis";
HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierBiologicalSex = @"HKCharacteristicTypeIdentifierBiologicalSex";
HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierBloodType = @"HKCharacteristicTypeIdentifierBloodType";
HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierDateOfBirth = @"HKCharacteristicTypeIdentifierDateOfBirth";
HKCorrelationTypeIdentifier const HKCorrelationTypeIdentifierBloodPressure = @"HKCorrelationTypeIdentifierBloodPressure";
HKCorrelationTypeIdentifier const HKCorrelationTypeIdentifierFood = @"HKCorrelationTypeIdentifierFood";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierActiveEnergyBurned = @"HKQuantityTypeIdentifierActiveEnergyBurned";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBasalEnergyBurned = @"HKQuantityTypeIdentifierBasalEnergyBurned";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBloodAlcoholContent = @"HKQuantityTypeIdentifierBloodAlcoholContent";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBloodGlucose = @"HKQuantityTypeIdentifierBloodGlucose";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBloodPressureDiastolic = @"HKQuantityTypeIdentifierBloodPressureDiastolic";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBloodPressureSystolic = @"HKQuantityTypeIdentifierBloodPressureSystolic";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBodyFatPercentage = @"HKQuantityTypeIdentifierBodyFatPercentage";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBodyMass = @"HKQuantityTypeIdentifierBodyMass";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBodyMassIndex = @"HKQuantityTypeIdentifierBodyMassIndex";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierBodyTemperature = @"HKQuantityTypeIdentifierBodyTemperature";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryBiotin = @"HKQuantityTypeIdentifierDietaryBiotin";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryCaffeine = @"HKQuantityTypeIdentifierDietaryCaffeine";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryCalcium = @"HKQuantityTypeIdentifierDietaryCalcium";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryCarbohydrates = @"HKQuantityTypeIdentifierDietaryCarbohydrates";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryChloride = @"HKQuantityTypeIdentifierDietaryChloride";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryCholesterol = @"HKQuantityTypeIdentifierDietaryCholesterol";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryChromium = @"HKQuantityTypeIdentifierDietaryChromium";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryCopper = @"HKQuantityTypeIdentifierDietaryCopper";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryEnergyConsumed = @"HKQuantityTypeIdentifierDietaryEnergyConsumed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryFatMonounsaturated = @"HKQuantityTypeIdentifierDietaryFatMonounsaturated";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryFatPolyunsaturated = @"HKQuantityTypeIdentifierDietaryFatPolyunsaturated";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryFatSaturated = @"HKQuantityTypeIdentifierDietaryFatSaturated";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryFatTotal = @"HKQuantityTypeIdentifierDietaryFatTotal";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryFiber = @"HKQuantityTypeIdentifierDietaryFiber";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryFolate = @"HKQuantityTypeIdentifierDietaryFolate";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryIodine = @"HKQuantityTypeIdentifierDietaryIodine";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryIron = @"HKQuantityTypeIdentifierDietaryIron";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryMagnesium = @"HKQuantityTypeIdentifierDietaryMagnesium";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryManganese = @"HKQuantityTypeIdentifierDietaryManganese";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryMolybdenum = @"HKQuantityTypeIdentifierDietaryMolybdenum";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryNiacin = @"HKQuantityTypeIdentifierDietaryNiacin";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryPantothenicAcid = @"HKQuantityTypeIdentifierDietaryPantothenicAcid";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryPhosphorus = @"HKQuantityTypeIdentifierDietaryPhosphorus";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryPotassium = @"HKQuantityTypeIdentifierDietaryPotassium";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryProtein = @"HKQuantityTypeIdentifierDietaryProtein";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryRiboflavin = @"HKQuantityTypeIdentifierDietaryRiboflavin";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietarySelenium = @"HKQuantityTypeIdentifierDietarySelenium";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietarySodium = @"HKQuantityTypeIdentifierDietarySodium";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietarySugar = @"HKQuantityTypeIdentifierDietarySugar";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryThiamin = @"HKQuantityTypeIdentifierDietaryThiamin";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminA = @"HKQuantityTypeIdentifierDietaryVitaminA";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminB12 = @"HKQuantityTypeIdentifierDietaryVitaminB12";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminB6 = @"HKQuantityTypeIdentifierDietaryVitaminB6";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminC = @"HKQuantityTypeIdentifierDietaryVitaminC";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminD = @"HKQuantityTypeIdentifierDietaryVitaminD";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminE = @"HKQuantityTypeIdentifierDietaryVitaminE";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryVitaminK = @"HKQuantityTypeIdentifierDietaryVitaminK";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDietaryZinc = @"HKQuantityTypeIdentifierDietaryZinc";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDistanceCycling = @"HKQuantityTypeIdentifierDistanceCycling";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDistanceWalkingRunning = @"HKQuantityTypeIdentifierDistanceWalkingRunning";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierElectrodermalActivity = @"HKQuantityTypeIdentifierElectrodermalActivity";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierFlightsClimbed = @"HKQuantityTypeIdentifierFlightsClimbed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierForcedExpiratoryVolume1 = @"HKQuantityTypeIdentifierForcedExpiratoryVolume1";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierForcedVitalCapacity = @"HKQuantityTypeIdentifierForcedVitalCapacity";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierHeartRate = @"HKQuantityTypeIdentifierHeartRate";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierHeight = @"HKQuantityTypeIdentifierHeight";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierInhalerUsage = @"HKQuantityTypeIdentifierInhalerUsage";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierLeanBodyMass = @"HKQuantityTypeIdentifierLeanBodyMass";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierNikeFuel = @"HKQuantityTypeIdentifierNikeFuel";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierNumberOfTimesFallen = @"HKQuantityTypeIdentifierNumberOfTimesFallen";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierOxygenSaturation = @"HKQuantityTypeIdentifierOxygenSaturation";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierPeakExpiratoryFlowRate = @"HKQuantityTypeIdentifierPeakExpiratoryFlowRate";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierPeripheralPerfusionIndex = @"HKQuantityTypeIdentifierPeripheralPerfusionIndex";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRespiratoryRate = @"HKQuantityTypeIdentifierRespiratoryRate";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierStepCount = @"HKQuantityTypeIdentifierStepCount";
NSString *const HKErrorDomain = @"com.apple.healthkit";
NSString *const HKMetadataKeyBodyTemperatureSensorLocation = @"HKBodyTemperatureSensorLocation";
NSString *const HKMetadataKeyCoachedWorkout = @"HKCoachedWorkout";
NSString *const HKMetadataKeyDeviceManufacturerName = @"HKDeviceManufacturerName";
NSString *const HKMetadataKeyDeviceName = @"HKDeviceName";
NSString *const HKMetadataKeyDeviceSerialNumber = @"HKDeviceSerialNumber";
NSString *const HKMetadataKeyDigitalSignature = @"HKDigitalSignature";
NSString *const HKMetadataKeyExternalUUID = @"HKExternalUUID";
NSString *const HKMetadataKeyFoodType = @"HKFoodType";
NSString *const HKMetadataKeyGroupFitness = @"HKGroupFitness";
NSString *const HKMetadataKeyHeartRateSensorLocation = @"HKHeartRateSensorLocation";
NSString *const HKMetadataKeyIndoorWorkout = @"HKIndoorWorkout";
NSString *const HKMetadataKeyReferenceRangeLowerLimit = @"HKReferenceRangeLowerLimit";
NSString *const HKMetadataKeyReferenceRangeUpperLimit = @"HKReferenceRangeUpperLimit";
NSString *const HKMetadataKeyTimeZone = @"HKTimeZone";
NSString *const HKMetadataKeyUDIDeviceIdentifier = @"HKUDIDeviceIdentifier";
NSString *const HKMetadataKeyUDIProductionIdentifier = @"HKUDIProductionIdentifier";
NSString *const HKMetadataKeyWasTakenInLab = @"HKWasTakenInLab";
NSString *const HKMetadataKeyWasUserEntered = @"HKWasUserEntered";
NSString *const HKMetadataKeyWorkoutBrandName = @"HKWorkoutBrandName";
NSString *const HKPredicateKeyPathCategoryValue = @"value";
NSString *const HKPredicateKeyPathCorrelation = @"correlation";
NSString *const HKPredicateKeyPathEndDate = @"endDate";
NSString *const HKPredicateKeyPathMetadata = @"metadata";
NSString *const HKPredicateKeyPathQuantity = @"quantity";
NSString *const HKPredicateKeyPathSource = @"source";
NSString *const HKPredicateKeyPathStartDate = @"startDate";
NSString *const HKPredicateKeyPathUUID = @"UUID";
NSString *const HKPredicateKeyPathWorkout = @"workout";
NSString *const HKPredicateKeyPathWorkoutDuration = @"duration";
NSString *const HKPredicateKeyPathWorkoutTotalDistance = @"totalDistance";
NSString *const HKPredicateKeyPathWorkoutTotalEnergyBurned = @"totalEnergyBurned";
NSString *const HKPredicateKeyPathWorkoutType = @"workoutType";
NSString *const HKSampleSortIdentifierEndDate = @"HKSampleSortIdentifierEndDate";
NSString *const HKSampleSortIdentifierStartDate = @"HKSampleSortIdentifierStartDate";
NSString *const HKWorkoutSortIdentifierDuration = @"HKWorkoutSortIdentifierDuration";
NSString *const HKWorkoutSortIdentifierTotalDistance = @"HKWorkoutSortIdentifierTotalDistance";
NSString *const HKWorkoutSortIdentifierTotalEnergyBurned = @"HKWorkoutSortIdentifierTotalEnergyBurned";
NSString *const HKWorkoutTypeIdentifier = @"HKWorkoutTypeIdentifier";
