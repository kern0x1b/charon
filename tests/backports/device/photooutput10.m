#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "check.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// AVCapturePhotoOutput's preview photo over the release's still image output
// (facts/AVFoundation/AVCapturePhotoOutput.md): the formats offered, the refusals, and a real capture
// with a preview at the display's size and at a size asked for. A process of its own: the camera needs
// no permission on 6.1.3.

@interface CharonPhotoCatcher : NSObject <AVCapturePhotoCaptureDelegate>
@property (atomic) BOOL finished;
@property (atomic) size_t photoWidth, photoHeight, previewWidth, previewHeight;
@property (atomic) OSType previewFormat;
@property (atomic) BOOL hadPreview, photoIsJPEG;
@property (atomic, strong) NSError *error;
@end

@implementation CharonPhotoCatcher

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photo
    previewPhotoSampleBuffer:(CMSampleBufferRef)preview resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolved
    bracketSettings:(AVCaptureBracketedStillImageSettings *)bracket error:(NSError *)error
{
    self.error = error;
    if (photo) {
        NSData *data = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:photo];
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        self.photoIsJPEG = image != nil;
        self.photoWidth = (size_t)CGImageGetWidth(image.CGImage);
        self.photoHeight = (size_t)CGImageGetHeight(image.CGImage);
    }
    CVImageBufferRef pixels = preview ? CMSampleBufferGetImageBuffer(preview) : NULL;
    self.hadPreview = pixels != NULL;
    if (pixels) {
        self.previewWidth = CVPixelBufferGetWidth(pixels);
        self.previewHeight = CVPixelBufferGetHeight(pixels);
        self.previewFormat = CVPixelBufferGetPixelFormatType(pixels);
    }
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

static CharonPhotoCatcher *capture(AVCapturePhotoOutput *output, NSDictionary *preview)
{
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    settings.previewPhotoFormat = preview;
    CharonPhotoCatcher *catcher = [[CharonPhotoCatcher alloc] init];
    [output capturePhotoWithSettings:settings delegate:catcher];
    for (int i = 0; i < 200 && !catcher.finished; i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    printf("capture: finished %d, error %s\n", catcher.finished, catcher.error.description.UTF8String ?: "none");
    return catcher;
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
        AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];
        CHECK(input && [session canAddInput:input] && [session canAddOutput:output], "the camera and the photo output go into a session");
        [session addInput:input];
        [session addOutput:output];
        [session startRunning];
        [NSThread sleepForTimeInterval:2];

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

        CharonPhotoCatcher *asked = capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                      (__bridge NSString *)kCVPixelBufferWidthKey: @160, (__bridge NSString *)kCVPixelBufferHeightKey: @160});
        printf("asked 160x160: preview %zux%zu\n", asked.previewWidth, asked.previewHeight);
        CHECK(asked.hadPreview && MAX(asked.previewWidth, asked.previewHeight) == 160, "a size asked for sets the longest side");
        CHECK(same_aspect(asked), "and the photo's aspect ratio is kept, not the one asked");

        CharonPhotoCatcher *huge = capture(output, @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                                     (__bridge NSString *)kCVPixelBufferWidthKey: @100000, (__bridge NSString *)kCVPixelBufferHeightKey: @100000});
        CHECK(huge.hadPreview && MAX(huge.previewWidth, huge.previewHeight) == MAX(full.previewWidth, full.previewHeight), "a size past the display is held to it");
        [session stopRunning];
        printf("%d checks, %d failed\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
