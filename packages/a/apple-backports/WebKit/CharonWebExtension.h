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

// The match pattern's error domain and codes, from the 26.2 SDK's NS_ERROR_ENUM, which numbers
// them from 1 in the order it declares them.
extern NSString *const WKWebExtensionMatchPatternErrorDomain;
typedef NS_ENUM(NSInteger, WKWebExtensionMatchPatternError) {
    WKWebExtensionMatchPatternErrorUnknown = 1,
    WKWebExtensionMatchPatternErrorInvalidScheme,
    WKWebExtensionMatchPatternErrorInvalidHost,
    WKWebExtensionMatchPatternErrorInvalidPath,
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

// The toolbar button and the keyboard commands. Both are NS_UNAVAILABLE to a program -- a CONTEXT
// hands them out -- and both are value holders, so the port carries the members and a context
// supplies the values. WKWebExtensionTab and WKWebExtensionContext are forward-declared here: they
// are their own families and this one only holds weak references to them.
@class WKWebExtensionContext;
@class WKWebExtensionController;
@protocol WKWebExtensionWindow;
@protocol WKWebExtensionTab;
@class WKWebView;

@interface WKWebExtensionAction : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, weak) WKWebExtensionContext *webExtensionContext;
@property (nonatomic, readonly, nullable, weak) id<WKWebExtensionTab> associatedTab;
- (nullable UIImage *)iconForSize:(CGSize)size;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, copy) NSString *badgeText;
@property (nonatomic) BOOL hasUnreadBadgeText;
@property (nonatomic, nullable, copy) NSString *inspectionName;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, copy) NSArray<UIMenuElement *> *menuItems;
@property (nonatomic, readonly) BOOL presentsPopup;
@property (nonatomic, readonly, nullable) UIViewController *popupViewController;
@property (nonatomic, readonly, nullable) WKWebView *popupWebView;
- (void)closePopup;
@end

@interface WKWebExtensionCommand : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly, weak) WKWebExtensionContext *webExtensionContext;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, nullable, copy) NSString *activationKey;
@property (nonatomic) UIKeyModifierFlags modifierFlags;
@property (nonatomic, readonly, copy) UIMenuElement *menuItem;
@property (nonatomic, readonly, copy, nullable) UIKeyCommand *keyCommand;
@end

// The port's own initialisers and setters, charon_-prefixed so they can never collide with a selector
// a later SDK grows, and in the init family because they assign to self.
@interface WKWebExtensionAction (CharonAction)
- (instancetype)charon_initWithContext:(WKWebExtensionContext *)context __attribute__((objc_method_family(init)));
- (void)charon_setLabel:(NSString *)label
              badgeText:(NSString *)badgeText
       inspectionName:(NSString *)inspectionName
             menuItems:(NSArray<UIMenuElement *> *)menuItems
                   icon:(UIImage *)icon
        presentsPopup:(BOOL)presentsPopup
  popupViewController:(UIViewController *)popupViewController
               enabled:(BOOL)enabled;
- (void)charon_setAssociatedTab:(id<WKWebExtensionTab>)tab;
@end

@interface WKWebExtensionCommand (CharonCommand)
- (instancetype)charon_initWithContext:(WKWebExtensionContext *)context
                             identifier:(NSString *)identifier
                                  title:(NSString *)title __attribute__((objc_method_family(init)));
- (void)charon_setActivationKey:(NSString *)activationKey menuItem:(UIMenuElement *)menuItem;
@end

// WKWebExtensionContext: what an extension, once it is LOADED, can do and be asked about.
//
// The class and its constants are carried. Its members are NOT, and the reason is measured rather
// than assumed: a context only exists once an extension is loaded in a web view, and the host cannot
// be asked for one here. `-[WKWebExtensionController loadExtensionContext:error:]` does not create a
// context -- it CONSUMES one, and the host raises on it when handed anything else:
//
//   *** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
//   reason: 'Invalid parameter not satisfying: [extensionContext isKindOfClass:WKWebExtensionContext.class]'
//   3   WebKit   -[WKWebExtensionController loadExtensionContext:error:]
//
// and the path that does create one, -[WKWebExtensionController extensionContextForExtension:],
// answers nil on this host for an extension built from a resource:
//
//   extensionContextForExtension = 0x0
//
// So every member below is declared and left unimplemented, and its row says what Apple answers
// without a web view. Nothing in this family is marked implemented on the strength of a measurement
// this port did not take.
extern NSString *const WKWebExtensionContextErrorDomain;
extern NSString *const WKWebExtensionContextPermissionsWereGrantedNotification;          /* "...PermissionsWereGranted" */
extern NSString *const WKWebExtensionContextPermissionMatchPatternsWereGrantedNotification;
extern NSString *const WKWebExtensionContextGrantedPermissionsWereRemovedNotification;
extern NSString *const WKWebExtensionContextDeniedPermissionsWereRemovedNotification;
extern NSString *const WKWebExtensionContextPermissionMatchPatternsWereDeniedNotification;
extern NSString *const WKWebExtensionContextDeniedPermissionMatchPatternsWereRemovedNotification;
extern NSString *const WKWebExtensionContextErrorsDidUpdateNotification;                 /* "...ErrorsDidUpdate" */
extern NSString *const WKWebExtensionContextNotificationUserInfoKeyPermissions;          /* "permissions" */
extern NSString *const WKWebExtensionContextNotificationUserInfoKeyMatchPatterns;      /* "matchPatterns" */

typedef NS_ENUM(NSInteger, WKWebExtensionContextPermissionStatus) {
    WKWebExtensionContextPermissionStatusUnknown = 0,
    WKWebExtensionContextPermissionStatusGrantedExplicitly,
    WKWebExtensionContextPermissionStatusGrantedImplicitly,
    WKWebExtensionContextPermissionStatusDeniedExplicitly,
    WKWebExtensionContextPermissionStatusDeniedImplicitly,
    WKWebExtensionContextPermissionStatusRequestedExplicitly,
    WKWebExtensionContextPermissionStatusRequestedImplicitly,
} API_AVAILABLE(ios(18.4));

@interface WKWebExtensionContext : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (nullable instancetype)contextForExtension:(WKWebExtension *)extension;
@property (nonatomic, readonly, weak) WKWebExtensionController *webExtensionController;
@property (nonatomic, readonly, weak) WKWebExtension *webExtension;
@property (nonatomic, readonly, copy) NSUUID *uniqueIdentifier;
@property (nonatomic, readonly) BOOL loaded;
@property (nonatomic, readonly) BOOL inspectable;
@property (nonatomic, readonly, copy) NSURL *baseURL;   /* webkit-extension://<uniqueIdentifier>/ */
@property (nonatomic, readonly, nullable, copy) NSURL *optionsPageURL;
@property (nonatomic, readonly, nullable, copy) NSURL *overrideNewTabPageURL;
@property (nonatomic, readonly, copy) NSArray<NSError *> *errors;
@property (nonatomic, readonly, copy) NSArray<NSString *> *unsupportedAPIs;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *grantedPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *deniedPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *currentPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *grantedPermissionMatchPatterns;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *deniedPermissionMatchPatterns;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *currentPermissionMatchPatterns;
@property (nonatomic, readonly) BOOL hasAccessToAllHosts;
@property (nonatomic, readonly) BOOL hasAccessToAllURLs;
@property (nonatomic, readonly) BOOL hasAccessToPrivateData;
@property (nonatomic, readonly) BOOL hasRequestedOptionalAccessToAllHosts;
@property (nonatomic, readonly) BOOL hasContentModificationRules;
@property (nonatomic, readonly) BOOL hasInjectedContent;
@property (nonatomic, readonly, nullable) WKWebViewConfiguration *webViewConfiguration;
@property (nonatomic, readonly) NSArray<id<WKWebExtensionTab>> *openTabs;
@property (nonatomic, readonly) NSArray<id<WKWebExtensionWindow>> *openWindows;
@property (nonatomic, readonly, nullable) id<WKWebExtensionWindow> focusedWindow;
@property (nonatomic, readonly) NSArray<WKWebExtensionCommand *> *commands;
- (nullable WKWebExtensionAction *)actionForTab:(id<WKWebExtensionTab>)tab;
@property (nonatomic, readonly, nullable) NSString *inspectionName;
@end

// The port's own initialiser, charon_-prefixed and in the init family, and the build step the class
// method calls once it has an extension.
@interface WKWebExtensionContext (CharonContext)
- (instancetype)charon_initWithExtension:(WKWebExtension *)extension __attribute__((objc_method_family(init)));
- (void)charon_buildFromManifest;
@end
