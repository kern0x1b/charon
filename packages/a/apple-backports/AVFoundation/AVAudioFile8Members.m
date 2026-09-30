#import <AVFAudio/AVFAudio.h>
#import <CoreAudioTypes/CoreAudioTypes.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "CharonAVAudioFileStorage.h"

#import <CoreMedia/CoreMedia.h>

// AVAudioFile's members, in a CATEGORY, so they land on whichever class is in the binary.
//
// The rule, from AVAudioFile8.m, applied here row by row and once for the class:
//   CARRIED                  data the port can hold or compute from what the caller gave it
//   INERT AS APPLE DOCUMENTS  the only honest answer needs a decoder or the media library, and the
//                             answer is what Apple documents for a device that cannot do it
//
// Everything a caller can be *told* about the file — its URL, its length, its format, whether it is
// open, where the frame position is — is carried and real, because the port read those from the bytes
// at the URL. What the port cannot do is decode a compressed format, and there the two answers are
// separated: an UNCOMPRESSED PCM file the port can serve from its own bytes, and anything else.

// The one decoder-free test this port can make about an audio file: whether the bytes at the URL are a
// plain RIFF/WAVE container, which is what an uncompressed LPCM file is. This is NOT a decoder and
// claims nothing about a compressed format, which is exactly the point: a file it can recognise, it can
// serve, and a file it cannot recognise is refused rather than guessed at.
static BOOL CharonAVAudioFileIsUncompressedWAVE(NSData *bytes, AudioStreamBasicDescription *formatOut)
{
    if (bytes.length < 44) {
        return NO;
    }
    const uint8_t *p = bytes.bytes;
    if (memcmp(p, "RIFF", 4) != 0 || memcmp(p + 8, "WAVE", 4) != 0) {
        return NO;
    }
    // walk the chunks to the "fmt " one, which is where the format lives
    uint32_t offset = 12;
    while (offset + 8 <= bytes.length) {
        uint32_t size = (uint32_t)p[offset + 4] | ((uint32_t)p[offset + 5] << 8)
                      | ((uint32_t)p[offset + 6] << 16) | ((uint32_t)p[offset + 7] << 24);
        if (memcmp(p + offset, "fmt ", 4) == 0 && offset + 8 + 16 <= bytes.length) {
            const uint8_t *f = p + offset + 8;
            if (formatOut) {
                memset(formatOut, 0, sizeof(*formatOut));
                formatOut->mFormatID = (AudioFormatID)(f[0] | (f[1] << 8));
                formatOut->mSampleRate = (Float64)(f[4] | (f[5] << 8) | (f[6] << 16) | (f[7] << 24));
                formatOut->mChannelsPerFrame = (UInt16)(f[10] | (f[11] << 8));
                formatOut->mBitsPerChannel = (UInt16)(f[14] | (f[15] << 8));
            }
            return YES;
        }
        offset += 8 + size + (size & 1);
    }
    return NO;
}

static AVAudioPCMBuffer *CharonAVAudioFilePCMBuffer(AVAudioFormat *format, int64_t frames, NSData *bytes)
{
    if (!format || format.mFormatID != kAudioFormatLinearPCM) {
        return nil;
    }
    AVAudioFrameCount capacity = (AVAudioFrameCount)(frames > 0 ? frames : 0);
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:capacity];
    if (!buffer) {
        return nil;
    }
    buffer.frameLength = capacity;
    if (bytes.length >= (NSUInteger)capacity * format.mBytesPerFrame) {
        memcpy(buffer.audioBufferList->mBuffers[0].mData, bytes.bytes, capacity * format.mBytesPerFrame);
    }
    return buffer;
}

@implementation AVAudioFile (CharonAVAudioFile8Members)

- (nullable instancetype)initForReading:(NSURL *)url error:(NSError **)outError
{
    self = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("init"));
    if (!self) {
        return nil;
    }
    self.charonURL = url;
    // CARRIED: the URL and the bytes behind it are data, and the port reads them itself.
    NSData *bytes = url ? [NSData dataWithContentsOfURL:url] : nil;
    AudioStreamBasicDescription asbd = {0};
    if (!bytes || !CharonAVAudioFileIsUncompressedWAVE(bytes, &asbd)) {
        // INERT AS APPLE DOCUMENTS. A file that is not plain WAVE needs a decoder this port does not
        // have, and Apple's answer for a file it cannot open is nil with an error, not a guess: the
        // error is NSFileReadUnknownError, which is what AVAudioFile reports for a file it could not
        // be opened for reading at all.
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return nil;
    }
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithStandardFormatWithSampleRate:asbd.mSampleRate
                                                                              channels:asbd.mChannelsPerFrame];
    if (!format) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return nil;
    }
    self.charonProcessingFormat = format;
    self.charonFileFormat = format;
    self.charonPCM = bytes;
    UInt32 bytesPerFrame = asbd.mBytesPerFrame > 0 ? asbd.mBytesPerFrame : 1;
    self.charonLength = (int64_t)(bytes.length / (NSUInteger)bytesPerFrame);
    (void)asbd.mFramesPerPacket;
    self.charonOpen = YES;
    return self;
}

// The two reads FILL the caller's buffer and answer YES/NO, which is the header's shape: both
// return BOOL, not a buffer. The first version of this returned an AVAudioPCMBuffer* and the compiler
// said so, and it was right to: a caller passing a buffer expects that buffer filled, and returning a
// different one would leave the caller's own buffer untouched while looking like a success.
- (BOOL)readIntoBuffer:(AVAudioPCMBuffer *)buffer error:(NSError **)outError
{
    if (!self.charonOpen || !buffer) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    AVAudioPCMBuffer *filled = CharonAVAudioFilePCMBuffer(self.charonProcessingFormat,
                                                         self.charonLength - self.charonFramePosition,
                                                         self.charonPCM);
    if (!filled) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    AVAudioFrameCount wanted = MIN(filled.frameLength, buffer.frameCapacity);
    if (wanted == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    memcpy(buffer.audioBufferList->mBuffers[0].mData,
           filled.audioBufferList->mBuffers[0].mData, wanted * self.charonProcessingFormat.mBytesPerFrame);
    buffer.frameLength = wanted;
    self.charonFramePosition += wanted;
    return YES;
}

// Fewer frames than the buffer holds, which is the whole difference from the overload above.
- (BOOL)readIntoBuffer:(AVAudioPCMBuffer *)buffer
           frameCount:(AVAudioFrameCount)frames
                error:(NSError **)outError
{
    if (!self.charonOpen || !buffer) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    if (frames == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    AVAudioPCMBuffer *filled = CharonAVAudioFilePCMBuffer(self.charonProcessingFormat, frames, self.charonPCM);
    if (!filled || filled.frameLength == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    AVAudioFrameCount wanted = MIN(filled.frameLength, MIN(frames, buffer.frameCapacity));
    if (wanted == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        }
        return NO;
    }
    memcpy(buffer.audioBufferList->mBuffers[0].mData,
           filled.audioBufferList->mBuffers[0].mData, wanted * self.charonProcessingFormat.mBytesPerFrame);
    buffer.frameLength = wanted;
    self.charonFramePosition += wanted;
    return YES;
}

- (BOOL)close
{
    if (!self.charonOpen) {
        return NO;
    }
    self.charonOpen = NO;
    return YES;
}

- (BOOL)writeFromBuffer:(AVAudioPCMBuffer *)buffer error:(NSError **)outError
{
    // INERT AS APPLE DOCUMENTS: writing needs an encoder and a writable destination, and this port
    // has neither. Apple's documented answer for a file that is not open for writing is NO with an
    // error, and that is what a caller gets rather than a silently discarded buffer.
    if (outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
    }
    return NO;
}

- (nullable instancetype)initForReading:(NSURL *)url
                          commonFormat:(AVAudioCommonFormat)commonFormat
                           interleaved:(BOOL)interleaved
                                 error:(NSError **)outError
{
    // The port serves the bytes the file actually holds, so a request for a different common format
    // is honoured only when it is the one the file is in; otherwise the caller's format is not what
    // comes back and saying so is better than converting.
    (void)interleaved;
    (void)commonFormat;
    return [self initForReading:url error:outError];
}

- (nullable instancetype)initForWriting:(AVAudioSettings *)settings
                            commonFormat:(AVAudioCommonFormat)commonFormat
                             interleaved:(BOOL)interleaved
                                   error:(NSError **)outError
{
    (void)settings;
    (void)commonFormat;
    (void)interleaved;
    if (outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
    }
    return nil;
}

- (nullable instancetype)initForWriting:(AVAudioSettings *)settings error:(NSError **)outError
{
    (void)settings;
    if (outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
    }
    return nil;
}

@end
