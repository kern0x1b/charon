#import "CharonPhotos.h"

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static CharonPhotosTransaction *charon_transaction(void)
{
    CharonPhotosTransaction *transaction = [CharonPhotosTransaction current];
    if (!transaction)
        [NSException raise:NSInternalInconsistencyException format:@"This method can only be called from inside of -[PHPhotoLibrary performChanges:completionHandler:] or -[PHPhotoLibrary performChangesAndWait:error:]"];
    return transaction;
}

@implementation PHAssetCollectionChangeRequest {
    PHAssetCollection *_editing;
    NSString *_title;
    NSString *_token;
    PHObjectPlaceholder *_placeholder;
    NSMutableArray<PHAsset *> *_addedAssets;
}

+ (instancetype)creationRequestForAssetCollectionWithTitle:(NSString *)title
{
    CharonPhotosTransaction *transaction = charon_transaction();
    PHAssetCollectionChangeRequest *request = [[self alloc] init];
    request->_title = [title copy];
    request->_token = [[NSUUID UUID].UUIDString stringByAppendingString:@"/L0/ALBUM"];
    request->_placeholder = [[PHObjectPlaceholder alloc] initWithCharonLocalIdentifier:request->_token];
    [transaction addChange:request];
    return request;
}

+ (void)deleteAssetCollections:(id<NSFastEnumeration>)assetCollections
{
    [charon_transaction() refuseWithReason:@"iOS 6 has no way to delete an album through AssetsLibrary"];
}

+ (instancetype)changeRequestForAssetCollection:(PHAssetCollection *)assetCollection
{
    CharonPhotosTransaction *transaction = charon_transaction();
    if (![assetCollection charon_group] || assetCollection.assetCollectionSubtype != PHAssetCollectionSubtypeAlbumRegular) {
        [transaction refuseWithReason:@"iOS 6 can only change a regular album, not a smart album or one synced from elsewhere"];
        return nil;
    }
    PHAssetCollectionChangeRequest *request = [[self alloc] init];
    request->_editing = assetCollection;
    [transaction addChange:request];
    return request;
}

+ (instancetype)changeRequestForAssetCollection:(PHAssetCollection *)assetCollection assets:(PHFetchResult<PHAsset *> *)assets
{
    return [self changeRequestForAssetCollection:assetCollection];
}

- (PHObjectPlaceholder *)placeholderForCreatedAssetCollection
{
    return _placeholder;
}

- (NSString *)title
{
    return _editing.localizedTitle ?: _title;
}

- (void)setTitle:(NSString *)title
{
    if (_editing)
        [charon_transaction() refuseWithReason:@"iOS 6 has no way to rename an existing album through AssetsLibrary"];
    else
        _title = [title copy];
}

- (void)addAssets:(id<NSFastEnumeration>)assets
{
    if (!_editing && !_title)
        [charon_transaction() refuseWithReason:@"addAssets: needs either a new album or one fetched with changeRequestForAssetCollection:"];
    if (!_addedAssets)
        _addedAssets = [NSMutableArray array];
    for (PHAsset *asset in assets)
        [_addedAssets addObject:asset];
}

- (void)insertAssets:(id<NSFastEnumeration>)assets atIndexes:(NSIndexSet *)indexes
{
    [charon_transaction() refuseWithReason:@"iOS 6 can only append assets to an album, not insert them at a position"];
}

- (void)removeAssets:(id<NSFastEnumeration>)assets
{
    [charon_transaction() refuseWithReason:@"iOS 6 has no way to remove an asset from an album through AssetsLibrary"];
}

- (void)removeAssetsAtIndexes:(NSIndexSet *)indexes
{
    [charon_transaction() refuseWithReason:@"iOS 6 has no way to remove an asset from an album through AssetsLibrary"];
}

- (void)replaceAssetsAtIndexes:(NSIndexSet *)indexes withAssets:(id<NSFastEnumeration>)assets
{
    [charon_transaction() refuseWithReason:@"iOS 6 has no way to replace an album's assets through AssetsLibrary"];
}

- (void)moveAssetsAtIndexes:(NSIndexSet *)fromIndexes toIndex:(NSUInteger)toIndex
{
    [charon_transaction() refuseWithReason:@"iOS 6 albums through AssetsLibrary carry no order to move within"];
}

- (BOOL)charon_validate:(NSError **)error
{
    return YES;
}

- (BOOL)charon_commit:(NSError **)error
{
    NSURL *groupURL;
    if (_title) {
        ALAssetsGroup *group = [CharonPhotosStore createAlbumWithName:_title error:error];
        if (!group)
            return NO;
        groupURL = [group valueForProperty:ALAssetsGroupPropertyURL];
        [CharonPhotosStore bindPlaceholderIdentifier:_token toIdentifier:groupURL.absoluteString];
    } else {
        groupURL = [NSURL URLWithString:[CharonPhotosStore resolvedIdentifier:_editing.localIdentifier]];
    }
    for (PHAsset *asset in _addedAssets) {
        if (![CharonPhotosStore addAsset:[asset charon_asset] toGroupWithURL:groupURL error:error])
            return NO;
    }
    return YES;
}

@end
