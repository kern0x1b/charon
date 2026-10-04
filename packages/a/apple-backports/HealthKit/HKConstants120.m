// The twenty-seven exported constants the held ladder first sees exported by iOS 12.0.
//
// Fourteen of them hold a value that is not the constant's own name - a key path, a metadata key or an
// FHIR type name - and the seven that hold their own name are the clinical type identifiers of that
// release. The value of each was read out of the arm64 shared cache of iOS 12.0 through the HealthKit
// image's own export trie, and each is what that release's image holds rather than what the name
// suggests: HKMetadataKeyCrossTrainerDistance is `HKCrossTrainerDistance`, HKPredicateKeyPathSum is
// `quantity`, and the seven identifiers hold their own names. Two controls read the same way:
// HKQuantityTypeIdentifierStepCount and HKErrorDomain answer as real strings (`com.apple.healthkit`),
// and a name the image does not export is reported by name.
//
// The reader is tools/cfconst.py, in the repository, which walks a 64-bit image of a shared cache in
// 64-bit words and masks off the flags those images carry above their address space - 0x2 in a variable
// of __DATA,__const, 0x4 in the isa of an __cfstring - because a 32-bit read of such a variable stops
// with "address ... is in no mapping". The declaration of each constant is the SDK's own, in
// HKClinicalType.h, HKFHIRResource.h, HKMetadataEnums.h and HKDefines.h of iOS 16.4 and of iOS 26.2,
// each with API_AVAILABLE(ios(12.0), ...).
//
// Six more are here than the twenty-one that release's header names, and the reason is a measurement.
// dyld.first_releases() over the held ladder answers 12.0 for six constants the headers mark 11.2 -
// HKMetadataKeyAlpineSlopeGrade, HKMetadataKeyAverageSpeed, HKMetadataKeyElevationAscended,
// HKMetadataKeyElevationDescended, HKMetadataKeyMaximumSpeed and
// HKQuantityTypeIdentifierDistanceDownhillSnowSports - because the 11.0 image is the rung before 12.0 and
// exports none of them and the 12.0 image exports all six, and an object carries the API of one release.
// Their rows are filed in ios112.json with the 11.2 their headers say. Five of the six hold a value that is
// not their own name - HKMetadataKeyAverageSpeed is `HKAverageSpeed` and HKMetadataKeyAlpineSlopeGrade is
// `HKAlpineSlopeGrade` - and each value was read out of the host's HealthKit, per constant in
// coordination/corpus/ledger/constant-values-HealthKit.tsv, rather than spelled from the name.

#import <HealthKit/HealthKit.h>

HKFHIRResourceType const HKFHIRResourceTypeAllergyIntolerance = @"AllergyIntolerance";
HKFHIRResourceType const HKFHIRResourceTypeCondition = @"Condition";
HKFHIRResourceType const HKFHIRResourceTypeImmunization = @"Immunization";
HKFHIRResourceType const HKFHIRResourceTypeMedicationDispense = @"MedicationDispense";
HKFHIRResourceType const HKFHIRResourceTypeMedicationOrder = @"MedicationOrder";
HKFHIRResourceType const HKFHIRResourceTypeMedicationStatement = @"MedicationStatement";
HKFHIRResourceType const HKFHIRResourceTypeObservation = @"Observation";
HKFHIRResourceType const HKFHIRResourceTypeProcedure = @"Procedure";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierAllergyRecord = @"HKClinicalTypeIdentifierAllergyRecord";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierConditionRecord = @"HKClinicalTypeIdentifierConditionRecord";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierImmunizationRecord = @"HKClinicalTypeIdentifierImmunizationRecord";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierLabResultRecord = @"HKClinicalTypeIdentifierLabResultRecord";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierMedicationRecord = @"HKClinicalTypeIdentifierMedicationRecord";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierProcedureRecord = @"HKClinicalTypeIdentifierProcedureRecord";
HKClinicalTypeIdentifier const HKClinicalTypeIdentifierVitalSignRecord = @"HKClinicalTypeIdentifierVitalSignRecord";
NSString *const HKMetadataKeyCrossTrainerDistance = @"HKCrossTrainerDistance";
NSString *const HKMetadataKeyFitnessMachineDuration = @"HKFitnessMachineDuration";
NSString *const HKMetadataKeyIndoorBikeDistance = @"HKIndoorBikeDistance";
NSString *const HKPredicateKeyPathClinicalRecordFHIRResourceIdentifier = @"FHIRResource.identifier";
NSString *const HKPredicateKeyPathClinicalRecordFHIRResourceType = @"FHIRResource.resourceType";
NSString *const HKPredicateKeyPathSum = @"quantity";
NSString *const HKMetadataKeyAlpineSlopeGrade = @"HKAlpineSlopeGrade";
NSString *const HKMetadataKeyAverageSpeed = @"HKAverageSpeed";
NSString *const HKMetadataKeyElevationAscended = @"HKElevationAscended";
NSString *const HKMetadataKeyElevationDescended = @"HKElevationDescended";
NSString *const HKMetadataKeyMaximumSpeed = @"HKMaximumSpeed";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierDistanceDownhillSnowSports = @"HKQuantityTypeIdentifierDistanceDownhillSnowSports";
