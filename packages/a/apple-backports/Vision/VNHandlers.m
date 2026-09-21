#import "CharonVision.h"
#import <ImageIO/ImageIO.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

static NSError *charon_vision_failure(VNRequest *request)
{
    Class cls = [request class];
    if (![[cls supportedRevisions] containsIndex:request.revision])
        return charon_vision_error(VNErrorUnsupportedRevision, [NSString stringWithFormat:@"%@ does not support %@Revision%lu", NSStringFromClass(cls), NSStringFromClass(cls), (unsigned long)request.revision]);
    if ([request isKindOfClass:[VNCoreMLRequest class]] && ![(VNCoreMLRequest *)request model])
        return charon_vision_error(VNErrorInvalidModel, @"The model does not have a valid input feature of type image");
    return charon_vision_error(VNErrorNotImplemented, [NSString stringWithFormat:@"%@ is not implemented on this release", NSStringFromClass(cls)]);
}

static BOOL charon_vision_perform(NSArray<VNRequest *> *requests, NSError **error)
{
    BOOL succeeded = YES;
    NSError *first = nil;
    for (VNRequest *request in requests) {
        NSError *failure = charon_vision_failure(request);
        if (failure) {
            succeeded = NO;
            first = first ?: failure;
        }
        VNRequestCompletionHandler handler = request.completionHandler;
        if (handler)
            handler(request, failure);
    }
    if (!succeeded && error)
        *error = first;
    return succeeded;
}

@implementation VNImageRequestHandler {
    id _image;
    CGImagePropertyOrientation _orientation;
    NSDictionary *_options;
}

- (instancetype)initWithImage:(id)image orientation:(CGImagePropertyOrientation)orientation options:(NSDictionary *)options
{
    if ((self = [super init])) {
        _image = image;
        _orientation = orientation;
        _options = [options copy];
    }
    return self;
}

- (instancetype)initWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer options:(NSDictionary *)options
{
    return [self initWithCVPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationUp options:options];
}

- (instancetype)initWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer orientation:(CGImagePropertyOrientation)orientation options:(NSDictionary *)options
{
    return [self initWithImage:(__bridge id)pixelBuffer orientation:orientation options:options];
}

- (instancetype)initWithCGImage:(CGImageRef)image options:(NSDictionary *)options
{
    return [self initWithCGImage:image orientation:kCGImagePropertyOrientationUp options:options];
}

- (instancetype)initWithCGImage:(CGImageRef)image orientation:(CGImagePropertyOrientation)orientation options:(NSDictionary *)options
{
    return [self initWithImage:(__bridge id)image orientation:orientation options:options];
}

- (instancetype)initWithCIImage:(CIImage *)image options:(NSDictionary *)options
{
    return [self initWithCIImage:image orientation:kCGImagePropertyOrientationUp options:options];
}

- (instancetype)initWithCIImage:(CIImage *)image orientation:(CGImagePropertyOrientation)orientation options:(NSDictionary *)options
{
    return [self initWithImage:image orientation:orientation options:options];
}

- (instancetype)initWithURL:(NSURL *)imageURL options:(NSDictionary *)options
{
    return [self initWithURL:imageURL orientation:kCGImagePropertyOrientationUp options:options];
}

- (instancetype)initWithURL:(NSURL *)imageURL orientation:(CGImagePropertyOrientation)orientation options:(NSDictionary *)options
{
    return [self initWithImage:imageURL orientation:orientation options:options];
}

- (instancetype)initWithData:(NSData *)imageData options:(NSDictionary *)options
{
    return [self initWithData:imageData orientation:kCGImagePropertyOrientationUp options:options];
}

- (instancetype)initWithData:(NSData *)imageData orientation:(CGImagePropertyOrientation)orientation options:(NSDictionary *)options
{
    return [self initWithImage:imageData orientation:orientation options:options];
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

@end

@implementation VNSequenceRequestHandler

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onCVPixelBuffer:(CVPixelBufferRef)pixelBuffer error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onCVPixelBuffer:(CVPixelBufferRef)pixelBuffer orientation:(CGImagePropertyOrientation)orientation error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onCGImage:(CGImageRef)image error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onCGImage:(CGImageRef)image orientation:(CGImagePropertyOrientation)orientation error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onCIImage:(CIImage *)image error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onCIImage:(CIImage *)image orientation:(CGImagePropertyOrientation)orientation error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onImageURL:(NSURL *)imageURL error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onImageURL:(NSURL *)imageURL orientation:(CGImagePropertyOrientation)orientation error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onImageData:(NSData *)imageData error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

- (BOOL)performRequests:(NSArray<VNRequest *> *)requests onImageData:(NSData *)imageData orientation:(CGImagePropertyOrientation)orientation error:(NSError **)error
{
    return charon_vision_perform(requests, error);
}

@end
