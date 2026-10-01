// The 13.0 API this slice carries, measured against the system's own Vision: which image each
// answer comes from, the truth table of +revision:supportsConstellation:, what VNElementTypeSize
// answers for every argument, the two animal identifiers' values, whether the progress protocol is
// reachable by name, and each request's own revision table. A name this Vision does not carry is the
// control: a reader that cannot find one cannot read a zero.
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include <string.h>

static const char *image_of(const void *symbol)
{
    static Dl_info info;
    if (symbol && dladdr(symbol, &info) && info.dli_fname) {
        const char *mark = strrchr(info.dli_fname, '/');
        return mark ? mark + 1 : info.dli_fname;
    }
    return "(no dladdr)";
}

static const char *yesno(BOOL answer) { return answer ? "YES" : "NO"; }

int main(void)
{
    printf("VNElementTypeSize from: %s\n", image_of((const void *)VNElementTypeSize));
    printf("+[VNDetectFaceLandmarksRequest class] from: %s\n",
           image_of((__bridge const void *)[VNDetectFaceLandmarksRequest class]));
    printf("&VNAnimalIdentifierCat from: %s\n", image_of(&VNAnimalIdentifierCat));

    for (NSUInteger revision = 1; revision <= 4; revision++)
        for (NSUInteger constellation = 0; constellation <= 2; constellation++)
            printf("revision %lu supports constellation %lu: %s\n", (unsigned long)revision,
                   (unsigned long)constellation,
                   yesno([VNDetectFaceLandmarksRequest revision:revision
                                    supportsConstellation:(VNRequestFaceLandmarksConstellation)constellation]));

    for (NSUInteger value = 0; value < 5; value++)
        printf("VNElementTypeSize(%lu) = %lu\n", (unsigned long)value,
               (unsigned long)VNElementTypeSize((VNElementType)value));

    printf("VNAnimalIdentifierCat = %s\n", VNAnimalIdentifierCat.UTF8String);
    printf("VNAnimalIdentifierDog = %s\n", VNAnimalIdentifierDog.UTF8String);

    for (NSString *name in @[@"VNRequestProgressProviding", @"VNNoProtocolOfThisName"])
        printf("NSProtocolFromString(%s) = %s\n", name.UTF8String,
               NSProtocolFromString(name) ? "found" : "nil");

    for (NSString *name in @[@"VNClassifyImageRequest", @"VNRecognizeAnimalsRequest", @"VNRecognizeTextRequest",
                             @"VNDetectHumanRectanglesRequest", @"VNRecognizedText", @"VNRecognizedTextObservation",
                             @"VNFeaturePrintObservation", @"VNSaliencyImageObservation",
                             @"VNGenerateAttentionBasedSaliencyImageRequest",
                             @"VNGenerateObjectnessBasedSaliencyImageRequest",
                             @"VNGenerateImageFeaturePrintRequest", @"VNDetectFaceCaptureQualityRequest",
                             @"VNNoClassOfThisName"])
        printf("NSClassFromString(%s) = %s\n", name.UTF8String,
               NSClassFromString(name) ? "found" : "nil");

    VNRecognizeTextRequest *text = [[VNRecognizeTextRequest alloc] init];
    printf("VNRecognizeTextRequest conformsToProtocol(VNRequestProgressProviding) = %s\n",
           yesno([text conformsToProtocol:@protocol(VNRequestProgressProviding)]));
    printf("VNRecognizeTextRequest indeterminate = %s\n", yesno(text.indeterminate));

    for (Class cls in @[[VNRecognizeAnimalsRequest class], [VNClassifyImageRequest class],
                        [VNDetectHumanRectanglesRequest class], [VNDetectFaceCaptureQualityRequest class],
                        [VNGenerateAttentionBasedSaliencyImageRequest class],
                        [VNGenerateObjectnessBasedSaliencyImageRequest class],
                        [VNGenerateImageFeaturePrintRequest class], [VNRecognizeTextRequest class],
                        [VNDetectFaceLandmarksRequest class], [VNDetectRectanglesRequest class]]) {
        id request = [[cls alloc] init];
        printf("%-46s supportedRevisions = %-8s currentRevision = %lu revisionProviding = %s\n", class_getName(cls),
               [cls supportedRevisions].description.UTF8String, (unsigned long)[cls currentRevision],
               yesno([request conformsToProtocol:@protocol(VNRequestRevisionProviding)]));
    }
    return 0;
}
