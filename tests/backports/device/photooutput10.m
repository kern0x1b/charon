#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import "check.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// AVCapturePhotoOutput as the release's still image output (facts/AVFoundation/AVCapturePhotoOutput.md):
// the release's own output in the same session as the control, the formats offered, the refusals, real
// captures with a preview at the display's size and at a size asked for, an uncompressed photo, a zoomed
// one, the flash modes, and the resolved settings every capture reports. Built with AVCapturePhotoOutput.m and the
// zoom's files, as the library carries them. A process of its own: the camera needs no permission on 6.1.3.
// The camera's flash is held Off; a capture with the flash On runs only when asked, `photooutput <log> flash-on`, as it
// fires the flash of a device someone may be using.

@interface CharonPhotoCatcher : NSObject <AVCapturePhotoCaptureDelegate>
@property (atomic) BOOL finished;
@property (atomic) size_t photoWidth, photoHeight, previewWidth, previewHeight;
@property (atomic) OSType previewFormat;
@property (atomic) BOOL hadPreview, photoIsJPEG, photoIsBGRA;
// The mean difference per channel, in levels of 255, between the preview and the photo drawn at the preview's
// size by the probe, and the same against the photo turned upside down (the control: a preview that is not the
// photo, or is drawn the wrong way up, is as far from one as from the other).
@property (atomic) double previewDifference, flippedDifference, previewSpread;
@property (atomic, strong) NSError *error;
// The resolved settings each callback was given, and what they answered at willBeginCapture and at the photo.
@property (atomic, strong) NSMutableArray *resolvedSeen, *callbacks;
@property (atomic) CMVideoDimensions beganPhoto, beganPreview, resolvedPhoto, resolvedPreview, resolvedRaw, resolvedLive;
@property (atomic) BOOL beganFlash, resolvedFlash, resolvedStabilized;
@property (atomic) int64_t resolvedID;
// The Exif Flash tag the release attached to the still, -1 when there is none.
@property (atomic) long stillFlash;
@end

// The photo as an image: a JPEG through UIImage, a 32BGRA buffer through a bitmap context over its bytes.
static CGImageRef create_photo_image(CMSampleBufferRef photo, BOOL *jpeg, BOOL *bgra)
{
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(photo);
    if (format && CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_JPEG) {
        NSData *data = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:photo];
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        *jpeg = image != nil;
        return image ? CGImageRetain(image.CGImage) : NULL;
    }
    CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(photo);
    if (!pixels || CVPixelBufferGetPixelFormatType(pixels) != kCVPixelFormatType_32BGRA)
        return NULL;
    *bgra = YES;
    CVPixelBufferLockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixels), CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 8,
                                                 CVPixelBufferGetBytesPerRow(pixels), space, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGImageRef image = context ? CGBitmapContextCreateImage(context) : NULL;
    if (context)
        CGContextRelease(context);
    CGColorSpaceRelease(space);
    CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
    return image;
}

static double difference(CVPixelBufferRef preview, CGImageRef photo, BOOL flipped)
{
    size_t width = CVPixelBufferGetWidth(preview), height = CVPixelBufferGetHeight(preview);
    NSMutableData *drawn = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(drawn.mutableBytes, width, height, 8, width * 4, space, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (flipped) {
        CGContextTranslateCTM(context, 0, height);
        CGContextScaleCTM(context, 1, -1);
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), photo);
    CGContextRelease(context);
    CVPixelBufferLockBaseAddress(preview, kCVPixelBufferLock_ReadOnly);
    const uint8_t *base = CVPixelBufferGetBaseAddress(preview), *ours = drawn.bytes;
    size_t row = CVPixelBufferGetBytesPerRow(preview);
    double total = 0;
    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++)
            for (int c = 0; c < 3; c++)
                total += abs((int)base[y * row + x * 4 + c] - (int)ours[(y * width + x) * 4 + c]);
    CVPixelBufferUnlockBaseAddress(preview, kCVPixelBufferLock_ReadOnly);
    return total / (width * height * 3);
}

// How much the picture varies: the mean distance of a channel from its mean, in levels of 255. A picture of one
// colour, which any wrong drawing could match, has none.
static double spread(CVPixelBufferRef preview)
{
    size_t width = CVPixelBufferGetWidth(preview), height = CVPixelBufferGetHeight(preview), row = CVPixelBufferGetBytesPerRow(preview);
    CVPixelBufferLockBaseAddress(preview, kCVPixelBufferLock_ReadOnly);
    const uint8_t *base = CVPixelBufferGetBaseAddress(preview);
    double mean[3] = {0, 0, 0}, total = 0;
    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++)
            for (int c = 0; c < 3; c++)
                mean[c] += base[y * row + x * 4 + c];
    for (int c = 0; c < 3; c++)
        mean[c] /= width * height;
    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++)
            for (int c = 0; c < 3; c++)
                total += fabs(base[y * row + x * 4 + c] - mean[c]);
    CVPixelBufferUnlockBaseAddress(preview, kCVPixelBufferLock_ReadOnly);
    printf("preview mean B %.1f G %.1f R %.1f\n", mean[0], mean[1], mean[2]);
    return total / (width * height * 3);
}

@implementation CharonPhotoCatcher

- (instancetype)init
{
    if ((self = [super init])) {
        _resolvedSeen = [NSMutableArray array];
        _callbacks = [NSMutableArray array];
    }
    return self;
}

- (void)captureOutput:(AVCapturePhotoOutput *)output willBeginCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolved
{
    [self.resolvedSeen addObject:resolved];
    [self.callbacks addObject:@"willBegin"];
    self.beganPhoto = resolved.photoDimensions;
    self.beganPreview = resolved.previewDimensions;
    self.beganFlash = resolved.flashEnabled;
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didCapturePhotoForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolved
{
    [self.resolvedSeen addObject:resolved];
    [self.callbacks addObject:@"didCapture"];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolved error:(NSError *)error
{
    [self.resolvedSeen addObject:resolved];
    [self.callbacks addObject:@"didFinishCapture"];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photo
    previewPhotoSampleBuffer:(CMSampleBufferRef)preview resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolved
    bracketSettings:(AVCaptureBracketedStillImageSettings *)bracket error:(NSError *)error
{
    self.error = error;
    [self.resolvedSeen addObject:resolved];
    [self.callbacks addObject:@"didFinishProcessing"];
    self.resolvedID = resolved.uniqueID;
    self.resolvedPhoto = resolved.photoDimensions;
    self.resolvedPreview = resolved.previewDimensions;
    self.resolvedRaw = resolved.rawPhotoDimensions;
    self.resolvedLive = resolved.livePhotoMovieDimensions;
    self.resolvedFlash = resolved.flashEnabled;
    self.resolvedStabilized = resolved.stillImageStabilizationEnabled;
    CFDictionaryRef exif = photo ? CMGetAttachment(photo, kCGImagePropertyExifDictionary, NULL) : NULL;
    NSNumber *flashTag = exif ? ((__bridge NSDictionary *)exif)[(__bridge NSString *)kCGImagePropertyExifFlash] : nil;
    self.stillFlash = flashTag ? flashTag.longValue : -1;
    BOOL jpeg = NO, bgra = NO;
    CGImageRef image = photo ? create_photo_image(photo, &jpeg, &bgra) : NULL;
    self.photoIsJPEG = jpeg;
    self.photoIsBGRA = bgra;
    self.photoWidth = image ? CGImageGetWidth(image) : 0;
    self.photoHeight = image ? CGImageGetHeight(image) : 0;
    CVImageBufferRef pixels = preview ? CMSampleBufferGetImageBuffer(preview) : NULL;
    self.hadPreview = pixels != NULL;
    if (pixels) {
        self.previewWidth = CVPixelBufferGetWidth(pixels);
        self.previewHeight = CVPixelBufferGetHeight(pixels);
        self.previewFormat = CVPixelBufferGetPixelFormatType(pixels);
        if (image && self.previewFormat == kCVPixelFormatType_32BGRA) {
            self.previewDifference = difference(pixels, image, NO);
            self.flippedDifference = difference(pixels, image, YES);
            self.previewSpread = spread(pixels);
        }
    }
    if (image)
        CGImageRelease(image);
    self.finished = YES;
}

@end

static NSString *raised(void (^block)(void))
{
    @try {
        block();
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
    }
    return @"nothing";
}

static BOOL same_dimensions(CMVideoDimensions a, CMVideoDimensions b)
{
    return a.width == b.width && a.height == b.height;
}

// What the header says of the resolved settings, against what the capture delivered: one object for every callback of
// the request, under the request's unique ID, answering at willBeginCapture the dimensions of the photo and preview
// buffers that come after, no RAW photo and no Live Photo movie (none asked for, none this release can make), and no
// still image stabilization on 6.x, which has none.
static void check_resolved(CharonPhotoCatcher *c, AVCapturePhotoSettings *settings)
{
    AVCaptureResolvedPhotoSettings *first = c.resolvedSeen.firstObject;
    BOOL one = c.resolvedSeen.count == 4;
    for (id seen in c.resolvedSeen)
        one = one && seen == first;
    CMVideoDimensions photo = c.resolvedPhoto, preview = c.resolvedPreview, began = c.beganPhoto;
    printf("resolved: %d x %zu callbacks, id %lld of %lld, photo %dx%d (at will begin %dx%d), preview %dx%d, raw %dx%d, live %dx%d, flash %d, stabilized %d\n",
           one, c.resolvedSeen.count, c.resolvedID, settings.uniqueID, photo.width, photo.height, began.width, began.height, preview.width, preview.height,
           c.resolvedRaw.width, c.resolvedRaw.height, c.resolvedLive.width, c.resolvedLive.height, c.resolvedFlash, c.resolvedStabilized);
    CHECK(one && c.resolvedID == settings.uniqueID, "every callback of a capture gets one resolved settings, under the request's unique ID");
    CHECK_EQUAL(c.callbacks, (@[@"willBegin", @"didCapture", @"didFinishProcessing", @"didFinishCapture"]), "in the header's order");
    CHECK(photo.width == (int32_t)c.photoWidth && photo.height == (int32_t)c.photoHeight, "its photo dimensions are the photo's");
    CHECK(same_dimensions(preview, (CMVideoDimensions){(int32_t)c.previewWidth, (int32_t)c.previewHeight}), "its preview dimensions the preview's, 0x0 with none");
    CHECK(same_dimensions(began, photo) && same_dimensions(c.beganPreview, preview) && c.beganFlash == c.resolvedFlash, "and it says both already at willBeginCapture");
    CHECK(same_dimensions(c.resolvedRaw, (CMVideoDimensions){0, 0}) && same_dimensions(c.resolvedLive, (CMVideoDimensions){0, 0}), "no RAW photo, no Live Photo movie");
    CHECK(!c.resolvedStabilized, "no still image stabilization on this release");
    CHECK(settings.flashMode != AVCaptureFlashModeOff || !c.resolvedFlash, "the flash is not enabled when it is asked Off");
}

static CharonPhotoCatcher *capture_with(AVCapturePhotoOutput *output, AVCapturePhotoSettings *settings, NSDictionary *preview)
{
    settings.previewPhotoFormat = preview;
    CharonPhotoCatcher *catcher = [[CharonPhotoCatcher alloc] init];
    AVCaptureInputPort *port = [output connectionWithMediaType:AVMediaTypeVideo].inputPorts.firstObject;
    CMVideoDimensions portDimensions = port.formatDescription ? CMVideoFormatDescriptionGetDimensions(port.formatDescription) : (CMVideoDimensions){0, 0};
    printf("port before the capture: %s %dx%d\n", port.formatDescription ? "format" : "no format", portDimensions.width, portDimensions.height);
    [output capturePhotoWithSettings:settings delegate:catcher];
    for (int i = 0; i < 200 && !catcher.finished; i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    printf("capture: finished %d, error %s, preview against the photo %.2f, upside down %.2f, spread %.2f\n", catcher.finished,
           catcher.error.description.UTF8String ?: "none", catcher.previewDifference, catcher.flippedDifference, catcher.previewSpread);
    if (catcher.finished)
        check_resolved(catcher, settings);
    return catcher;
}

static CharonPhotoCatcher *capture(AVCapturePhotoOutput *output, NSDictionary *preview)
{
    return capture_with(output, [AVCapturePhotoSettings photoSettings], preview);
}

// The preview is the photo, drawn the right way up: within a few levels of the probe's own drawing of it, and
// further from the photo turned upside down.
static BOOL drawn_from_photo(CharonPhotoCatcher *c)
{
    return c.hadPreview && c.previewDifference < 6 && c.flippedDifference > c.previewDifference;
}

// The control: the release's own still image output, captured the way the facade captures, so a failure can be
// told from the release's answer.
static BOOL bare_capture(AVCaptureStillImageOutput *still, const char *label)
{
    AVCaptureConnection *connection = [still connectionWithMediaType:AVMediaTypeVideo];
    __block BOOL finished = NO;
    __block NSError *failure = nil;
    __block size_t width = 0, height = 0;
    printf("%s: connection %p active %d enabled %d, capturing %d\n", label, (__bridge void *)connection, connection.active, connection.enabled,
           still.capturingStillImage);
    [still captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef buffer, NSError *error) {
        failure = error;
        NSData *data = buffer ? [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:buffer] : nil;
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        width = (size_t)CGImageGetWidth(image.CGImage);
        height = (size_t)CGImageGetHeight(image.CGImage);
        finished = YES;
    }];
    for (int i = 0; i < 200 && !finished; i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    printf("%s: finished %d, photo %zux%zu, error %s\n", label, finished, width, height, failure.description.UTF8String ?: "none");
    return finished && !failure && width > 0;
}

// The preview keeps the photo's aspect ratio to within the rounding of one pixel.
static BOOL same_aspect(CharonPhotoCatcher *c)
{
    double photo = (double)c.photoWidth / c.photoHeight, preview = (double)c.previewWidth / c.previewHeight;
    return fabs(photo * c.previewHeight - c.previewWidth) <= 1 || fabs(preview - photo) < 0.01;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1)
            charon_log_to(@(argv[1]));
        AVCapturePhotoSettings *probe = [AVCapturePhotoSettings photoSettings];
        CHECK_EQUAL(probe.availablePreviewPhotoPixelFormatTypes, @[@(kCVPixelFormatType_32BGRA)], "32BGRA is the preview format offered");

        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        session.sessionPreset = AVCaptureSessionPresetPhoto;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] error:NULL];
        [session addInput:input];
        AVCaptureDevice *camera = input.device;
        AVCaptureFlashMode cameraFlash = camera.flashMode;
        BOOL flashOn = argc > 2 && strcmp(argv[2], "flash-on") == 0;
        if (camera.hasFlash && [camera lockForConfiguration:NULL]) {
            camera.flashMode = AVCaptureFlashModeOff;
            [camera unlockForConfiguration];
        }

        AVCaptureStillImageOutput *bare = [[AVCaptureStillImageOutput alloc] init];
        CHECK(input && [session canAddOutput:bare], "the camera and the release's still image output go into a session");
        [session addOutput:bare];
        [session startRunning];
        [NSThread sleepForTimeInterval:2];
        CHECK(bare_capture(bare, "control 1"), "the release's still image output captures a JPEG");
        CHECK(bare_capture(bare, "control 2"), "and captures again");
        [session beginConfiguration];
        [session removeOutput:bare];
        [session commitConfiguration];

        AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];
        CHECK([session canAddOutput:output], "the photo output goes into the same session");
        [session beginConfiguration];
        [session addOutput:output];
        [session commitConfiguration];
        [NSThread sleepForTimeInterval:2];
        CHECK_EQUAL(NSStringFromClass([output class]), @"AVCapturePhotoOutput", "the photo output keeps its class's name");
        CHECK([session.outputs containsObject:output], "and the session's outputs hold it");

        NSString *wrongFormat = raised(^{ capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}); });
        CHECK([wrongFormat hasPrefix:@"NSInvalidArgumentException"], "a preview format not offered raises");
        NSString *halfSize = raised(^{ capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                         (__bridge NSString *)kCVPixelBufferWidthKey: @160}); });
        CHECK([halfSize hasPrefix:@"NSInvalidArgumentException"], "a width without a height raises");

        CharonPhotoCatcher *none = capture(output, nil);
        CHECK(none.finished && none.photoIsJPEG && !none.hadPreview, "without a preview format the photo comes alone");

        UIScreen *screen = [UIScreen mainScreen];
        size_t display = (size_t)(MAX(screen.bounds.size.width, screen.bounds.size.height) * screen.scale);
        CharonPhotoCatcher *full = capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)});
        printf("photo %zux%zu, display longest %zu, preview %zux%zu format %08x\n", full.photoWidth, full.photoHeight, display, full.previewWidth, full.previewHeight,
               (unsigned)full.previewFormat);
        CHECK(full.finished && full.error == nil && full.hadPreview, "a preview comes with the photo");
        CHECK(full.previewFormat == kCVPixelFormatType_32BGRA, "in 32BGRA");
        CHECK(MAX(full.previewWidth, full.previewHeight) == MIN(display, MAX(full.photoWidth, full.photoHeight)), "at the display's size, or the photo's when smaller");
        CHECK(same_aspect(full), "with the photo's aspect ratio");
        CHECK(drawn_from_photo(full), "and it is the photo, drawn the right way up");

        CharonPhotoCatcher *asked = capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                      (__bridge NSString *)kCVPixelBufferWidthKey: @160, (__bridge NSString *)kCVPixelBufferHeightKey: @160});
        printf("asked 160x160: preview %zux%zu\n", asked.previewWidth, asked.previewHeight);
        CHECK(asked.hadPreview && MAX(asked.previewWidth, asked.previewHeight) == 160, "a size asked for sets the longest side");
        CHECK(same_aspect(asked), "and the photo's aspect ratio is kept, not the one asked");
        CHECK(drawn_from_photo(asked), "and it is the photo at that size");

        CharonPhotoCatcher *huge = capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                     (__bridge NSString *)kCVPixelBufferWidthKey: @100000, (__bridge NSString *)kCVPixelBufferHeightKey: @100000});
        CHECK(huge.hadPreview && MAX(huge.previewWidth, huge.previewHeight) == MAX(full.previewWidth, full.previewHeight), "a size past the display is held to it");

        // An uncompressed photo: its preview is drawn through CoreImage, and the next photo settings without a format
        // ask for a JPEG again.
        NSArray *formats = output.availablePhotoPixelFormatTypes;
        printf("photo pixel formats:");
        for (NSNumber *format in formats)
            printf(" %08x", format.unsignedIntValue);
        printf("\n");
        CHECK([formats containsObject:@(kCVPixelFormatType_32BGRA)], "the photo output offers the release's uncompressed 32BGRA");
        AVCapturePhotoSettings *uncompressed = [AVCapturePhotoSettings photoSettingsWithFormat:@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
        CharonPhotoCatcher *raw = capture_with(output, uncompressed, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                                        (__bridge NSString *)kCVPixelBufferWidthKey: @320, (__bridge NSString *)kCVPixelBufferHeightKey: @320});
        printf("uncompressed: photo %zux%zu bgra %d, preview %zux%zu\n", raw.photoWidth, raw.photoHeight, raw.photoIsBGRA, raw.previewWidth, raw.previewHeight);
        CHECK(raw.finished && raw.error == nil && raw.photoIsBGRA, "a format asked for gives an uncompressed photo");
        CHECK(MAX(raw.previewWidth, raw.previewHeight) == 320 && same_aspect(raw) && drawn_from_photo(raw), "whose preview is the photo at the size asked");
        CharonPhotoCatcher *again = capture(output, nil);
        CHECK(again.finished && again.photoIsJPEG, "the next settings without a format take a JPEG again");

        // The zoom of iOS 7 over the still image connection's own scale and crop: the photo output is zoomed as any
        // still image output is, and still captures.
        AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
        printf("zoom: max %.2f, connection max %.2f\n", camera.activeFormat.videoMaxZoomFactor, connection.videoMaxScaleAndCropFactor);
        CGFloat zoom = MIN((CGFloat)2, MIN(camera.activeFormat.videoMaxZoomFactor, connection.videoMaxScaleAndCropFactor));
        if (zoom > 1 && [camera lockForConfiguration:NULL]) {
            camera.videoZoomFactor = zoom;
            [camera unlockForConfiguration];
            CharonPhotoCatcher *zoomed = capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)});
            printf("zoomed %.2f: connection %.2f, photo %zux%zu, preview %zux%zu\n", zoom, connection.videoScaleAndCropFactor, zoomed.photoWidth, zoomed.photoHeight,
                   zoomed.previewWidth, zoomed.previewHeight);
            CHECK(connection.videoScaleAndCropFactor == zoom, "the zoom sets the photo output's scale and crop");
            CHECK(zoomed.finished && zoomed.error == nil && zoomed.photoIsJPEG && drawn_from_photo(zoomed), "and a zoomed photo comes with its preview");
            if ([camera lockForConfiguration:NULL]) {
                camera.videoZoomFactor = 1;
                [camera unlockForConfiguration];
            }
        } else {
            printf("zoom: this camera does not scale and crop its stills\n");
        }

        // The flash: the header offers the modes of the camera behind the output, Off, On and Auto for a camera with a
        // flash and Off alone for one without (the iPad 2). A capture takes its settings' mode onto the camera, where the
        // release's still image output reads it, and a photo still comes; the resolved settings say the flash is enabled
        // as the still's own Exif Flash tag says it fired (bit 0). On only when asked (above).
        NSSet *flashModes = [NSSet setWithArray:output.supportedFlashModes];
        NSSet *cameraModes = camera.hasFlash ? [NSSet setWithObjects:@(AVCaptureFlashModeOff), @(AVCaptureFlashModeOn), @(AVCaptureFlashModeAuto), nil]
                                             : [NSSet setWithObject:@(AVCaptureFlashModeOff)];
        printf("flash: camera has one %d, modes offered %s\n", camera.hasFlash, [[output.supportedFlashModes componentsJoinedByString:@" "] UTF8String]);
        CHECK_EQUAL(flashModes, cameraModes, "the flash modes offered are the camera's");
        if (camera.hasFlash) {
            NSArray *modes = flashOn ? @[@(AVCaptureFlashModeOn), @(AVCaptureFlashModeOff)] : @[@(AVCaptureFlashModeOff)];
            for (NSNumber *mode in modes) {
                AVCapturePhotoSettings *flash = [AVCapturePhotoSettings photoSettings];
                flash.flashMode = mode.integerValue;
                CharonPhotoCatcher *lit = capture_with(output, flash, nil);
                printf("flash %ld: camera mode %ld, available %d, photo %zux%zu, resolved flash %d, Exif Flash %ld\n", (long)mode.integerValue,
                       (long)camera.flashMode, camera.flashAvailable, lit.photoWidth, lit.photoHeight, lit.resolvedFlash, lit.stillFlash);
                CHECK(camera.flashMode == mode.integerValue, "a capture sets its flash mode on the camera");
                CHECK(lit.finished && lit.error == nil && lit.photoIsJPEG, "and the photo comes");
                CHECK(lit.stillFlash >= 0, "the still says in its Exif whether the flash fired");
                CHECK(lit.resolvedFlash == (lit.stillFlash >= 0 && (lit.stillFlash & 1)), "and the resolved settings say the same");
            }
            if (!flashOn)
                printf("flash: the On capture is not run; `flash-on` runs it\n");
        }
        [session beginConfiguration];
        [session removeOutput:output];
        [session addOutput:bare];
        [session commitConfiguration];
        CHECK(![session.outputs containsObject:output] && [session.outputs containsObject:bare], "removed, the session's outputs no longer hold it");
        [NSThread sleepForTimeInterval:2];
        CHECK(bare_capture(bare, "control after"), "the release's still image output still captures after the photo output");
        [session stopRunning];
        if (camera.hasFlash && [camera lockForConfiguration:NULL]) {
            camera.flashMode = cameraFlash;
            [camera unlockForConfiguration];
        }
        printf("%d checks, %d failed\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
