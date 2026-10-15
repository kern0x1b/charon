#import <Foundation/Foundation.h>

/* NEHotspotNetwork, NEHotspotConfiguration and the helper's confidence enumeration, as the iOS 26.2 SDK's
   NEHotspotNetwork.h, NEHotspotConfigurationManager.h and NEHotspotHelper.h declare them: the class, its
   properties and the (HotspotHelper) category that NEHotspotHelper.h adds to NEHotspotNetwork, with
   setConfidence: and setPassword:.

   The build resolves charon@iphoneos-sdk to 16.4, which has no NetworkExtension.h at all, so these
   declarations are this package's. The member names, the getters (isSecure, didAutoJoin, didJustJoin,
   isChosenHelper) and the availability come from those headers.

   Not declared here yet: NEHotspotEAPSettings and NEHotspotHS20Settings, and the two initializers of
   NEHotspotConfiguration that take them. NEHotspotConfigurationManager and NEHotspotHelper are not carried
   yet either: their join route is a question the coordinator rules on (facts/NetworkExtension/Hotspot.md). */
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NEHotspotNetworkSecurityType) {
    NEHotspotNetworkSecurityTypeOpen = 0,
    NEHotspotNetworkSecurityTypeWEP = 1,
    NEHotspotNetworkSecurityTypePersonal = 2,
    NEHotspotNetworkSecurityTypeEnterprise = 3,
    NEHotspotNetworkSecurityTypeUnknown = 4
};

typedef NS_ENUM(NSInteger, NEHotspotHelperConfidence) {
    kNEHotspotHelperConfidenceNone = 0,
    kNEHotspotHelperConfidenceLow = 1,
    kNEHotspotHelperConfidenceHigh = 2,
};

@interface NEHotspotNetwork : NSObject
@property (readonly, nullable) NSString *SSID;
@property (readonly, nullable) NSString *BSSID;
@property (readonly) NEHotspotNetworkSecurityType securityType;
+ (void)fetchCurrentWithCompletionHandler:(void (^)(NEHotspotNetwork * __nullable currentNetwork))completionHandler;
@end

@interface NEHotspotNetwork (HotspotHelper)
@property (readonly) double signalStrength;
@property (readonly, getter=isSecure) BOOL secure;
@property (readonly, getter=didAutoJoin) BOOL autoJoined;
@property (readonly, getter=didJustJoin) BOOL justJoined;
@property (readonly, getter=isChosenHelper) BOOL chosenHelper;
- (void)setConfidence:(NEHotspotHelperConfidence)confidence;
- (void)setPassword:(NSString *)password;
@end

@interface NEHotspotConfiguration : NSObject <NSCopying, NSSecureCoding>
/* Empty, not nil, for a configuration built from an SSID prefix: the host answers the empty string. */
@property (readonly, nullable) NSString *SSID;
/* Empty for a configuration built from an SSID, as the host answers. */
@property (readonly, nullable) NSString *SSIDPrefix;
@property BOOL joinOnce;
@property (copy, nullable) NSNumber *lifeTimeInDays;
@property BOOL hidden;
- (instancetype)initWithSSID:(NSString *)SSID;
- (instancetype)initWithSSID:(NSString *)SSID passphrase:(NSString *)passphrase isWEP:(BOOL)isWEP;
- (instancetype)initWithSSIDPrefix:(NSString *)SSIDPrefix;
- (instancetype)initWithSSIDPrefix:(NSString *)SSIDPrefix passphrase:(NSString *)passphrase isWEP:(BOOL)isWEP;
@end

NS_ASSUME_NONNULL_END
