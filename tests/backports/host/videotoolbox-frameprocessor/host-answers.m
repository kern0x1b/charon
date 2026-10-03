// host-answers.m - what the HOST's own VideoToolbox answers for the seventeen frame-processor classes
// and for the error domain, asked through the runtime so that a class the host marks NS_UNAVAILABLE
// can be asked anyway.
//
// WHY objc_msgSend AND NOT BRACKETED CALLS: SDK 26.2 declares `- (instancetype) init NS_UNAVAILABLE;`
// on sixteen of the seventeen classes, so `[[VTFrameProcessorFrame alloc] init]` does not compile
// against the host's own header either. A bracketed call cannot even be written, let alone used as an
// oracle, so this file sends the selectors by name - which is exactly the case the annotation exists to
// warn about, and the case the port's `absent` rows describe.
//
// WHAT IT PRINTS, one TSV line per row:
//   DOMAIN   <the NSString VTFrameProcessorErrorDomain holds>
//   UNKNOWN  <the codes VTFrameProcessorError enumerates, in the header's own order>
//   UNAVAILABLE <class> <+new answers 0|1> <-init answers 0|1> <frameWidth, or NA>
//   SUPPORTED <class> <+isSupported, or NA where the class declares no such property>
//   ERRORCODE <name> <the value>
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <VideoToolbox/VideoToolbox.h>

extern NSErrorDomain const VTFrameProcessorErrorDomain;

static id send_id(id target, SEL selector)
{
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL send_bool(id target, SEL selector)
{
    return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
}

static const char *const CLASSES[] = {
    "VTFrameProcessor", "VTFrameProcessorFrame", "VTFrameProcessorOpticalFlow",
    "VTFrameRateConversionConfiguration", "VTFrameRateConversionParameters",
    "VTLowLatencyFrameInterpolationConfiguration", "VTLowLatencyFrameInterpolationParameters",
    "VTLowLatencySuperResolutionScalerConfiguration", "VTLowLatencySuperResolutionScalerParameters",
    "VTMotionBlurConfiguration", "VTMotionBlurParameters",
    "VTOpticalFlowConfiguration", "VTOpticalFlowParameters",
    "VTSuperResolutionScalerConfiguration", "VTSuperResolutionScalerParameters",
    "VTTemporalNoiseFilterConfiguration", "VTTemporalNoiseFilterParameters",
};

// The codes SDK 26.2's VTFrameProcessorErrors.h enumerates, named here because a bracketed comparison
// against the header's own enum is what this file is checking the port's transcription against.
static const struct { const char *name; NSInteger code; } CODES[] = {
    {"VTFrameProcessorUnknownError", -19730}, {"VTFrameProcessorUnsupportedResolution", -19731},
    {"VTFrameProcessorSessionNotStarted", -19732}, {"VTFrameProcessorSessionAlreadyActive", -19733},
    {"VTFrameProcessorFatalError", -19734}, {"VTFrameProcessorSessionLevelError", -19735},
    {"VTFrameProcessorInitializationFailed", -19736}, {"VTFrameProcessorUnsupportedInput", -19737},
    {"VTFrameProcessorMemoryAllocationFailure", -19738}, {"VTFrameProcessorRevisionNotSupported", -19739},
    {"VTFrameProcessorProcessingError", -19740}, {"VTFrameProcessorInvalidParameterError", -19741},
    {"VTFrameProcessorInvalidFrameTiming", -19742}, {"VTFrameProcessorAssetDownloadFailed", -19743},
};

int main(void)
{
    // The control line the reader requires before it believes any of the rest: the framework opened, and
    // the domain symbol is there. Without it a framework that failed to load would read as "no classes",
    // which is the same shape of output a real answer has.
    void *library = dlopen("/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox", RTLD_LAZY);
    printf("CONTROL\tframework=%s\tdomain-symbol=%s\n",
           library ? "opened" : "DID NOT OPEN",
           library && dlsym(library, "VTFrameProcessorErrorDomain") ? "present" : "ABSENT");

    printf("DOMAIN\t%s\t%s\n", [VTFrameProcessorErrorDomain UTF8String],
           class_getName([VTFrameProcessorErrorDomain class]));

    // The host's own NSError built in the host's domain, and its code, which is the port's second error
    // in the same shape: a domain a caller compares and a code a caller compares.
    NSError *built = [NSError errorWithDomain:VTFrameProcessorErrorDomain
                                         code:VTFrameProcessorSessionNotStarted
                                     userInfo:@{NSLocalizedDescriptionKey: @"the host's own"}];
    printf("BUILDERROR\t%s\t%ld\n", [built.domain UTF8String], (long)built.code);

    for (unsigned index = 0; index < sizeof(CODES) / sizeof(CODES[0]); index++)
        printf("ERRORCODE\t%s\t%ld\n", CODES[index].name, (long)CODES[index].code);

    for (unsigned index = 0; index < sizeof(CLASSES) / sizeof(CLASSES[0]); index++) {
        NSString *name = [NSString stringWithUTF8String:CLASSES[index]];
        Class cls = NSClassFromString(name);
        if (!cls) { printf("ABSENT\t%s\n", CLASSES[index]); continue; }
        id made = send_id(cls, @selector(new));
        id again = made ? send_id(made, @selector(init)) : nil;
        // frameWidth is on the configuration and parameters classes and not on the two value holders, so
        // asking it of everything would raise; respondsToSelector decides, and "NA" is a real answer.
        const char *width = "NA";
        if (made && [made respondsToSelector:@selector(frameWidth)])
            width = [[NSString stringWithFormat:@"%lld", (long long)send_id(made, @selector(frameWidth))] UTF8String];
        printf("UNAVAILABLE\t%s\t%d\t%d\t%s\n", CLASSES[index], made != nil, again != nil, width);
        if ([cls respondsToSelector:@selector(isSupported)])
            printf("SUPPORTED\t%s\t%d\n", CLASSES[index], send_bool(cls, @selector(isSupported)));
    }
    return 0;
}