// What a caller gets from the 13.0 classes about the protocols their own headers declare, and about
// the defaults their headers state. The port's classes are compiled here under names of their own, so
// every answer comes from the port and not from the Vision of this host -- the same check
// tests/backports/host/vision/run.sh makes, and a name that is no class at all is asked for as the
// control.
//
// It needs the rename header the way tests/backports/host/vision/run.sh makes it, so that the port's
// own classes are the ones being asked and an answer cannot come from the Vision of this host:
//
//   sdk=$(xcrun --show-sdk-path)
//   clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" \
//       -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w \
//       -include rename.h -I packages/a/apple-backports/Vision \
//       -framework Foundation -framework Vision -framework CoreGraphics -framework CoreImage \
//       -framework CoreVideo -framework CoreML -framework ImageIO \
//       tools/vision/conforms130.m packages/a/apple-backports/Vision/*.c \
//       packages/a/apple-backports/Vision/*.m -o conforms130 && ./conforms130
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include <string.h>

static const char *leaf(const char *path)
{
    const char *mark = strrchr(path, '/');
    return mark ? mark + 1 : path;
}

int main(void)
{
    static Dl_info info;
    for (Class cls in @[[VNDetectFaceCaptureQualityRequest class], [VNRecognizeTextRequest class],
                        [VNRecognizedText class], [VNDetectFaceLandmarksRequest class]]) {
        const char *image = "(no dladdr)";
        if (dladdr((__bridge const void *)cls, &info) && info.dli_fname) image = leaf(info.dli_fname);
        printf("%-46s %-22s conforms:", class_getName(cls), image);
        for (Protocol *p in @[@protocol(VNFaceObservationAccepting), @protocol(VNRequestProgressProviding),
                               @protocol(VNRequestRevisionProviding), @protocol(NSSecureCoding), @protocol(NSCopying)]) {
            if ([cls conformsToProtocol:p]) printf("  %s", protocol_getName(p));
        }
        printf("\n");
    }
    Class ghost = NSClassFromString(@"VNNoClassOfThisName");
    printf("%-46s %-22s conforms to nothing: %s\n", "VNNoClassOfThisName (the control)", ghost ? "found" : "nil class",
           [ghost conformsToProtocol:@protocol(VNRequestProgressProviding)] ? "YES" : "no");

    VNRecognizeTextRequest *text = [[VNRecognizeTextRequest alloc] init];
    printf("\nVNRecognizeTextRequest progressHandler responds: %s, indeterminate = %s, usesLanguageCorrection = %s\n",
           [text respondsToSelector:@selector(progressHandler)] ? "responds" : "no selector",
           text.indeterminate ? "YES" : "NO", text.usesLanguageCorrection ? "YES" : "NO");
    VNRecognizedText *word = [[VNRecognizedText alloc] init];
    printf("VNRecognizedText supportsSecureCoding = %s, string = %s, confidence = %f, requestRevision = %lu\n",
           [VNRecognizedText supportsSecureCoding] ? "YES" : "NO",
           word.string ? "set" : "nil", (double)word.confidence, (unsigned long)word.requestRevision);
    printf("VNDetectHumanRectanglesRequest upperBodyOnly = %s\n",
           [[[VNDetectHumanRectanglesRequest alloc] init] upperBodyOnly] ? "YES" : "NO");
    printf("VNGenerateImageFeaturePrintRequest imageCropAndScaleOption = %lu (ScaleFill is 2, CenterCrop is 0)\n",
           (unsigned long)[[[VNGenerateImageFeaturePrintRequest alloc] init] imageCropAndScaleOption]);
    return 0;
}
