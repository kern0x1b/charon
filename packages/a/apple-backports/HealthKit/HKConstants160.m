// The 145 exported string constants the held ladder first sees exported by iOS 16.0.
//
// They arrive in ten releases by their own headers - 12.2 (4), 13.0 (16), 13.6 (33), 14.0 (29), 14.2 (2),
// 14.3 (6), 14.5 (1), 15.0 (7), 15.4 (6) and 16.0 (39) - and two more that the headers mark 26.0. They are
// one object because an object carries the API of one release, and the release is measured rather than
// read off a header: `dyld.first_releases()` over the held ladder, which is what
// modules/apple/backports.lua's releases_in() asks and what tools/release-split.lua makes, answers 16.0 for
// every one of the 145. The ladder holds 53 rungs and the two rungs after 12.0 are 16.0 and 18.0, so there
// is no held release between 12.0 and 16.0 to answer for any of them: the 12.0 image is the rung before and
// does not export them, the 16.0 image is the rung after and does. The answer was taken twice, from
// `xmake l tools/symbol-first-release.lua` with the build SDK's own .tbd owner filter and from
// `python3 tools/cache-index/first-rung.py` over the same ladder's index, and the two agree for all 145.
// Their registry rows keep the release each header names, one file per release, so ios136.json says 13.6
// for the thirty-three that arrived in 13.6 while this object is placed at the release the ladder
// measures; the two are different questions and the facts file writes down both where they differ.
//
// The two whose header marks them 26.0 are here and not with the other seven of that release:
// HKMedicationDoseEventTypeIdentifierMedicationDoseEvent and HKPredicateKeyPathStatus. Both are exported by
// the 16.0 image and both are declared by the 26.2 header with API_AVAILABLE(ios(26.0)) - HKTypeIdentifiers.h:338
// and HKMedicationDoseEvent.h:104 - while neither is declared by the 16.4 build SDK's headers, so for these
// two the header has no date before 26.0 to give and the image has the only earlier one. Their rows are
// filed in ios260.json with the 26.0 their headers say, and putting them in the 26.0 object beside the
// other seven would give that object two releases, which the release check refuses.
//
// 44 of the 145 hold a value that is not their own name - a predicate key path, a metadata key, a FHIR
// resource type or release, a verifiable-record credential type - so a value spelled from the constant's
// name would be wrong for them. Every value is Apple's own, read out of the host's HealthKit and recorded
// per constant in coordination/corpus/ledger/constant-values-HealthKit.tsv: 386 rows, each a dlsym through
// CFStringGetCString as UTF-8 out of /System/Library/Frameworks/HealthKit.framework/HealthKit on
// macOS 26A428, with that binary and that build on every row. All 145 are declared by the 26.2 header and
// the corpus ledger's `introduced` agrees with the header's own availability for all 145.
//
// The C type each definition carries is the typedef the 16.4 build SDK declares for it, so a caller that
// compiles against the same header reads the declaration it expects. Two of the ten typedefs this file's
// constants use are not in that SDK - HKScoredAssessmentTypeIdentifier (18.0) and HKHealthConceptDomain
// (26.0) - so the three constants of those two types are spelled `NSString * const`, which is exactly what
// those typedefs expand to: `typedef NSString * HKScoredAssessmentTypeIdentifier NS_STRING_ENUM` at
// HKTypeIdentifiers.h:296 of 26.2, and `typedef NSString * HKHealthConceptDomain NS_TYPED_ENUM
// API_AVAILABLE(ios(26.0), ...)` at HKHealthConceptIdentifier.h:20 of 26.2. No declaration is invented here.

#import <HealthKit/HealthKit.h>

HKCategoryTypeIdentifier const HKCategoryTypeIdentifierAbdominalCramps = @"HKCategoryTypeIdentifierAbdominalCramps";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierAcne = @"HKCategoryTypeIdentifierAcne";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierAppetiteChanges = @"HKCategoryTypeIdentifierAppetiteChanges";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierAppleWalkingSteadinessEvent = @"HKCategoryTypeIdentifierAppleWalkingSteadinessEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierAudioExposureEvent = @"HKCategoryTypeIdentifierAudioExposureEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierBladderIncontinence = @"HKCategoryTypeIdentifierBladderIncontinence";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierBloating = @"HKCategoryTypeIdentifierBloating";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierBreastPain = @"HKCategoryTypeIdentifierBreastPain";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierChestTightnessOrPain = @"HKCategoryTypeIdentifierChestTightnessOrPain";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierChills = @"HKCategoryTypeIdentifierChills";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierConstipation = @"HKCategoryTypeIdentifierConstipation";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierContraceptive = @"HKCategoryTypeIdentifierContraceptive";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierCoughing = @"HKCategoryTypeIdentifierCoughing";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierDiarrhea = @"HKCategoryTypeIdentifierDiarrhea";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierDizziness = @"HKCategoryTypeIdentifierDizziness";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierDrySkin = @"HKCategoryTypeIdentifierDrySkin";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent = @"HKCategoryTypeIdentifierAudioExposureEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierFainting = @"HKCategoryTypeIdentifierFainting";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierFatigue = @"HKCategoryTypeIdentifierFatigue";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierFever = @"HKCategoryTypeIdentifierFever";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierGeneralizedBodyAche = @"HKCategoryTypeIdentifierGeneralizedBodyAche";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHairLoss = @"HKCategoryTypeIdentifierHairLoss";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHandwashingEvent = @"HKCategoryTypeIdentifierHandwashingEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHeadache = @"HKCategoryTypeIdentifierHeadache";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHeadphoneAudioExposureEvent = @"HKCategoryTypeIdentifierHeadphoneAudioExposureEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHeartburn = @"HKCategoryTypeIdentifierHeartburn";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHighHeartRateEvent = @"HKCategoryTypeIdentifierHighHeartRateEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHotFlashes = @"HKCategoryTypeIdentifierHotFlashes";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierInfrequentMenstrualCycles = @"HKCategoryTypeIdentifierInfrequentMenstrualCycles";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierIrregularHeartRhythmEvent = @"HKCategoryTypeIdentifierIrregularHeartRhythmEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierIrregularMenstrualCycles = @"HKCategoryTypeIdentifierIrregularMenstrualCycles";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierLactation = @"HKCategoryTypeIdentifierLactation";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierLossOfSmell = @"HKCategoryTypeIdentifierLossOfSmell";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierLossOfTaste = @"HKCategoryTypeIdentifierLossOfTaste";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierLowCardioFitnessEvent = @"HKCategoryTypeIdentifierLowCardioFitnessEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierLowHeartRateEvent = @"HKCategoryTypeIdentifierLowHeartRateEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierLowerBackPain = @"HKCategoryTypeIdentifierLowerBackPain";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierMemoryLapse = @"HKCategoryTypeIdentifierMemoryLapse";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierMoodChanges = @"HKCategoryTypeIdentifierMoodChanges";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierNausea = @"HKCategoryTypeIdentifierNausea";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierNightSweats = @"HKCategoryTypeIdentifierNightSweats";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierPelvicPain = @"HKCategoryTypeIdentifierPelvicPain";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierPersistentIntermenstrualBleeding = @"HKCategoryTypeIdentifierPersistentIntermenstrualBleeding";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierPregnancy = @"HKCategoryTypeIdentifierPregnancy";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierPregnancyTestResult = @"HKCategoryTypeIdentifierPregnancyTestResult";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierProgesteroneTestResult = @"HKCategoryTypeIdentifierProgesteroneTestResult";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierProlongedMenstrualPeriods = @"HKCategoryTypeIdentifierProlongedMenstrualPeriods";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat = @"HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierRunnyNose = @"HKCategoryTypeIdentifierRunnyNose";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierShortnessOfBreath = @"HKCategoryTypeIdentifierShortnessOfBreath";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierSinusCongestion = @"HKCategoryTypeIdentifierSinusCongestion";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierSkippedHeartbeat = @"HKCategoryTypeIdentifierSkippedHeartbeat";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierSleepChanges = @"HKCategoryTypeIdentifierSleepChanges";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierSoreThroat = @"HKCategoryTypeIdentifierSoreThroat";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierToothbrushingEvent = @"HKCategoryTypeIdentifierToothbrushingEvent";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierVaginalDryness = @"HKCategoryTypeIdentifierVaginalDryness";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierVomiting = @"HKCategoryTypeIdentifierVomiting";
HKCategoryTypeIdentifier const HKCategoryTypeIdentifierWheezing = @"HKCategoryTypeIdentifierWheezing";
HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierActivityMoveMode = @"HKCharacteristicTypeIdentifierActivityMoveMode";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierCoverageRecord = @"HKClinicalTypeIdentifierCoverageRecord";
NSString * const HKDataTypeIdentifierHeartbeatSeries = @"HKDataTypeIdentifierHeartbeatSeries";
HKFHIRRelease const HKFHIRReleaseDSTU2 = @"DSTU2";
HKFHIRRelease const HKFHIRReleaseR4 = @"R4";
HKFHIRRelease const HKFHIRReleaseUnknown = @"unknown";
HKFHIRResourceType const HKFHIRResourceTypeCoverage = @"Coverage";
HKFHIRResourceType const HKFHIRResourceTypeMedicationRequest = @"MedicationRequest";
NSString * const HKMedicationDoseEventTypeIdentifierMedicationDoseEvent = @"HKMedicationDoseEventTypeIdentifierMedicationDoseEvent";
NSString * const HKMetadataKeyAlgorithmVersion = @"HKAlgorithmVersion";
NSString * const HKMetadataKeyAppleDeviceCalibrated = @"HKMetadataKeyAppleDeviceCalibrated";
NSString * const HKMetadataKeyAppleECGAlgorithmVersion = @"HKMetadataKeyAppleECGAlgorithmVersion";
NSString * const HKMetadataKeyAudioExposureDuration = @"HKMetadataKeyAudioExposureDuration";
NSString * const HKMetadataKeyAudioExposureLevel = @"HKMetadataKeyAudioExposureLevel";
NSString * const HKMetadataKeyAverageMETs = @"HKAverageMETs";
NSString * const HKMetadataKeyBarometricPressure = @"HKMetadataKeyBarometricPressure";
NSString * const HKMetadataKeyDateOfEarliestDataUsedForEstimate = @"HKDateOfEarliestDataUsedForEstimate";
NSString * const HKMetadataKeyDevicePlacementSide = @"HKMetadataKeyDevicePlacementSide";
NSString * const HKMetadataKeyGlassesPrescriptionDescription = @"HKMetadataKeyGlassesPrescriptionDescription";
NSString * const HKMetadataKeyHeartRateEventThreshold = @"HKHeartRateEventThreshold";
NSString * const HKMetadataKeyHeartRateRecoveryActivityDuration = @"HKMetadataKeyHeartRateRecoveryActivityDuration";
NSString * const HKMetadataKeyHeartRateRecoveryActivityType = @"HKMetadataKeyHeartRateRecoveryActivityType";
NSString * const HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate = @"HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate";
NSString * const HKMetadataKeyHeartRateRecoveryTestType = @"HKMetadataKeyHeartRateRecoveryTestType";
NSString * const HKMetadataKeyLowCardioFitnessEventThreshold = @"HKLowCardioFitnessEventThreshold";
NSString * const HKMetadataKeyQuantityClampedToLowerBound = @"HKMetadataKeyQuantityClampedToLowerBound";
NSString * const HKMetadataKeyQuantityClampedToUpperBound = @"HKMetadataKeyQuantityClampedToUpperBound";
NSString * const HKMetadataKeySWOLFScore = @"HKSWOLFScore";
NSString * const HKMetadataKeySessionEstimate = @"HKMetadataKeySessionEstimate";
NSString * const HKMetadataKeyUserMotionContext = @"HKMetadataKeyUserMotionContext";
NSString * const HKMetadataKeyVO2MaxValue = @"HKVO2MaxValue";
NSString * const HKPredicateKeyPathAverage = @"quantity";
NSString * const HKPredicateKeyPathAverageHeartRate = @"ecg_average_heart_rate";
NSString * const HKPredicateKeyPathCount = @"count";
NSString * const HKPredicateKeyPathECGClassification = @"ecg_public_classification";
NSString * const HKPredicateKeyPathECGSymptomsStatus = @"ecg_symptoms_status";
NSString * const HKPredicateKeyPathMax = @"max";
NSString * const HKPredicateKeyPathMin = @"min";
NSString * const HKPredicateKeyPathMostRecent = @"most_recent";
NSString * const HKPredicateKeyPathMostRecentDuration = @"most_recent_duration";
NSString * const HKPredicateKeyPathMostRecentEndDate = @"most_recent_end_date";
NSString * const HKPredicateKeyPathMostRecentStartDate = @"most_recent_start_date";
NSString * const HKPredicateKeyPathStatus = @"status";
NSString * const HKPredicateKeyPathWorkoutActivity = @"workoutActivity";
NSString * const HKPredicateKeyPathWorkoutActivityAverageQuantity = @"activityAverageQuantity";
NSString * const HKPredicateKeyPathWorkoutActivityDuration = @"activityDuration";
NSString * const HKPredicateKeyPathWorkoutActivityEndDate = @"activityEndDate";
NSString * const HKPredicateKeyPathWorkoutActivityMaximumQuantity = @"activityMaximumQuantity";
NSString * const HKPredicateKeyPathWorkoutActivityMinimumQuantity = @"activityMinimumQuantity";
NSString * const HKPredicateKeyPathWorkoutActivityStartDate = @"activityStartDate";
NSString * const HKPredicateKeyPathWorkoutActivitySumQuantity = @"activitySumQuantity";
NSString * const HKPredicateKeyPathWorkoutActivityType = @"activityType";
NSString * const HKPredicateKeyPathWorkoutAverageQuantity = @"averageQuantity";
NSString * const HKPredicateKeyPathWorkoutMaximumQuantity = @"maximumQuantity";
NSString * const HKPredicateKeyPathWorkoutMinimumQuantity = @"minimumQuantity";
NSString * const HKPredicateKeyPathWorkoutSumQuantity = @"sumQuantity";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAppleMoveTime = @"HKQuantityTypeIdentifierAppleMoveTime";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAppleSleepingWristTemperature = @"HKQuantityTypeIdentifierAppleSleepingWristTemperature";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAppleStandTime = @"HKQuantityTypeIdentifierAppleStandTime";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAppleWalkingSteadiness = @"HKQuantityTypeIdentifierAppleWalkingSteadiness";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAtrialFibrillationBurden = @"HKQuantityTypeIdentifierAtrialFibrillationBurden";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierEnvironmentalAudioExposure = @"HKQuantityTypeIdentifierEnvironmentalAudioExposure";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierEnvironmentalSoundReduction = @"HKQuantityTypeIdentifierEnvironmentalSoundReduction";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierHeadphoneAudioExposure = @"HKQuantityTypeIdentifierHeadphoneAudioExposure";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierHeartRateRecoveryOneMinute = @"HKQuantityTypeIdentifierHeartRateRecoveryOneMinute";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierNumberOfAlcoholicBeverages = @"HKQuantityTypeIdentifierNumberOfAlcoholicBeverages";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRunningGroundContactTime = @"HKQuantityTypeIdentifierRunningGroundContactTime";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRunningPower = @"HKQuantityTypeIdentifierRunningPower";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRunningSpeed = @"HKQuantityTypeIdentifierRunningSpeed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRunningStrideLength = @"HKQuantityTypeIdentifierRunningStrideLength";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierRunningVerticalOscillation = @"HKQuantityTypeIdentifierRunningVerticalOscillation";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierSixMinuteWalkTestDistance = @"HKQuantityTypeIdentifierSixMinuteWalkTestDistance";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierStairAscentSpeed = @"HKQuantityTypeIdentifierStairAscentSpeed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierStairDescentSpeed = @"HKQuantityTypeIdentifierStairDescentSpeed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierUnderwaterDepth = @"HKQuantityTypeIdentifierUnderwaterDepth";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWalkingAsymmetryPercentage = @"HKQuantityTypeIdentifierWalkingAsymmetryPercentage";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWalkingDoubleSupportPercentage = @"HKQuantityTypeIdentifierWalkingDoubleSupportPercentage";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWalkingSpeed = @"HKQuantityTypeIdentifierWalkingSpeed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWalkingStepLength = @"HKQuantityTypeIdentifierWalkingStepLength";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierWaterTemperature = @"HKQuantityTypeIdentifierWaterTemperature";
HKVerifiableClinicalRecordCredentialType const HKVerifiableClinicalRecordCredentialTypeCOVID19 = @"https://smarthealth.cards#covid19";
HKVerifiableClinicalRecordCredentialType const HKVerifiableClinicalRecordCredentialTypeImmunization = @"https://smarthealth.cards#immunization";
HKVerifiableClinicalRecordCredentialType const HKVerifiableClinicalRecordCredentialTypeLaboratory = @"https://smarthealth.cards#laboratory";
HKVerifiableClinicalRecordCredentialType const HKVerifiableClinicalRecordCredentialTypeRecovery = @"https://smarthealth.cards#recovery";
HKVerifiableClinicalRecordSourceType const HKVerifiableClinicalRecordSourceTypeEUDigitalCOVIDCertificate = @"EUDigitalCOVIDCertificate";
HKVerifiableClinicalRecordSourceType const HKVerifiableClinicalRecordSourceTypeSMARTHealthCard = @"SMARTHealthCard";
NSString * const HKVisionPrescriptionTypeIdentifier = @"HKVisionPrescriptionTypeIdentifier";
