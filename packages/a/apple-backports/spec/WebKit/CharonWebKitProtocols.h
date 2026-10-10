// CharonWebKitProtocols.h - the WebKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <WebKit/WebKit.h> for that body, and
#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
#import "CharonWebExtensionController.h"

@protocol UIContextMenuInteractionCommitAnimating;

@protocol UIEditMenuInteractionAnimating;

@protocol WKDownloadDelegate;

@protocol WKHTTPCookieStoreObserver;

@protocol WKNavigationDelegate;

@protocol WKPreviewActionItem;

@protocol WKScriptMessageHandlerWithReply;

@protocol WKUIDelegate;

@protocol WKURLSchemeHandler;

@protocol WKURLSchemeTask;

@protocol WKWebExtensionControllerDelegate;

@class WKWebExtensionContext;
@class WKWebExtensionTabConfiguration;
API_AVAILABLE(ios(18.4))
@protocol WKWebExtensionTab <NSObject>
@optional
- (id<WKWebExtensionWindow> _Nullable)windowForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (NSUInteger)indexInWindowForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (id<WKWebExtensionTab> _Nullable)parentTabForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setParentTab:(id<WKWebExtensionTab>  _Nullable)parentTab forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (WKWebView * _Nullable)webViewForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (NSString * _Nullable)titleForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (BOOL)isPinnedForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setPinned:(BOOL)pinned forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (BOOL)isReaderModeAvailableForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (BOOL)isReaderModeActiveForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setReaderModeActive:(BOOL)active forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (BOOL)isPlayingAudioForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (BOOL)isMutedForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setMuted:(BOOL)muted forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (CGSize)sizeForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (double)zoomFactorForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setZoomFactor:(double)zoomFactor forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (NSURL * _Nullable)urlForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (NSURL * _Nullable)pendingURLForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (BOOL)isLoadingCompleteForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)detectWebpageLocaleForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSLocale * _Nullable_result, NSError * _Nullable))completionHandler;
- (void)takeSnapshotUsingConfiguration:(WKSnapshotConfiguration * _Nonnull)configuration forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(UIImage * _Nullable_result, NSError * _Nullable))completionHandler;
- (void)loadURL:(NSURL * _Nonnull)url forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)reloadFromOrigin:(BOOL)fromOrigin forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)goBackForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)goForwardForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)activateForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (BOOL)isSelectedForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setSelected:(BOOL)selected forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)duplicateUsingConfiguration:(WKWebExtensionTabConfiguration * _Nonnull)configuration forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(id<WKWebExtensionTab>  _Nullable_result, NSError * _Nullable))completionHandler;
- (void)closeForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (BOOL)shouldGrantPermissionsOnUserGestureForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (BOOL)shouldBypassPermissionsForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
@end

@class WKWebExtensionContext;
typedef enum WKWebExtensionWindowState WKWebExtensionWindowState;
typedef enum WKWebExtensionWindowType WKWebExtensionWindowType;
API_AVAILABLE(ios(18.4))
@protocol WKWebExtensionWindow <NSObject>
@optional
- (NSArray<id<WKWebExtensionTab>> * _Nonnull)tabsForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (id<WKWebExtensionTab> _Nullable)activeTabForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (WKWebExtensionWindowType)windowTypeForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (WKWebExtensionWindowState)windowStateForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setWindowState:(WKWebExtensionWindowState)state forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (BOOL)isPrivateForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (CGRect)frameForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context;
- (void)setFrame:(CGRect)frame forWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)focusForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
- (void)closeForWebExtensionContext:(WKWebExtensionContext * _Nonnull)context completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler;
@end
