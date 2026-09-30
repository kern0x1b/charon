// CharonWebExtension.h — the WebKit web-extension API of iOS 18.4, as this port carries it.
// The 16.4 SDK this package compiles against has no WebKit.framework web-extension API at all, so
// every declaration below is transcribed from the 26.2 SDK's WKWebExtension*.h: the class, its
// members with their kinds and types, and API_AVAILABLE(ios(18.4)). Facts only — no body, no
// behaviour, and nothing that is not in those headers.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

typedef NSString *WKWebExtensionPermission NS_STRING_ENUM NS_SWIFT_NAME(WebExtension.Permission);

// The error domain and the codes the 26.2 SDK's NS_ERROR_ENUM numbers from 1 in this order.
extern NSString *const WKWebExtensionErrorDomain;
typedef NS_ENUM(NSInteger, WKWebExtensionError) {
    WKWebExtensionErrorUnknown = 1,
    WKWebExtensionErrorResourceNotFound,
    WKWebExtensionErrorInvalidResourceCodeSignature,
    WKWebExtensionErrorInvalidManifest,
    WKWebExtensionErrorUnsupportedManifestVersion,
    WKWebExtensionErrorInvalidManifestEntry,
    WKWebExtensionErrorInvalidDeclarativeNetRequestEntry,
    WKWebExtensionErrorInvalidBackgroundPersistence,
    WKWebExtensionErrorInvalidArchive,
} API_AVAILABLE(ios(18.4));

// The options the two matches methods take, from the 26.2 SDK's NS_OPTIONS.
typedef NS_OPTIONS(NSUInteger, WKWebExtensionMatchPatternOptions) {
    WKWebExtensionMatchPatternOptionsNone = 0,
    WKWebExtensionMatchPatternOptionsIgnoreSchemes = 1 << 0,
    WKWebExtensionMatchPatternOptionsIgnorePaths = 1 << 1,
    WKWebExtensionMatchPatternOptionsMatchBidirectionally = 1 << 2,
} API_AVAILABLE(ios(18.4));

// The match pattern, which the extension's permission sets are made of. Its own matching behaviour
// is a later family; what WKWebExtension needs to exist is the class and the string form.
@interface WKWebExtensionMatchPattern : NSObject <NSCopying>
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithString:(NSString *)string error:(NSError **)error __attribute__((objc_method_family(init)));
- (nullable instancetype)initWithScheme:(NSString *)scheme
                                   host:(NSString *)host
                                   path:(NSString *)path
                                  error:(NSError **)error __attribute__((objc_method_family(init)));
- (BOOL)matchesPattern:(nullable WKWebExtensionMatchPattern *)pattern;
- (BOOL)matchesPattern:(WKWebExtensionMatchPattern *)pattern
               options:(WKWebExtensionMatchPatternOptions)options;
- (BOOL)matchesURL:(NSURL *)url;
- (BOOL)matchesURL:(nullable NSURL *)url options:(WKWebExtensionMatchPatternOptions)options;
@property (nonatomic, readonly, copy) NSString *string;
@property (nonatomic, readonly, copy) NSString *scheme;
@property (nonatomic, readonly, copy) NSString *host;
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) BOOL matchesAllHosts;
@property (nonatomic, readonly) BOOL matchesAllURLs;
@end

@interface WKWebExtension : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (void)extensionWithAppExtensionBundle:(NSBundle *)appExtensionBundle
                      completionHandler:(void (^)(WKWebExtension *extension, NSError *error))completionHandler;
+ (void)extensionWithResourceBaseURL:(NSURL *)resourceBaseURL
                  completionHandler:(void (^)(WKWebExtension *extension, NSError *error))completionHandler;
- (BOOL)supportsManifestVersion:(double)manifestVersion;
@property (nonatomic, readonly, copy) NSArray<NSError *> *errors;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *manifest;
@property (nonatomic, readonly) double manifestVersion;
@property (nonatomic, nullable, readonly, copy) NSLocale *defaultLocale;
@property (nonatomic, nullable, readonly, copy) NSString *displayName;
@property (nonatomic, nullable, readonly, copy) NSString *displayShortName;
@property (nonatomic, nullable, readonly, copy) NSString *displayVersion;
@property (nonatomic, nullable, readonly, copy) NSString *displayDescription;
@property (nonatomic, nullable, readonly, copy) NSString *displayActionLabel;
@property (nonatomic, nullable, readonly, copy) NSString *version;
- (nullable UIImage *)iconForSize:(CGSize)size;
- (nullable UIImage *)actionIconForSize:(CGSize)size;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *requestedPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *optionalPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *requestedPermissionMatchPatterns;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *optionalPermissionMatchPatterns;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *allRequestedMatchPatterns;
@property (nonatomic, readonly) BOOL hasBackgroundContent;
@property (nonatomic, readonly) BOOL hasPersistentBackgroundContent;
@property (nonatomic, readonly) BOOL hasInjectedContent;
@property (nonatomic, readonly) BOOL hasOptionsPage;
@property (nonatomic, readonly) BOOL hasOverrideNewTabPage;
@property (nonatomic, readonly) BOOL hasCommands;
@property (nonatomic, readonly) BOOL hasContentModificationRules;
@end

// The port's own initialiser. WKWebExtension is a class the RELEASE does not carry, so a class row
// answers for its members, but the spelling is charon_-prefixed all the same: a class the SDK does not
// declare has no header to be transcribed from, and a port-owned initialiser on a class that a later
// SDK WILL carry must never collide with Apple's.
@interface WKWebExtension (CharonInit)
- (instancetype)charon_initWithManifest:(NSDictionary<NSString *, id> *)manifest
                           resourcePath:(NSString *)resourcePath
                                 errors:(NSArray<NSError *> *)errors __attribute__((objc_method_family(init)));
@end
