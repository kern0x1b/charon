#import <AVFAudio/AVFAudio.h>
#import <CoreAudioTypes/CoreAudioTypes.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "CharonAVAudioFileStorage.h"

// AVAudioFile, iOS 8 — the CLASS, in an object of its own, under Apple's own name.
//
// The first HELD RUNG that exports `_OBJC_CLASS_$_AVAudioFile` and its metaclass is **8.0**, measured
// by tools/corpus/generate-ledger-objects.py over every held cache, with `_NSFileSize` planted as a
// control and a nonsense symbol in none of the fifteen. 4.3 and 6.1.3 do not export it, so on the
// bands the port's floor spans there is no such class and nothing of that name is built; the members
// alone, in a category, would leave `check_registry` counting the row unbuilt and stopping the band
// build — the failure AVMetadataItemFilter had as a bare category.
//
// The members are in AVAudioFile8Members.m, a category. A class symbol is dropped from 8.0 up, where
// the release's own class answers, and a category defines no symbol and is never dropped — so the
// members land on whichever class is in the binary: the port's below 8.0, the release's from 8.0 up.
//
// **The owner's rule for this class, written once and applied to every row below.**
// A row is CARRIED when it is data the port can hold or compute from what the caller gave it — a URL,
// a format, a length, a frame position, a buffer it was handed — and INERT AS APPLE DOCUMENTS when the
// only honest answer comes from something this device lacks: a real decoder or encoder for a
// compressed format, or the media-library service behind one. Nothing here reaches a capture device, a
// route or a key server; the two that cannot be answered without a decoder are `-readIntoBuffer:error:`
// and the `initForReading:` that has to know whether the file's format can be decoded at all.

// The members of this class live in AVAudioFile8Members.m, a category, because a class symbol is
// dropped from 8.0 up and a category's is not a symbol and is never dropped. The warning this class
// raises for the members it declares and does not define is the build stating that split, and it is
// contained here with that reason rather than silenced with -Wno-incomplete-implementation, which
// would also hide a member that is genuinely missing.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation AVAudioFile

// The port's own flag set makes an unsynthesized property an error, so the five storages are
// synthesized explicitly rather than left to default synthesis.
@synthesize charonURL = _charonURL;
@synthesize charonProcessingFormat = _charonProcessingFormat;
@synthesize charonFileFormat = _charonFileFormat;
@synthesize charonPCM = _charonPCM;
@synthesize charonOpen = _charonOpen;
@synthesize charonLength = _charonLength;
@synthesize charonFramePosition = _charonFramePosition;

- (NSURL *)url
{
    return _charonURL;
}

- (AVAudioFormat *)processingFormat
{
    return _charonProcessingFormat;
}

- (AVAudioFormat *)fileFormat
{
    return _charonFileFormat;
}

- (int64_t)length
{
    return _charonLength;
}

- (int64_t)framePosition
{
    return _charonFramePosition;
}

- (BOOL)isOpen
{
    return _charonOpen;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AVAudioFile %p url=%@ length=%lld open=%@>", self,
            [self.charonURL path] ?: @"(none)", (long long)self.charonLength,
            self.charonOpen ? @"YES" : @"no"];
}

@end

#pragma clang diagnostic pop
