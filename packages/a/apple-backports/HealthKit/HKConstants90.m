// The 22 exported constants iOS 9.0 added, with the values HealthKit gave them.
//
// Every value below was read out of the armv7 shared cache of iOS 9.0, not assumed: the image was extracted with
// modules/apple/dyld.lua's extract() and each constant followed through its entry in the image's own
// symbol table to the __cfstring it points at, so what is written here is the string that release
// held. The reader is .agent-work/runs/api-kits/cfconst32.py and its output hk9.0.constvalues.
//
// The declaration of each is the SDK's own.

#import <HealthKit/HealthKit.h>


NSString *const HKCategoryTypeIdentifierAppleStandHour = @"HKCategoryTypeIdentifierAppleStandHour";
NSString *const HKCategoryTypeIdentifierCervicalMucusQuality = @"HKCategoryTypeIdentifierCervicalMucusQuality";
NSString *const HKCategoryTypeIdentifierIntermenstrualBleeding = @"HKCategoryTypeIdentifierIntermenstrualBleeding";
NSString *const HKCategoryTypeIdentifierMenstrualFlow = @"HKCategoryTypeIdentifierMenstrualFlow";
NSString *const HKCategoryTypeIdentifierOvulationTestResult = @"HKCategoryTypeIdentifierOvulationTestResult";
NSString *const HKCategoryTypeIdentifierSexualActivity = @"HKCategoryTypeIdentifierSexualActivity";
NSString *const HKCharacteristicTypeIdentifierFitzpatrickSkinType = @"HKCharacteristicTypeIdentifierFitzpatrickSkinType";
NSString *const HKDevicePropertyKeyFirmwareVersion = @"HKDevicePropertyFirmwareVersion";
NSString *const HKDevicePropertyKeyHardwareVersion = @"HKDevicePropertyHardwareVersion";
NSString *const HKDevicePropertyKeyLocalIdentifier = @"HKDevicePropertyLocalIdentifier";
NSString *const HKDevicePropertyKeyManufacturer = @"HKDevicePropertyManufacturer";
NSString *const HKDevicePropertyKeyModel = @"HKDevicePropertyModel";
NSString *const HKDevicePropertyKeyName = @"HKDevicePropertyName";
NSString *const HKDevicePropertyKeySoftwareVersion = @"HKDevicePropertySoftwareVersion";
NSString *const HKDevicePropertyKeyUDIDeviceIdentifier = @"HKDevicePropertyUDIDeviceIdentifier";
NSString *const HKMetadataKeyMenstrualCycleStart = @"HKMenstrualCycleStart";
NSString *const HKMetadataKeySexualActivityProtectionUsed = @"HKSexualActivityProtectionUsed";
NSString *const HKPredicateKeyPathDevice = @"device";
NSString *const HKPredicateKeyPathSourceRevision = @"sourceRevision";
NSString *const HKQuantityTypeIdentifierBasalBodyTemperature = @"HKQuantityTypeIdentifierBasalBodyTemperature";
NSString *const HKQuantityTypeIdentifierDietaryWater = @"HKQuantityTypeIdentifierDietaryWater";
NSString *const HKQuantityTypeIdentifierUVExposure = @"HKQuantityTypeIdentifierUVExposure";
