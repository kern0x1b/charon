// ARReferenceImage.m - a reference image a session is asked to track, at 11.3 where it arrived.
//
// A reference image is a picture of a thing in the world and its real width, and the session finds it
// in the camera's frames by looking for that thing. There is no sensor in it beyond the camera the
// session is already running, so on this device it is carried whole: a caller builds one from a
// `CGImage` or a pixel buffer and the session is asked to track it, and nothing here needs a sensor
// the release has not.
//
// The width is what makes it a measurement rather than a label. A picture of a door with no width is a
// picture; with a width it is a size the session can compare a tracked shape against, and it is that
// comparison that reports `estimatedScaleFactor` on the anchor. So the width is carried as given, and a
// caller that gives none has said something the framework cannot use - which is what the validation
// completion handler is for.
//
// This is an 11.3 object: `ARReferenceImage` and `ARImageAnchor` arrived together at 11.3, and
// `ARImageTrackingConfiguration`'s `trackingImages` is 11.3's too. The 13.0 members below are in their
// own object.

#import <ARKit/ARKit.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <simd/simd.h>

#import "CharonARKitPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARReferenceImage ()
@property (nonatomic, assign) CGSize imageSize;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, copy, nullable) NSString *group;
@end

@implementation ARReferenceImage

@synthesize name = _name;
@synthesize physicalSize = _physicalSize;
@synthesize resourceGroupName = _resourceGroupName;
@synthesize imageSize = _imageSize;
@synthesize width = _width;
@synthesize group = _group;

/// The physical size is the width the caller gave and the picture's own aspect ratio: a 1.0 m door in a
/// 3:2 picture is 1.0 m by 0.667 m, and that ratio is the whole of what the picture contributes.
static CGSize CharonPhysicalSize(CGSize pixels, CGFloat physicalWidth)
{
    if (pixels.width <= 0 || pixels.height <= 0)
        return CGSizeZero;
    if (physicalWidth <= 0)
        return CGSizeZero;
    return CGSizeMake(physicalWidth, physicalWidth * pixels.height / pixels.width);
}

- (instancetype)initWithCGImage:(CGImageRef)image
                     orientation:(CGImagePropertyOrientation)orientation
                  physicalWidth:(CGFloat)physicalWidth
{
    // A nil picture is not a reference image, and the framework's own signature is nonnull, so this
    // returns nil rather than an object that matches nothing.
    if (!image)
        return nil;
    self = [super init];
    if (!self)
        return nil;
    _imageSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    _width = physicalWidth;
    _physicalSize = CharonPhysicalSize(_imageSize, physicalWidth);
    return self;
}

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                         orientation:(CGImagePropertyOrientation)orientation
                      physicalWidth:(CGFloat)physicalWidth
{
    if (!pixelBuffer)
        return nil;
    self = [super init];
    if (!self)
        return nil;
    _imageSize = CGSizeMake(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    _width = physicalWidth;
    _physicalSize = CharonPhysicalSize(_imageSize, physicalWidth);
    return self;
}

+ (nullable NSSet<ARReferenceImage *> *)referenceImagesInGroupNamed:(NSString *)name
                                                            bundle:(nullable NSBundle *)bundle
{
    // A reference-image group is a folder named `<name>.arreferenceimage` in a bundle's resource
    // directory, and inside it a `Contents.json` naming the picture and its real width. That is the
    // format the framework reads, and reading it is the whole of this method: there is no camera
    // involved in assembling a group, only in tracking what it holds.
    if (!name)
        return nil;
    NSBundle *where = bundle ?: [NSBundle mainBundle];
    NSString *folder = [where pathForResource:name ofType:@"arreferenceimage"];
    if (!folder)
        return nil;

    NSString *contents = [folder stringByAppendingPathComponent:@"Contents.json"];
    NSData *json = [NSData dataWithContentsOfFile:contents];
    if (!json)
        return nil;
    NSDictionary *described = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    if (![described isKindOfClass:[NSDictionary class]])
        return nil;

    NSString *picture = described[@"image"];
    NSNumber *width = described[@"width"];
    if (![picture isKindOfClass:[NSString class]] || ![width isKindOfClass:[NSNumber class]])
        return nil;
    NSString *path = [folder stringByAppendingPathComponent:picture];
    NSData *bytes = [NSData dataWithContentsOfFile:path];
    if (!bytes)
        return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)bytes, NULL);
    if (!source)
        return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image)
        return nil;

    ARReferenceImage *reference = [[self alloc] initWithCGImage:image
                                                     orientation:kCGImagePropertyOrientationUp
                                                  physicalWidth:(CGFloat)width.doubleValue];
    CGImageRelease(image);
    if (!reference)
        return nil;
    reference.name = name;
    reference.group = folder.lastPathComponent;
    return [NSSet setWithObject:reference];
}

- (void)validateWithCompletionHandler:(void (^)(NSError *_Nullable))completionHandler
{
    if (!completionHandler)
        return;
    // What validation can say without the images: a picture with no pixels, or a width that is not a
    // width. Anything else is whether the session can find the thing in a frame, which needs frames.
    NSError *error = nil;
    if (_imageSize.width <= 0 || _imageSize.height <= 0)
        error = [NSError errorWithDomain:@"space.kern0x1b.arkit" code:10
                                userInfo:@{ NSLocalizedDescriptionKey:
                                                @"the reference image has no pixels" }];
    else if (_width <= 0)
        error = [NSError errorWithDomain:@"space.kern0x1b.arkit" code:11
                                userInfo:@{ NSLocalizedDescriptionKey:
                                                @"the reference image has no physical width, so a tracked shape has nothing to be measured against" }];
    dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(error); });
}

@end

NS_ASSUME_NONNULL_END
