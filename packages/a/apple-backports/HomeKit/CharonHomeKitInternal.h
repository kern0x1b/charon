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

HMRoom *CharonHomeKitRoom(NSString *identifier, NSString * _Nullable homeIdentifier);
HMZone *CharonHomeKitZone(NSString *identifier, NSString * _Nullable homeIdentifier);
HMUser *CharonHomeKitUser(NSString *identifier, NSString * _Nullable homeIdentifier);
HMServiceGroup *CharonHomeKitServiceGroup(NSString *identifier, NSString * _Nullable homeIdentifier);
HMHome *CharonHomeKitHome(NSString *identifier);
HMAccessory *CharonHomeKitAccessory(NSString *identifier, NSString * _Nullable homeIdentifier);
HMService *CharonHomeKitService(NSString *identifier, NSString * _Nullable accessoryIdentifier);
HMCharacteristic *CharonHomeKitCharacteristic(NSString *identifier, NSString * _Nullable serviceIdentifier);
HMActionSet *CharonHomeKitActionSet(NSString *identifier, NSString * _Nullable homeIdentifier);
HMAction *CharonHomeKitAction(NSString *identifier, NSString * _Nullable actionSetIdentifier);
HMTimerTrigger *CharonHomeKitTimerTrigger(NSString *identifier, NSString * _Nullable homeIdentifier);
HMEventTrigger *CharonHomeKitEventTrigger(NSString *identifier, NSString * _Nullable homeIdentifier);
HMEvent *CharonHomeKitEvent(NSString *identifier, NSString *kind);
HMAccessoryCategory *CharonHomeKitAccessoryCategory(NSString *categoryType);
HMAccessoryProfile *CharonHomeKitAccessoryProfile(NSString *identifier, NSString * _Nullable accessoryIdentifier);
HMCameraProfile *CharonHomeKitCameraProfile(NSString *identifier, NSString * _Nullable accessoryIdentifier);
HMHomeAccessControl *CharonHomeKitHomeAccessControl(HMHome *home, HMUser *user);

// The localized description of an accessory category type, or nil for a type this framework does not
// know: an application that asks about a type the release has never heard of gets nil, not a name.
NSString * _Nullable CharonHomeKitAccessoryCategoryDescription(NSString * _Nullable categoryType);

// The identifiers a graph edge is stored under, read off any model object.
NSString * _Nullable CharonHomeKitOwnerIdentifier(id object);

// The characteristic metadata belongs to the characteristic and has no identifier of its own, so it is
// built from that characteristic's record rather than from a stored one of its own.
HMCharacteristicMetadata *CharonHomeKitCharacteristicMetadataForRecord(NSMutableDictionary *record);

// Identity, held on the object rather than read out of the store, so that a property answers without
// touching the disk. The record holds the same identifier; the two cannot disagree, because the
// identifier is what the record is keyed by.
@interface HMRoom () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMZone () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMUser () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMServiceGroup () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMAccessory () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier;
@property (nonatomic, weak, nullable) id<HMAccessoryDelegate> charon_delegate; @end
@interface HMService () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_accessoryIdentifier; @end
@interface HMCharacteristic () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_serviceIdentifier; @end
@interface HMHome () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, weak, nullable) id<HMHomeDelegate> charon_delegate; @end
@interface HMHomeManager () @property (nonatomic, weak, nullable) id<HMHomeManagerDelegate> charon_delegate; @end
@interface HMTrigger () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMEventTrigger () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMActionSet () @property (nonatomic, copy) NSString *charon_identifier;
@property (nonatomic, copy, nullable) NSString *charon_homeIdentifier; @end
@interface HMAction () @property (nonatomic, copy) NSString *charon_identifier; @end
@interface HMEvent () @property (nonatomic, copy) NSString *charon_identifier; @end
@interface HMHomeAccessControl () @property (nonatomic, weak, nullable) HMHome *charon_home;
@property (nonatomic, strong, nullable) HMUser *charon_user; @end
@interface HMCharacteristicMetadata () @property (nonatomic, strong) NSMutableDictionary *charon_record; @end
@interface HMCharacteristicWriteAction () @property (nonatomic, strong, nullable) HMCharacteristic *charon_characteristic;
@property (nonatomic, strong, nullable) id charon_targetValue; @end
@interface HMNumberRange () @property (nonatomic, strong, nullable) NSNumber *charon_minValue;
@property (nonatomic, strong, nullable) NSNumber *charon_maxValue; @end
@interface HMDurationEvent () @property (nonatomic, strong, nullable) NSNumber *charon_duration; @end
@interface HMMutableDurationEvent () @end
@interface HMCalendarEvent () @property (nonatomic, strong, nullable) NSDateComponents *charon_fireDateComponents; @end
@interface HMMutableCalendarEvent () @end
@interface HMSignificantTimeEvent () @property (nonatomic, copy, nullable) NSString *charon_significantEvent;
@property (nonatomic, strong, nullable) NSNumber *charon_offset; @end
@interface HMMutableSignificantTimeEvent () @end
@interface HMPresenceEvent () @property (nonatomic, strong, nullable) NSNumber *charon_presenceEventType;
@property (nonatomic, strong, nullable) NSNumber *charon_presenceUserType; @end
@interface HMMutablePresenceEvent () @end
@interface HMMutableCharacteristicEvent () @end
@interface HMCharacteristicThresholdRangeEvent () @property (nonatomic, strong, nullable) HMNumberRange *charon_thresholdRange;
@property (nonatomic, strong, nullable) HMCharacteristic *charon_characteristic; @end
@interface HMMutableCharacteristicThresholdRangeEvent () @end
@interface HMAccessoryCategory () @property (nonatomic, copy, nullable) NSString *charon_categoryType; @end
HMNumberRange *CharonHomeKitNumberRange(NSNumber * _Nullable minimum, NSNumber * _Nullable maximum);

@interface HMLocationEvent () @property (nonatomic, strong, nullable) CLCircularRegion *charon_region; @end
@interface HMCharacteristicEvent () @property (nonatomic, strong, nullable) HMCharacteristic *charon_characteristic;
@property (nonatomic, strong, nullable) id charon_triggerValue; @end

// What a graph edge needs written, named after the edge rather than after the class that reads it.
@interface HMAccessory ()
- (void)charon_setHomeIdentifier:(NSString * _Nullable)homeIdentifier;
- (void)charon_setRoom:(NSString * _Nullable)roomIdentifier;
- (void)charon_setServiceIdentifiers:(NSArray<NSString *> *)identifiers;
@end
@interface HMService ()
- (void)charon_setAccessoryIdentifier:(NSString * _Nullable)accessoryIdentifier;
- (void)charon_setCharacteristicIdentifiers:(NSArray<NSString *> *)identifiers;
@end
@interface HMCharacteristic ()
- (void)charon_setServiceIdentifier:(NSString * _Nullable)serviceIdentifier;
- (void)charon_setValue:(id)value;
- (void)charon_setProperties:(NSArray<NSString *> *)properties;
@end
@interface HMHome ()
- (void)charon_addTrigger:(HMTrigger *)trigger;
- (void)charon_removeTrigger:(HMTrigger *)trigger;
- (void)charon_addActionSet:(HMActionSet *)actionSet;
- (void)charon_removeActionSet:(HMActionSet *)actionSet;
- (BOOL)charon_nameInUse:(NSString *)name;
@end
@interface HMUser () - (void)charon_setName:(NSString *)name; @end
@interface HMTimerTrigger ()
- (void)charon_applyName:(NSString * _Nullable)name;
- (void)charon_applyFireDate:(NSDate * _Nullable)fireDate;
- (void)charon_applyRecurrence:(NSDateComponents * _Nullable)recurrence;
@end
@interface HMEventTrigger ()
- (void)charon_applyName:(NSString * _Nullable)name;
- (void)charon_applyEvents:(NSArray<HMEvent *> * _Nullable)events forKey:(NSString *)key;
- (void)charon_applyPredicate:(NSPredicate * _Nullable)predicate;
- (NSArray<HMEvent *> *)charon_eventsForKey:(NSString *)key;
- (NSString *)charon_kindOfEvent:(HMEvent *)event;
@end

NS_ASSUME_NONNULL_END

#endif
