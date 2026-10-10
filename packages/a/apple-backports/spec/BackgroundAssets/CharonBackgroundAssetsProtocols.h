// CharonBackgroundAssetsProtocols.h - the BackgroundAssets protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <BackgroundAssets/BackgroundAssets.h> for that body, and
#import <BackgroundAssets/BackgroundAssets.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol BADownloadManagerDelegate;

@protocol BADownloaderExtension;

@class BAAssetPack;
API_AVAILABLE(ios(26))
@protocol BAManagedAssetPackDownloadDelegate <NSObject>
@optional
- (void)downloadOfAssetPackBegan:(BAAssetPack * _Nonnull)assetPack;
- (void)downloadOfAssetPackPaused:(BAAssetPack * _Nonnull)assetPack;
- (void)downloadOfAssetPack:(BAAssetPack * _Nonnull)assetPack hasProgress:(NSProgress * _Nonnull)progress;
- (void)downloadOfAssetPackFinished:(BAAssetPack * _Nonnull)assetPack;
- (void)downloadOfAssetPack:(BAAssetPack * _Nonnull)assetPack failedWithError:(NSError * _Nonnull)error;
@end

@class BAAssetPack;
API_AVAILABLE(ios(26))
@protocol BAManagedDownloaderExtension <BADownloaderExtension>
@optional
- (BOOL)shouldDownloadAssetPack:(BAAssetPack * _Nonnull)assetPack;
@end
