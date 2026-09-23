#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// Ranks 16/17 of coordination/corpus/crash-demand-top.tsv, LOAD-FAIL, class_confirmed against
// both telegram and session's own trees. Two-step check first: apple.objc.inventory() against
// the armv7 shared cache of 6.1.3 confirms AVCapturePhotoOutput/AVCapturePhotoSettings/
// AVCaptureResolvedPhotoSettings do not exist under any name on this release - a genuine gap -
// while AVCaptureStillImageOutput, the class the header itself documents the new API as sitting
// above, is real, exported, and already a working AVCaptureOutput subclass on this release; grep
// of this tree's own .m files found no orphaned implementation already carrying a demanded
// selector. Ladder-walked with tools' own cache-by-cache inventory (not read from the SDK
// header's availability attribute, which names when Apple published the symbol, not when it
// first exports): all three classes first export at 10.0.1, not the header's bare "10.0".
//
// What Telegram's own delegate implementation resolved this design: the corpus's defcache for
// telegram defines *both*
// -captureOutput:didFinishProcessingPhoto:error: (the AVCapturePhoto-based, iOS 11+ callback) and
// -captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:
// (the original, iOS 10-era CMSampleBufferRef-based callback, deprecated in 13.0 but never
// removed) - the second is the one iOS 10 itself used before AVCapturePhoto existed, needs no
// AVCapturePhoto object (out of scope: not itself demanded, and would need image processing this
// release does not do for us), and is a real fallback path Telegram already ships for pre-11
// devices. This port targets exactly that path.
//
// On this release AVCapturePhotoOutput is an AVCaptureStillImageOutput itself, the one output class that captures
// stills, so the session builds and runs it as its own: 6.1.3's AVCaptureSession reads its own -outputs while it
// builds the graph at -startRunning and again while a capture runs, and an object standing beside the real output
// there (the first version of this port) made every capture end in AVFoundationErrorDomain -11800
// (facts/AVFoundation/AVCapturePhotoOutput.md, "Why the output is a still image output"). The SDK declares the
// class above AVCaptureOutput, so the implementation is declared under a name of its own and carries the class's
// name at run time.
__attribute__((objc_runtime_name("AVCapturePhotoOutput")))
@interface CharonPhotoOutput : AVCaptureStillImageOutput
@end

static AVCaptureDevice *CharonDeviceForConnection(AVCaptureConnection *connection)
{
    AVCaptureInputPort *port = connection.inputPorts.firstObject;
    AVCaptureInput *input = port.input;
    return [input isKindOfClass:[AVCaptureDeviceInput class]] ? ((AVCaptureDeviceInput *)input).device : nil;
}

@interface AVCaptureResolvedPhotoSettings ()
@property (nonatomic, readwrite) int64_t uniqueID;
@end

@implementation AVCaptureResolvedPhotoSettings
@synthesize uniqueID = _uniqueID;
@end

@implementation AVCapturePhotoSettings
{
    int64_t _charonUniqueID;
}

@synthesize format = _format;
@synthesize flashMode = _flashMode;
@synthesize autoStillImageStabilizationEnabled = _autoStillImageStabilizationEnabled;
@synthesize previewPhotoFormat = _previewPhotoFormat;

+ (int64_t)charon_nextUniqueID
{
    static int64_t counter;
    @synchronized ([AVCapturePhotoSettings class]) {
        return ++counter;
    }
}

- (instancetype)initCharonWithFormat:(NSDictionary<NSString *, id> *)format
{
    if ((self = [super init])) {
        _format = [format copy];
        _charonUniqueID = [AVCapturePhotoSettings charon_nextUniqueID];
        _flashMode = AVCaptureFlashModeOff;
    }
    return self;
}

+ (instancetype)photoSettings
{
    return [[self alloc] initCharonWithFormat:nil];
}

+ (instancetype)photoSettingsWithFormat:(NSDictionary<NSString *, id> *)format
{
    return [[self alloc] initCharonWithFormat:format];
}

- (int64_t)uniqueID
{
    return _charonUniqueID;
}

// The preview is drawn by the port from the captured still (facts/AVFoundation/AVCapturePhotoOutput.md),
// into the format CoreGraphics draws into directly.
- (NSArray<NSNumber *> *)availablePreviewPhotoPixelFormatTypes
{
    return @[@(kCVPixelFormatType_32BGRA)];
}

@end

@implementation CharonPhotoOutput
{
    BOOL _charonHighResolutionCaptureEnabled;
}

- (NSArray<NSNumber *> *)availablePhotoPixelFormatTypes
{
    return self.availableImageDataCVPixelFormatTypes ?: @[];
}

// iOS 6's AVCaptureStillImageOutput has no Bayer/Apple ProRAW capture path at all - real
// hardware and software support for RAW capture arrived with iOS 10's own AVCapturePhotoOutput,
// so an honestly empty array is correct here, not a stub standing in for one this port cannot
// build: nothing on this release could ever populate it.
- (NSArray<NSNumber *> *)availableRawPhotoPixelFormatTypes
{
    return @[];
}

- (NSArray<NSNumber *> *)supportedFlashModes
{
    AVCaptureDevice *device = CharonDeviceForConnection(self.connections.firstObject);
    if (!device)
        return @[@(AVCaptureFlashModeOff)];
    NSMutableArray<NSNumber *> *modes = [NSMutableArray arrayWithObject:@(AVCaptureFlashModeOff)];
    if ([device isFlashModeSupported:AVCaptureFlashModeOn])
        [modes addObject:@(AVCaptureFlashModeOn)];
    if ([device isFlashModeSupported:AVCaptureFlashModeAuto])
        [modes addObject:@(AVCaptureFlashModeAuto)];
    return modes;
}

// The real property "always returns NO unless you set photoSettingsForSceneMonitoring to a
// non-nil value" (Apple's own header). This port carries no scene-monitoring pipeline, so
// photoSettingsForSceneMonitoring is never non-nil, and NO is the release's own documented
// default answer for that state - not a fabricated default standing in for real monitoring.
- (BOOL)isFlashScene
{
    return NO;
}

// AVCaptureStillImageOutput already captures at the device's full active-format resolution by
// default (it has no separate preview-resolution/high-resolution distinction the way a video data
// output does), so there is no lower-resolution capture path this property would need to opt out
// of; it is real, settable storage rather than a fabricated always-on default, and observing it
// costs this port nothing to honor since the release's own still image path already behaves as if
// it were always enabled.
- (BOOL)isHighResolutionCaptureEnabled
{
    return _charonHighResolutionCaptureEnabled;
}

- (void)setHighResolutionCaptureEnabled:(BOOL)highResolutionCaptureEnabled
{
    _charonHighResolutionCaptureEnabled = highResolutionCaptureEnabled;
}

// Live Photo capture needs a motion/video pipeline paired to the still capture that this
// release's AVCaptureStillImageOutput has no counterpart for. Real AVCapturePhotoOutput throws
// NSInvalidArgumentException when livePhotoCaptureEnabled is set YES without
// livePhotoCaptureSupported also being YES; livePhotoCaptureSupported is unconditionally NO here,
// so this port reproduces that same real exception rather than silently accepting a YES it could
// never honor.
- (BOOL)isLivePhotoCaptureSupported
{
    return NO;
}

- (BOOL)isLivePhotoCaptureEnabled
{
    return NO;
}

- (void)setLivePhotoCaptureEnabled:(BOOL)livePhotoCaptureEnabled
{
    if (livePhotoCaptureEnabled)
        [NSException raise:NSInvalidArgumentException format:@"livePhotoCaptureEnabled may only be set to YES if livePhotoCaptureSupported is YES"];
}

// The longest side of the preview: "Width and height are only honored up to the display dimensions. If you
// specify a width and height whose aspect ratio differs from the RAW or processed photo, the larger of the two
// dimensions is honored and aspect ratio of the RAW or processed photo is always preserved" (the header); with
// no dimensions, the display's.
static size_t CharonPreviewLongestSide(NSDictionary *preview)
{
    UIScreen *screen = [UIScreen mainScreen];
    size_t display = (size_t)(MAX(screen.bounds.size.width, screen.bounds.size.height) * screen.scale);
    NSNumber *width = preview[(__bridge NSString *)kCVPixelBufferWidthKey], *height = preview[(__bridge NSString *)kCVPixelBufferHeightKey];
    if (!width || !height)
        return display;
    return MIN((size_t)MAX(width.unsignedIntegerValue, height.unsignedIntegerValue), display);
}

// The captured still as an image no longer on its longest side than `longest`: a JPEG through ImageIO's
// thumbnail, which decodes at the reduced size; an uncompressed buffer through CoreImage.
static CGImageRef CharonCreatePhotoImage(CMSampleBufferRef photo, size_t longest)
{
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(photo);
    if (format && CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_JPEG) {
        NSData *data = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:photo];
        CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
        if (!source)
            return NULL;
        NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                                  (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(longest)};
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        return image;
    }
    CVImageBufferRef buffer = CMSampleBufferGetImageBuffer(photo);
    CIImage *image = buffer ? [CIImage imageWithCVPixelBuffer:buffer] : nil;
    return image ? [[CIContext contextWithOptions:nil] createCGImage:image fromRect:image.extent] : NULL;
}

// The preview sample buffer: the still drawn into a 32BGRA pixel buffer whose longest side is `longest` (or
// the still's own, when that is smaller), with the still's presentation time.
static CMSampleBufferRef CharonCreatePreviewSample(CMSampleBufferRef photo, size_t longest)
{
    if (!photo)
        return NULL;
    CGImageRef image = CharonCreatePhotoImage(photo, longest);
    if (!image)
        return NULL;
    size_t imageWidth = CGImageGetWidth(image), imageHeight = CGImageGetHeight(image);
    double scale = MIN(1.0, (double)longest / MAX(imageWidth, imageHeight));
    size_t width = MAX((size_t)1, (size_t)llround(imageWidth * scale)), height = MAX((size_t)1, (size_t)llround(imageHeight * scale));
    CVPixelBufferRef pixels = NULL;
    NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    if (CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &pixels) != kCVReturnSuccess) {
        CGImageRelease(image);
        return NULL;
    }
    CVPixelBufferLockBaseAddress(pixels, 0);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixels), width, height, 8, CVPixelBufferGetBytesPerRow(pixels), space,
                                                 kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (context) {
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(pixels, 0);
    CGImageRelease(image);
    CMVideoFormatDescriptionRef description = NULL;
    CMSampleBufferRef sample = NULL;
    CMSampleTimingInfo timing = {kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(photo), kCMTimeInvalid};
    if (context && CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixels, &description) == noErr)
        CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixels, true, NULL, NULL, description, &timing, &sample);
    if (description)
        CFRelease(description);
    CVPixelBufferRelease(pixels);
    return sample;
}

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate
{
    NSDictionary *preview = settings.previewPhotoFormat;
    if (preview && ![settings.availablePreviewPhotoPixelFormatTypes containsObject:preview[(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey]]) {
        [NSException raise:NSInvalidArgumentException format:@"previewPhotoFormat's pixel format type must be present in availablePreviewPhotoPixelFormatTypes"];
        return;
    }
    if (preview && (preview[(__bridge NSString *)kCVPixelBufferWidthKey] == nil) != (preview[(__bridge NSString *)kCVPixelBufferHeightKey] == nil)) {
        [NSException raise:NSInvalidArgumentException format:@"previewPhotoFormat must give both kCVPixelBufferWidthKey and kCVPixelBufferHeightKey, or neither"];
        return;
    }
    size_t previewLongest = preview ? CharonPreviewLongestSide(preview) : 0;
    AVCaptureConnection *connection = [self connectionWithMediaType:AVMediaTypeVideo];
    if (!connection) {
        [NSException raise:NSInvalidArgumentException format:@"AVCapturePhotoOutput has no connection to capture from - add it to a running AVCaptureSession first"];
        return;
    }

    // Still image stabilization arrived on AVCaptureStillImageOutput in 7.0; 6.x has none, and the setting is then
    // what it is on a device without it: kept, and nothing to enable.
    if ([self respondsToSelector:@selector(setAutomaticallyEnablesStillImageStabilizationWhenAvailable:)])
        self.automaticallyEnablesStillImageStabilizationWhenAvailable = settings.autoStillImageStabilizationEnabled;
    // Every capture takes its own settings' format; without one, a photo settings object asks for a JPEG.
    self.outputSettings = settings.format ?: @{AVVideoCodecKey: AVVideoCodecJPEG};

    AVCaptureDevice *device = CharonDeviceForConnection(connection);
    AVCaptureFlashMode flashMode = settings.flashMode;
    if (device.hasFlash && [device isFlashModeSupported:flashMode] && [device lockForConfiguration:NULL]) {
        device.flashMode = flashMode;
        [device unlockForConfiguration];
    }

    AVCaptureResolvedPhotoSettings *resolved = ((id (*)(id, SEL))objc_msgSend)([AVCaptureResolvedPhotoSettings alloc], sel_registerName("init"));
    resolved.uniqueID = settings.uniqueID;

    AVCapturePhotoOutput *output = (AVCapturePhotoOutput *)(id)self;
    if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)])
        [delegate captureOutput:output willBeginCaptureForResolvedSettings:resolved];

    [self captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if ([delegate respondsToSelector:@selector(captureOutput:didCapturePhotoForResolvedSettings:)])
            [delegate captureOutput:output didCapturePhotoForResolvedSettings:resolved];
        if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:)]) {
            CMSampleBufferRef previewSample = previewLongest ? CharonCreatePreviewSample(imageDataSampleBuffer, previewLongest) : NULL;
            if (previewLongest && imageDataSampleBuffer && !previewSample)
                NSLog(@"AVCapturePhotoOutput: the preview photo asked for could not be made from the captured still; it is delivered without one");
            ((void (*)(id, SEL, id, CMSampleBufferRef, CMSampleBufferRef, id, id, id))objc_msgSend)(delegate, sel_registerName("captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:"),
                output, imageDataSampleBuffer, previewSample, resolved, nil, error);
            if (previewSample)
                CFRelease(previewSample);
        }
        if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)])
            [delegate captureOutput:output didFinishCaptureForResolvedSettings:resolved error:error];
    }];
}

@end
