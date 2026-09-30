// The twenty-one exported constants of iOS 12.0.
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
