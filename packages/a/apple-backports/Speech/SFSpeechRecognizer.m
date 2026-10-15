#import <Speech/Speech.h>

// The recognizer of iOS 10. No recognizer runs on this device, so no locale is one it can recognize: supportedLocales is
// empty, and a recognizer for any locale is not made, which is the answer the host gives for a locale it does not support
// (tests/backports/host/speech-data, case 10). Nothing here opens the microphone or sends audio anywhere.
//
// The host answers an authorization status of NotDetermined for an application with no usage description, and it ends
// the process when that application asks for authorization, before the handler runs (case 12). The port keeps the status and
// never calls the handler, so the request is answered by nothing: the coordinator decides whether a Restricted answer is
// better (facts/Speech/recognizer.md).
@implementation SFSpeechRecognizer

// The instance properties are declared in the header but not carried: no recognizer instance exists on this device, so
// nothing answers them. @dynamic stops the compiler from synthesizing accessors, which would answer the zeros of ivars the
// host never shows; a caller that asks reaches an unrecognized selector (facts/Speech/recognizer.md).
@dynamic available, locale, supportsOnDeviceRecognition, delegate, defaultTaskHint, queue;

+ (NSSet<NSLocale *> *)supportedLocales
{
    return [NSSet set];
}

+ (SFSpeechRecognizerAuthorizationStatus)authorizationStatus
{
    return SFSpeechRecognizerAuthorizationStatusNotDetermined;
}

+ (void)requestAuthorization:(void (^)(SFSpeechRecognizerAuthorizationStatus status))handler
{
}

- (nullable instancetype)init
{
    return [self initWithLocale:[NSLocale currentLocale]];
}

- (nullable instancetype)initWithLocale:(NSLocale *)locale
{
    // The locale is not one of supportedLocales, which is empty here, so no recognizer is made for it.
    return nil;
}

@end
