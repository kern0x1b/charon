// The fourteen exported constants of iOS 12.0 whose value is NOT the constant's own name.
//
// The 12.0 group holds twenty-one exported constants. Seven of them hold their own name, and
// 6dc5caf3 is generating every HealthKit constant of that shape from the host's own HealthKit, so they
// are not here and this group is one group short of those seven until that work lands; the registry
// file for this group says so rather than pretend the group is whole. The fourteen below are outside
// that shape - a key path or an FHIR type name rather than the constant's name - so no one generating
// from value = name will produce them, and this group has to.
//
// Each value was read out of the arm64 shared cache of iOS 12.0 through the HealthKit image's own
// symbol table with tools/cfconst.py, and the table is kept in
// .agent-work/runs/api-kits/hk12.constvalues. The declaration of each is the SDK's own.

#import <HealthKit/HealthKit.h>

HKFHIRResourceType const HKFHIRResourceTypeAllergyIntolerance = @"AllergyIntolerance";
HKFHIRResourceType const HKFHIRResourceTypeCondition = @"Condition";
HKFHIRResourceType const HKFHIRResourceTypeImmunization = @"Immunization";
HKFHIRResourceType const HKFHIRResourceTypeMedicationDispense = @"MedicationDispense";
HKFHIRResourceType const HKFHIRResourceTypeMedicationOrder = @"MedicationOrder";
HKFHIRResourceType const HKFHIRResourceTypeMedicationStatement = @"MedicationStatement";
HKFHIRResourceType const HKFHIRResourceTypeObservation = @"Observation";
HKFHIRResourceType const HKFHIRResourceTypeProcedure = @"Procedure";
NSString *const HKMetadataKeyCrossTrainerDistance = @"HKCrossTrainerDistance";
NSString *const HKMetadataKeyFitnessMachineDuration = @"HKFitnessMachineDuration";
NSString *const HKMetadataKeyIndoorBikeDistance = @"HKIndoorBikeDistance";
NSString *const HKPredicateKeyPathClinicalRecordFHIRResourceIdentifier = @"FHIRResource.identifier";
NSString *const HKPredicateKeyPathClinicalRecordFHIRResourceType = @"FHIRResource.resourceType";
NSString *const HKPredicateKeyPathSum = @"quantity";
