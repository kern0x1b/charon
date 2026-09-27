// The port's own ways into the model: a C function per class that rebuilds the object the store
// already holds, and the class extensions that carry an object's identity and its edge back to what
// holds it. Nothing here is a row of the surface: a C function whose name starts with `Charon` is the
// port's own, and modules/apple/backports.lua filters it out of what an object is weighed for, and a
// class extension is part of the class's own implementation rather than an addition to it.
#ifndef CHARON_HOMEKIT_INTERNAL_H
#define CHARON_HOMEKIT_INTERNAL_H

#import <Foundation/Foundation.h>
#import <HomeKit/HomeKit.h>
#import <CoreLocation/CoreLocation.h>
#import "CharonHomeKitModel.h"

NS_ASSUME_NONNULL_BEGIN

// One constructor per model class, each defined in the file that defines the class, so that an object
// can be rebuilt from the store without a public initialiser HomeKit does not have. The nil owner is
// what a freshly created object, not yet in a home, has.

HMAccessory *CharonHomeKitAccessory(NSString *identifier, NSString * _Nullable homeIdentifier);
HMAction *CharonHomeKitAction(NSString *identifier, NSString * _Nullable homeIdentifier);
HMService *CharonHomeKitService(NSString *identifier, NSString * _Nullable accessoryIdentifier);
HMCharacteristic *CharonHomeKitCharacteristic(NSString *identifier, NSString * _Nullable serviceIdentifier);
HMAccessoryCategory *CharonHomeKitAccessoryCategory(NSString *categoryType);
HMNumberRange *CharonHomeKitNumberRange(NSNumber * _Nullable minimum, NSNumber * _Nullable maximum);
HMAccessory *CharonHomeKitAccessory(NSString *identifier, NSString * _Nullable homeIdentifier);
HMAction *CharonHomeKitAction(NSString *identifier, NSString * _Nullable homeIdentifier);
HMService *CharonHomeKitService(NSString *identifier, NSString * _Nullable accessoryIdentifier);
HMCharacteristic *CharonHomeKitCharacteristic(NSString *identifier, NSString * _Nullable serviceIdentifier);
HMAccessoryCategory *CharonHomeKitAccessoryCategory(NSString *categoryType);
HMNumberRange *CharonHomeKitNumberRange(NSNumber * _Nullable minimum, NSNumber * _Nullable maximum);

// The characteristic metadata belongs to the characteristic and has no identifier of its own, so it is
// built from that characteristic's record rather than from a stored one of its own.
HMCharacteristicMetadata *CharonHomeKitCharacteristicMetadataForRecord(NSMutableDictionary *record);

// The localized description of an accessory category type, or nil for a type this framework does not
// know: an application that asks about a type the release has never heard of gets nil, not a name.
NSString * _Nullable CharonHomeKitAccessoryCategoryDescription(NSString * _Nullable categoryType);

@interface HMAccessoryCategory () @property (nonatomic, copy, nullable) NSString *charon_categoryType; @end
@interface HMNumberRange () @property (nonatomic, strong, nullable) NSNumber *charon_minValue;
@property (nonatomic, strong, nullable) NSNumber *charon_maxValue; @end
@interface HMAccessory () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier;
@property (nonatomic, weak, nullable) id<HMAccessoryDelegate> charon_delegate; @end
@interface HMAction () @property (nonatomic, copy) NSString *charon_identifier; @end
@interface HMService () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_accessoryIdentifier; @end
@interface HMCharacteristic () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_serviceIdentifier; @end
@interface HMCharacteristicMetadata () @property (nonatomic, strong) NSMutableDictionary *charon_record; @end
@interface HMCharacteristicWriteAction () @property (nonatomic, strong, nullable) HMCharacteristic *charon_characteristic;
@property (nonatomic, strong, nullable) id charon_targetValue; @end

// What a graph edge needs written, named after the edge rather than after the class that reads it.
@interface HMAccessory (CharonHomeKitStore)
- (void)charon_setHomeIdentifier:(NSString * _Nullable)homeIdentifier;
- (void)charon_setRoom:(NSString * _Nullable)roomIdentifier;
- (void)charon_setServiceIdentifiers:(NSArray<NSString *> *)identifiers;
@end
@interface HMService (CharonHomeKitStore)
- (void)charon_setAccessoryIdentifier:(NSString * _Nullable)accessoryIdentifier;
- (void)charon_setCharacteristicIdentifiers:(NSArray<NSString *> *)identifiers;
@end
@interface HMCharacteristic (CharonHomeKitStore)
- (void)charon_setServiceIdentifier:(NSString * _Nullable)serviceIdentifier;
- (void)charon_setValue:(id)value;
- (void)charon_setProperties:(NSArray<NSString *> *)properties;
@end

NS_ASSUME_NONNULL_END

#endif
