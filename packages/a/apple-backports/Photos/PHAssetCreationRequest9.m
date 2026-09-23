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

@implementation PHAssetResourceCreationOptions
@synthesize originalFilename, uniformTypeIdentifier, shouldMoveFile;

- (id)copyWithZone:(NSZone *)zone
{
    PHAssetResourceCreationOptions *copy = [[PHAssetResourceCreationOptions alloc] init];
    copy.originalFilename = self.originalFilename;
    copy.uniformTypeIdentifier = self.uniformTypeIdentifier;
    copy.shouldMoveFile = self.shouldMoveFile;
    return copy;
}

@end

@implementation PHAssetCreationRequest {
    NSString *_token;
    PHObjectPlaceholder *_placeholder;
    BOOL _hasResource;
    PHAssetResourceType _resourceType;
    NSData *_resourceData;
    NSURL *_resourceFileURL;
}

+ (instancetype)creationRequestForAsset
{
    CharonPhotosTransaction *transaction = charon_transaction();
    PHAssetCreationRequest *request = [[self alloc] init];
    request->_token = [[NSUUID UUID].UUIDString stringByAppendingString:@"/L0/001"];
    request->_placeholder = [[PHObjectPlaceholder alloc] initWithCharonLocalIdentifier:request->_token];
    [transaction addChange:request];
    return request;
}

+ (BOOL)supportsAssetResourceTypes:(NSArray<NSNumber *> *)types
{
    return types.count == 1 && (types.firstObject.integerValue == PHAssetResourceTypePhoto || types.firstObject.integerValue == PHAssetResourceTypeVideo);
}

- (PHObjectPlaceholder *)placeholderForCreatedAsset
{
    return _placeholder;
}

- (void)charon_addResourceOfType:(PHAssetResourceType)type
{
    if (type != PHAssetResourceTypePhoto && type != PHAssetResourceTypeVideo) {
        [charon_transaction() refuseWithReason:@"iOS 6 can only add a primary photo or video resource, not adjustment data, an alternate photo, or a live photo pairing"];
        return;
    }
    if (_hasResource) {
        [charon_transaction() refuseWithReason:@"iOS 6 can save only a single resource for a new asset"];
        return;
    }
    _hasResource = YES;
    _resourceType = type;
}

- (void)addResourceWithType:(PHAssetResourceType)type fileURL:(NSURL *)fileURL options:(PHAssetResourceCreationOptions *)options
{
    [self charon_addResourceOfType:type];
    _resourceFileURL = fileURL;
}

- (void)addResourceWithType:(PHAssetResourceType)type data:(NSData *)data options:(PHAssetResourceCreationOptions *)options
{
    [self charon_addResourceOfType:type];
    _resourceData = data;
}

- (BOOL)charon_validate:(NSError **)error
{
    if (!_hasResource) {
        if (error)
            *error = [CharonPhotosStore errorWithCode:3302 reason:@"the creation request was never given a resource to save"];
        return NO;
    }
    if (_resourceType == PHAssetResourceTypePhoto && _resourceData && ![UIImage imageWithData:_resourceData]) {
        if (error)
            *error = [CharonPhotosStore errorWithCode:3302 reason:@"the resource data is not an image this release can decode"];
        return NO;
    }
    return YES;
}

- (BOOL)charon_commit:(NSError **)error
{
    NSDictionary *metadata = [self charon_metadata];
    NSString *identifier = nil;
    if (_resourceType == PHAssetResourceTypePhoto) {
        NSData *data = _resourceData ?: (_resourceFileURL ? [NSData dataWithContentsOfURL:_resourceFileURL] : nil);
        identifier = [CharonPhotosStore writeImageData:data metadata:metadata error:error];
    } else {
        NSURL *url = _resourceFileURL;
        if (!url && _resourceData) {
            url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
            if (![_resourceData writeToURL:url atomically:YES]) {
                if (error)
                    *error = [CharonPhotosStore errorWithCode:-1 reason:@"the video data could not be staged for the photo library"];
                return NO;
            }
        }
        identifier = [CharonPhotosStore writeVideoAtURL:url error:error];
    }
    if (!identifier)
        return NO;
    [CharonPhotosStore bindPlaceholderIdentifier:_token toIdentifier:identifier];
    return YES;
}

@end
