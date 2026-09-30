#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

@interface CharonPhotosStore : NSObject
+ (ALAssetsLibrary *)library;
+ (BOOL)canRead;
+ (BOOL)canWrite;
+ (NSArray<PHAsset *> *)assetsOfSourceTypes:(PHAssetSourceType)sourceTypes filter:(ALAssetsFilter *)filter;
+ (NSArray<PHAsset *> *)assetsInGroupWithURL:(NSURL *)url filter:(ALAssetsFilter *)filter;
+ (NSArray<PHAssetCollection *> *)collectionsOfGroupTypes:(ALAssetsGroupType)types;
+ (PHAssetCollection *)collectionWithIdentifier:(NSString *)identifier;
+ (PHAsset *)assetWithIdentifier:(NSString *)identifier;
+ (NSArray<PHAssetCollection *> *)collectionsContainingAssetWithIdentifier:(NSString *)identifier;
+ (NSString *)resolvedIdentifier:(NSString *)identifier;
+ (void)bindPlaceholderIdentifier:(NSString *)token toIdentifier:(NSString *)identifier;
+ (NSString *)writeImageData:(NSData *)data metadata:(NSDictionary *)metadata error:(NSError **)error;
+ (NSString *)writeImage:(UIImage *)image error:(NSError **)error;
+ (NSString *)writeVideoAtURL:(NSURL *)url error:(NSError **)error;
+ (NSError *)errorWithCode:(NSInteger)code reason:(NSString *)reason;
// NO, with the library's error, when the albums cannot be listed; otherwise YES, and whether one has the name.
+ (BOOL)findAlbumWithName:(NSString *)name found:(BOOL *)found error:(NSError **)error;
+ (ALAssetsGroup *)createAlbumWithName:(NSString *)name error:(NSError **)error;
+ (BOOL)addAsset:(ALAsset *)asset toGroupWithURL:(NSURL *)url error:(NSError **)error;
@end

@interface CharonPhotosTransaction : NSObject
+ (CharonPhotosTransaction *)current;
+ (void)run:(dispatch_block_t)changes then:(void (^)(BOOL success, NSError *error))completion;
+ (BOOL)runAndWait:(dispatch_block_t)changes error:(NSError **)error;
- (void)addChange:(id)change;
- (NSArray *)changes;
- (void)refuseWithReason:(NSString *)reason;
@end

// PHPhotoLibrary's own instance variables, in a class extension rather than in the @implementation:
// the members of one release live in one file each (PHPhotoLibrary.m carries 8.0, the availability
// members of 13.0 are in PHPhotoLibraryAvailability13.m), and a category cannot add an ivar, so the
// names have to be visible to both. The layout is still the class's own, emitted by its @implementation.
@interface PHPhotoLibrary () {
    NSHashTable *_observers;
    dispatch_queue_t _delivery;
    id _listening;
    NSHashTable *_availabilityObservers;
    dispatch_queue_t _availabilityDelivery;
    id _availabilityListening;
    NSInteger _lastAvailability;
}
@end

@interface PHObject (Charon)
- (instancetype)initWithCharonLocalIdentifier:(NSString *)identifier;
@end

@interface PHFetchResult (Charon)
- (instancetype)initWithCharonObjects:(NSArray *)objects;
- (instancetype)initWithCharonQuery:(NSArray *(^)(void))query options:(PHFetchOptions *)options;
- (PHFetchResult *)charon_refetched;
- (BOOL)charon_wantsIncrementalChangeDetails;
@end

@interface PHObject (CharonChange)
- (PHObject *)charon_refetched;
- (BOOL)charon_sameStateAs:(PHObject *)other;
@end

@interface PHChange (Charon)
- (instancetype)initWithCharonUserInfo:(NSDictionary *)userInfo;
@end

@interface PHFetchOptions (Charon)
- (NSArray *)charon_apply:(NSArray *)objects;
@end

@interface PHAsset (Charon)
- (instancetype)initWithCharonAsset:(ALAsset *)asset sourceType:(PHAssetSourceType)sourceType;
- (ALAsset *)charon_asset;
@end

@interface PHAssetCollection (Charon)
- (instancetype)initWithCharonGroup:(ALAssetsGroup *)group;
- (instancetype)initWithCharonSmartSubtype:(PHAssetCollectionSubtype)subtype;
- (NSArray<PHAsset *> *)charon_assets;
- (ALAssetsGroup *)charon_group;
@end

@interface PHAssetChangeRequest (Charon)
- (NSDictionary *)charon_metadata;
@end
