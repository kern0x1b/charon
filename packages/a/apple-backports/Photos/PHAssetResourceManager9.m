#import "CharonPhotos.h"

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@implementation PHAssetResourceRequestOptions
@synthesize networkAccessAllowed, progressHandler;

- (id)copyWithZone:(NSZone *)zone
{
    PHAssetResourceRequestOptions *copy = [[PHAssetResourceRequestOptions alloc] init];
    copy.networkAccessAllowed = self.networkAccessAllowed;
    copy.progressHandler = self.progressHandler;
    return copy;
}

@end

@implementation PHAssetResourceManager

+ (instancetype)defaultManager
{
    static PHAssetResourceManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

+ (PHAssetResourceDataRequestID)charon_nextRequestID
{
    static int32_t counter = 0;
    @synchronized ([PHAssetResourceManager class]) {
        counter++;
        return counter;
    }
}

- (NSData *)charon_readResource:(PHAssetResource *)resource error:(NSError **)error
{
    PHAsset *asset = [CharonPhotosStore assetWithIdentifier:resource.assetLocalIdentifier];
    ALAssetRepresentation *representation = [asset charon_asset].defaultRepresentation;
    if (!representation) {
        if (error)
            *error = [CharonPhotosStore errorWithCode:-1 reason:@"the asset this resource was made from no longer exists"];
        return nil;
    }
    NSUInteger length = (NSUInteger)representation.size;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    NSError *readError = nil;
    NSUInteger got = [representation getBytes:data.mutableBytes fromOffset:0 length:length error:&readError];
    if (got != length) {
        if (error)
            *error = readError ?: [CharonPhotosStore errorWithCode:-1 reason:@"the photo library gave fewer bytes than the resource's own size"];
        return nil;
    }
    return data;
}

- (PHAssetResourceDataRequestID)requestDataForAssetResource:(PHAssetResource *)resource
                                                     options:(PHAssetResourceRequestOptions *)options
                                         dataReceivedHandler:(void (^)(NSData *data))handler
                                           completionHandler:(void (^)(NSError *error))completionHandler
{
    PHAssetResourceDataRequestID requestID = [PHAssetResourceManager charon_nextRequestID];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSData *data = [self charon_readResource:resource error:&error];
        if (data) {
            if (options.progressHandler)
                options.progressHandler(1.0);
            if (handler)
                handler(data);
        }
        if (completionHandler)
            completionHandler(data ? nil : error);
    });
    return requestID;
}

- (void)writeDataForAssetResource:(PHAssetResource *)resource
                            toFile:(NSURL *)fileURL
                           options:(PHAssetResourceRequestOptions *)options
                 completionHandler:(void (^)(NSError *error))completionHandler
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSData *data = [self charon_readResource:resource error:&error];
        BOOL wrote = data && [data writeToURL:fileURL options:NSDataWritingAtomic error:&error];
        if (wrote && options.progressHandler)
            options.progressHandler(1.0);
        if (completionHandler)
            completionHandler(wrote ? nil : (error ?: [CharonPhotosStore errorWithCode:-1 reason:@"the resource's data could not be written to that file"]));
    });
}

- (void)cancelDataRequest:(PHAssetResourceDataRequestID)requestID
{
}

@end
