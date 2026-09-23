#import "CharonPhotos.h"
#import <CoreLocation/CoreLocation.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static PHFetchResult *charon_collections(NSArray *collections, PHFetchOptions *options)
{
    return [[PHFetchResult alloc] initWithCharonObjects:options ? [options charon_apply:collections] : collections];
}

@implementation PHCollection

- (BOOL)canContainAssets
{
    return NO;
}

- (BOOL)canContainCollections
{
    return NO;
}

- (NSString *)localizedTitle
{
    return nil;
}

- (BOOL)canPerformEditOperation:(PHCollectionEditOperation)operation
{
    return NO;
}

+ (PHFetchResult<PHCollection *> *)fetchCollectionsInCollectionList:(PHCollectionList *)collectionList options:(PHFetchOptions *)options
{
    return charon_collections(@[], options);
}

+ (PHFetchResult<PHCollection *> *)fetchTopLevelUserCollectionsWithOptions:(PHFetchOptions *)options
{
    return charon_collections([CharonPhotosStore collectionsOfGroupTypes:ALAssetsGroupAlbum], options);
}

@end

@implementation PHAssetCollection {
    ALAssetsGroup *_group;
    NSString *_title;
    PHAssetCollectionType _assetCollectionType;
    PHAssetCollectionSubtype _assetCollectionSubtype;
    NSUInteger _estimatedAssetCount;
}

- (instancetype)initWithCharonGroup:(ALAssetsGroup *)group
{
    NSString *identifier = [[group valueForProperty:ALAssetsGroupPropertyURL] absoluteString];
    self = [self initWithCharonLocalIdentifier:identifier];
    if (!self)
        return nil;
    _group = group;
    _title = [group valueForProperty:ALAssetsGroupPropertyName];
    _estimatedAssetCount = group.numberOfAssets;
    switch ([[group valueForProperty:ALAssetsGroupPropertyType] unsignedIntegerValue]) {
    case ALAssetsGroupSavedPhotos:
        _assetCollectionType = PHAssetCollectionTypeSmartAlbum;
        _assetCollectionSubtype = PHAssetCollectionSubtypeSmartAlbumUserLibrary;
        break;
    case ALAssetsGroupEvent:
        _assetCollectionType = PHAssetCollectionTypeAlbum;
        _assetCollectionSubtype = PHAssetCollectionSubtypeAlbumSyncedEvent;
        break;
    case ALAssetsGroupFaces:
        _assetCollectionType = PHAssetCollectionTypeAlbum;
        _assetCollectionSubtype = PHAssetCollectionSubtypeAlbumSyncedFaces;
        break;
    case ALAssetsGroupLibrary:
        _assetCollectionType = PHAssetCollectionTypeAlbum;
        _assetCollectionSubtype = PHAssetCollectionSubtypeAlbumSyncedAlbum;
        break;
    case ALAssetsGroupPhotoStream:
        _assetCollectionType = PHAssetCollectionTypeAlbum;
        _assetCollectionSubtype = PHAssetCollectionSubtypeAlbumMyPhotoStream;
        break;
    default:
        _assetCollectionType = PHAssetCollectionTypeAlbum;
        _assetCollectionSubtype = PHAssetCollectionSubtypeAlbumRegular;
    }
    return self;
}

- (instancetype)initWithCharonSmartSubtype:(PHAssetCollectionSubtype)subtype
{
    self = [self initWithCharonLocalIdentifier:[NSString stringWithFormat:@"CHARON/SMART/%ld", (long)subtype]];
    if (!self)
        return nil;
    _assetCollectionType = PHAssetCollectionTypeSmartAlbum;
    _assetCollectionSubtype = subtype;
    _estimatedAssetCount = subtype == PHAssetCollectionSubtypeSmartAlbumVideos ? NSNotFound : 0;
    switch (subtype) {
    case PHAssetCollectionSubtypeSmartAlbumVideos:
        _title = @"Videos";
        break;
    case PHAssetCollectionSubtypeSmartAlbumFavorites:
        _title = @"Favorites";
        break;
    case PHAssetCollectionSubtypeSmartAlbumAllHidden:
        _title = @"Hidden";
        break;
    case PHAssetCollectionSubtypeSmartAlbumBursts:
        _title = @"Bursts";
        break;
    default:
        _title = nil;
    }
    return self;
}

- (BOOL)canContainAssets
{
    return YES;
}

- (NSString *)localizedTitle
{
    return _title;
}

- (NSUInteger)estimatedAssetCount
{
    return _estimatedAssetCount;
}

- (NSArray<NSString *> *)localizedLocationNames
{
    return @[];
}

- (NSArray<PHAsset *> *)charon_assets
{
    if (_group)
        return [CharonPhotosStore assetsInGroupWithURL:[NSURL URLWithString:self.localIdentifier] filter:nil];
    if (_assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumVideos)
        return [CharonPhotosStore assetsOfSourceTypes:0 filter:[ALAssetsFilter allVideos]];
    return @[];
}

- (ALAssetsGroup *)charon_group
{
    return _group;
}

+ (NSArray *)charon_smartSubtypes
{
    return @[@(PHAssetCollectionSubtypeSmartAlbumVideos), @(PHAssetCollectionSubtypeSmartAlbumFavorites),
             @(PHAssetCollectionSubtypeSmartAlbumBursts), @(PHAssetCollectionSubtypeSmartAlbumAllHidden)];
}

+ (PHFetchResult<PHAssetCollection *> *)fetchAssetCollectionsWithType:(PHAssetCollectionType)type subtype:(PHAssetCollectionSubtype)subtype options:(PHFetchOptions *)options
{
    NSMutableArray *found = [NSMutableArray array];
    if (type == PHAssetCollectionTypeAlbum) {
        for (PHAssetCollection *collection in [CharonPhotosStore collectionsOfGroupTypes:ALAssetsGroupAlbum | ALAssetsGroupEvent | ALAssetsGroupFaces | ALAssetsGroupLibrary | ALAssetsGroupPhotoStream]) {
            if (subtype == PHAssetCollectionSubtypeAny || collection.assetCollectionSubtype == subtype)
                [found addObject:collection];
        }
    } else if (type == PHAssetCollectionTypeSmartAlbum) {
        for (PHAssetCollection *collection in [CharonPhotosStore collectionsOfGroupTypes:ALAssetsGroupSavedPhotos]) {
            if (subtype == PHAssetCollectionSubtypeAny || collection.assetCollectionSubtype == subtype)
                [found addObject:collection];
        }
        for (NSNumber *smart in [self charon_smartSubtypes]) {
            if (subtype == PHAssetCollectionSubtypeAny || subtype == smart.integerValue)
                [found addObject:[[PHAssetCollection alloc] initWithCharonSmartSubtype:(PHAssetCollectionSubtype)smart.integerValue]];
        }
    }
    return charon_collections(found, options);
}

+ (PHFetchResult<PHAssetCollection *> *)fetchAssetCollectionsWithLocalIdentifiers:(NSArray<NSString *> *)identifiers options:(PHFetchOptions *)options
{
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        PHAssetCollection *collection = [CharonPhotosStore collectionWithIdentifier:identifier];
        if (collection)
            [found addObject:collection];
    }
    return charon_collections(found, options);
}

+ (PHFetchResult<PHAssetCollection *> *)fetchAssetCollectionsContainingAsset:(PHAsset *)asset withType:(PHAssetCollectionType)type options:(PHFetchOptions *)options
{
    NSMutableArray *found = [NSMutableArray array];
    for (PHAssetCollection *collection in [CharonPhotosStore collectionsContainingAssetWithIdentifier:asset.localIdentifier]) {
        if (collection.assetCollectionType == type)
            [found addObject:collection];
    }
    return charon_collections(found, options);
}

+ (PHFetchResult<PHAssetCollection *> *)fetchAssetCollectionsWithALAssetGroupURLs:(NSArray<NSURL *> *)assetGroupURLs options:(PHFetchOptions *)options
{
    NSMutableArray *identifiers = [NSMutableArray array];
    for (NSURL *url in assetGroupURLs)
        [identifiers addObject:url.absoluteString];
    return [self fetchAssetCollectionsWithLocalIdentifiers:identifiers options:options];
}

@end

@implementation PHCollectionList

- (NSArray<NSString *> *)localizedLocationNames
{
    return @[];
}

+ (PHFetchResult<PHCollectionList *> *)fetchCollectionListsContainingCollection:(PHCollection *)collection options:(PHFetchOptions *)options
{
    return charon_collections(@[], options);
}

+ (PHFetchResult<PHCollectionList *> *)fetchCollectionListsWithLocalIdentifiers:(NSArray<NSString *> *)identifiers options:(PHFetchOptions *)options
{
    return charon_collections(@[], options);
}

+ (PHFetchResult<PHCollectionList *> *)fetchCollectionListsWithType:(PHCollectionListType)collectionListType subtype:(PHCollectionListSubtype)subtype options:(PHFetchOptions *)options
{
    return charon_collections(@[], options);
}

@end
