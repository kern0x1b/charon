#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wunguarded-availability"
// A category implementing 10.0's designated initializer of a class the release defines is told three
// times over that only a primary class may do it, and once that the primary class also implements it.
// Both are true and neither is a defect here: the release has no -initWithOutputSettings: to inherit,
// and the method is the one that has to exist for a caller. The same pair of warnings is silenced in
// Foundation/NSBundle+ReceiptURL.m's neighbourhood, and this file is otherwise warning-clean.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// The iOS 10 API of the release-10 absent rows, and nothing else: the three members a release at this
// port's floor (6.0) can answer. Every other row of that release stays absent, and the measurement that
// closes it is in facts/AVFoundation/AVFoundation10.md, which names the commands and their output.
//
// All three are CATEGORY methods, so nm -gU over this object defines no API symbol at all and
// tools/release-split.lua checks ZERO symbols here and reports the file clean vacuously - the blind spot
// its own header documents. The class-scoped check for a category is a selector-string walk of the cache
// ladder, which is what first-rung.py answers, and the three selectors are 10.0.1 there while the classes
// that own them carry neither at 6.1.3 (4.3 does not carry AVPlayerItemVideoOutput at all, which is why
// this object's minimum is 6.0 and not 4.3).

@implementation AVPlayer (CharonAVFoundation10)

// 10.0: "causes the value of rate to change to the specified rate ... and the receiver to play the
// available media immediately, whether or not prior buffering of media data is sufficient to ensure
// smooth playback" (AVPlayer.h, -playImmediatelyAtRate:).
//
// A release at this floor has no stalling gate to bypass: 6.1.3's AVPlayer carries no
// automaticallyWaitsToMinimizeStalling, no timeControlStatus and no reasonForWaitingToPlay, and its rate
// is -setRate: (measured on the armv7 cache, the only rate setter on the class). A non-zero rate there
// already starts the available media as soon as there is any, which is the whole of what this method is
// for, and a rate of 0 pauses, which is what the header documents -setRate: with 0.0 to do.
- (void)playImmediatelyAtRate:(float)rate
{
    [self setRate:rate];
}

// 10.0: the header's own three conditions, read against members the release carries.
//
//   - WaitingToPlayAtSpecifiedRate holds "when the player has no item to play, i.e. when the receiver's
//     currentItem is nil" - asked first, because the header names it unconditionally.
//   - Paused is entered "upon receipt of a -pause message, an invocation of -setRate: with a value of
//     0.0", so a zero rate with an item to play is Paused.
//   - Playing against WaitingToPlayAtSpecifiedRate turns on "whether sufficient media data is available
//     to continue playback", which is what -[AVPlayerItem isPlaybackLikelyToKeepUp] answers ("sufficient
//     media data ... to continue playback", AVPlayerItem.h) - the property is a
//     `(readonly, getter=isPlaybackLikelyToKeepUp)` and the release carries that getter.
//
// The value is right on every read. No KVO notification is sent for it, because there is no state here
// to announce - the release's own -rate, -currentItem and -isPlaybackLikelyToKeepUp carry the changes, and
// a caller that observes this property observes those three instead. That limit is stated in the row's
// effect rather than papered over.
- (AVPlayerTimeControlStatus)timeControlStatus
{
    AVPlayerItem *item = self.currentItem;
    if (item == nil)
        return AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
    if (self.rate == 0.0f)
        return AVPlayerTimeControlStatusPaused;
    return item.isPlaybackLikelyToKeepUp ? AVPlayerTimeControlStatusPlaying
                                         : AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
}

@end

@implementation AVPlayerItemVideoOutput (CharonAVFoundation10)

// 10.0's designated initializer. Its parameter is documented in this tree's own SDK header
// (iPhoneOS16.4.sdk, AVPlayerItemOutput.h) as "The client requirements for output CVPixelBuffers,
// expressed using the constants in <AVFoundation/AVVideoSettings.h>", against
// -initWithPixelBufferAttributes:'s "expressed using the constants in <CoreVideo/CVPixelBuffer.h>": the
// same requirements in two vocabularies, and the release carries only the second, so the translation is
// the implementation.
//
// The header's own throws are reproduced rather than smoothed over: it throws for an empty dictionary,
// for settings "that will yield compressed output", and for settings that "do not honor the requirements
// listed above" - so AVVideoCodecKey raises here, and any key outside the two dimensions raises instead
// of being dropped, which is what the release's own -initWithPixelBufferAttributes: does with a key that
// is not a pixel buffer attribute key.
- (instancetype)initWithOutputSettings:(NSDictionary<NSString *, id> *)outputSettings
{
    if (outputSettings == nil)
        return [self initWithPixelBufferAttributes:nil];

    if (outputSettings.count == 0)
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"AVPlayerItemVideoOutput: the output settings dictionary is empty"
                                     userInfo:nil];

    if (outputSettings[AVVideoCodecKey] != nil)
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"AVPlayerItemVideoOutput: the output settings name a codec, so they would yield compressed output, and this output produces CVPixelBuffers"
                                     userInfo:nil];

    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:2];
    for (NSString *key in outputSettings) {
        if ([key isEqualToString:AVVideoWidthKey])
            attributes[(__bridge NSString *)kCVPixelBufferWidthKey] = outputSettings[key];
        else if ([key isEqualToString:AVVideoHeightKey])
            attributes[(__bridge NSString *)kCVPixelBufferHeightKey] = outputSettings[key];
        else
            @throw [NSException
                exceptionWithName:NSInvalidArgumentException
                           reason:[NSString stringWithFormat:@"AVPlayerItemVideoOutput: the output settings carry %@, which names no requirement the CVPixelBuffers of this output can be given", key]
                         userInfo:nil];
    }
    return [self initWithPixelBufferAttributes:attributes];
}

@end
