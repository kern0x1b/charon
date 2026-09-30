#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "CharonWebExtension.h"

/* The measured values of the context's constants, which is the whole of this family the port can
 * answer. A notification NAME drops the "Notification" suffix its symbol carries, and the two
 * user-info keys are "permissions" and "matchPatterns" -- all read by dlsym on this host, not
 * written from the symbol names. */

NSString *const WKWebExtensionContextErrorDomain = @"WKWebExtensionContextErrorDomain";
NSString *const WKWebExtensionContextPermissionsWereGrantedNotification = @"WKWebExtensionContextPermissionsWereGranted";
NSString *const WKWebExtensionContextPermissionMatchPatternsWereGrantedNotification = @"WKWebExtensionContextPermissionMatchPatternsWereGranted";
NSString *const WKWebExtensionContextGrantedPermissionsWereRemovedNotification = @"WKWebExtensionContextGrantedPermissionsWereRemoved";
NSString *const WKWebExtensionContextDeniedPermissionsWereRemovedNotification = @"WKWebExtensionContextDeniedPermissionsWereRemoved";
NSString *const WKWebExtensionContextPermissionMatchPatternsWereDeniedNotification = @"WKWebExtensionContextPermissionMatchPatternsWereDenied";
NSString *const WKWebExtensionContextDeniedPermissionMatchPatternsWereRemovedNotification = @"WKWebExtensionContextDeniedPermissionMatchPatternsWereRemoved";
NSString *const WKWebExtensionContextErrorsDidUpdateNotification = @"WKWebExtensionContextErrorsDidUpdate";
NSString *const WKWebExtensionContextNotificationUserInfoKeyPermissions = @"permissions";
NSString *const WKWebExtensionContextNotificationUserInfoKeyMatchPatterns = @"matchPatterns";

/* WKWebExtensionContext is DECLARED and not implemented, and that is the measured state of it.
 *
 * A context only exists once an extension is loaded in a web view. On this host:
 *
 *   -[WKWebExtensionController loadExtensionContext:error:] does not CREATE a context, it CONSUMES
 *   one, and raises on anything else:
 *       NSInternalInconsistencyException, reason:
 *       'Invalid parameter not satisfying: [extensionContext isKindOfClass:WKWebExtensionContext.class]'
 *
 *   -[WKWebExtensionController extensionContextForExtension:] does create one, and answers nil here
 *   for an extension built from a resource:
 *       extensionContextForExtension = 0x0
 *
 * So there is no object to answer anything from, and a port that invented values for loaded, inspectable
 * or any permission set would be answering numbers it did not measure. The class is here so that
 * NSClassFromString finds it and so that a later family -- the controller, which needs a web view this
 * port has not got -- has something to hand out; every member is unimplemented and every row says
 * which. The permission status an extension does not have is Unknown, and that is the zero of the enum
 * the 26.2 SDK declares, which is the value a caller reads when nothing has been decided.
 */
