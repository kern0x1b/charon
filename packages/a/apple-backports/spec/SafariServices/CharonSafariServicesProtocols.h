// CharonSafariServicesProtocols.h - the SafariServices protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <SafariServices/SafariServices.h> for that body, and
#import <SafariServices/SafariServices.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@class BEWebAppManifest;
@class SFAddToHomeScreenInfo;
API_AVAILABLE(ios(17.4))
@protocol SFAddToHomeScreenActivityItem <NSObject>
@property (nonatomic, readonly) NSURL * _Nonnull URL;
@property (nonatomic, readonly) NSString * _Nonnull title;
@optional
@property (nonatomic, readonly) NSItemProvider * _Nullable iconItemProvider;
- (void)getWebAppManifestWithCompletionHandler:(void (^ _Nonnull)(BEWebAppManifest * _Nullable))completionHandler;
- (void)getHomeScreenWebAppInfoWithCompletionHandler:(void (^ _Nonnull)(SFAddToHomeScreenInfo * _Nullable))completionHandler;
@end

@protocol SFSafariViewControllerDelegate;
