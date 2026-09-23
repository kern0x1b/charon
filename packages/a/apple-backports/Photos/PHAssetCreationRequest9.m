#import "CharonPhotos.h"
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

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
    BOOL _moveFile;
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
    _moveFile = options.shouldMoveFile;
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
            *error = [CharonPhotosStore errorWithCode:PHPhotosErrorMissingResource reason:@"the creation request was never given a resource to save"];
        return NO;
    }
    if (_resourceType == PHAssetResourceTypePhoto && _resourceData && ![UIImage imageWithData:_resourceData]) {
        if (error)
            *error = [CharonPhotosStore errorWithCode:PHPhotosErrorInvalidResource reason:@"the resource data is not an image this release can decode"];
        return NO;
    }
    // A move takes the file out of its folder once the asset is made. The header says a hard-linked file cannot be
    // moved; neither can one whose folder does not let it be removed. Both fail here, before anything is written.
    if (_moveFile && _resourceFileURL) {
        struct stat status;
        const char *path = _resourceFileURL.fileSystemRepresentation;
        NSString *refusal = nil;
        if (lstat(path, &status) != 0) {
            if (error)
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSURLErrorKey: _resourceFileURL}];
            return NO;
        }
        if (status.st_nlink > 1)
            refusal = @"a file with more than one hard link cannot be moved into the photo library";
        else if (access(_resourceFileURL.URLByDeletingLastPathComponent.fileSystemRepresentation, W_OK) != 0)
            refusal = @"the file's folder does not let it be removed, so it cannot be moved into the photo library";
        if (refusal) {
            if (error)
                *error = [CharonPhotosStore errorWithCode:PHPhotosErrorInvalidResource reason:refusal];
            return NO;
        }
    }
    return YES;
}

// A moved file is removed once the asset is made from it; a removal that then fails fails the change with the file
// system's error, like any other write of the change that fails after the ones before it were made.
- (BOOL)charon_removeMovedFile:(NSError **)error
{
    if (!_moveFile || !_resourceFileURL)
        return YES;
    if (unlink(_resourceFileURL.fileSystemRepresentation) == 0)
        return YES;
    if (error)
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSURLErrorKey: _resourceFileURL}];
    return NO;
}

- (BOOL)charon_commit:(NSError **)error
{
    NSDictionary *metadata = [self charon_metadata];
    NSString *identifier = nil;
    NSURL *staged = nil;
    if (_resourceType == PHAssetResourceTypePhoto) {
        NSData *data = _resourceData ?: (_resourceFileURL ? [NSData dataWithContentsOfURL:_resourceFileURL] : nil);
        identifier = [CharonPhotosStore writeImageData:data metadata:metadata error:error];
    } else if (_resourceFileURL) {
        identifier = [CharonPhotosStore writeVideoAtURL:_resourceFileURL error:error];
    } else {
        // ALAssetsLibrary takes a video only as a file: the data is staged in one of this process's own, which is
        // removed once the library has copied it, whether the write succeeded or not.
        staged = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
        if (![_resourceData writeToURL:staged options:NSDataWritingAtomic error:error])
            return NO;
        identifier = [CharonPhotosStore writeVideoAtURL:staged error:error];
    }
    if (identifier)
        [CharonPhotosStore bindPlaceholderIdentifier:_token toIdentifier:identifier];
    // A write that failed keeps its own error, the cause; after one that succeeded, a staged file that cannot be removed
    // fails the change with the file system's error, as a moved file does.
    if (staged && unlink(staged.fileSystemRepresentation) != 0 && identifier) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSURLErrorKey: staged}];
        return NO;
    }
    if (!identifier)
        return NO;
    return [self charon_removeMovedFile:error];
}

@end
