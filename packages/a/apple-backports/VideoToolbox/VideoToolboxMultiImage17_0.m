#import "CharonVideoToolbox.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VTDecompressionSession.h>
#include <VideoToolbox/VTCompressionSession.h>
#include <VideoToolbox/VTErrors.h>

// The four decode and encode variants of SDK 17.0, and what each one can honestly do on a release that
// exports none of them.
//
// The measurement that decides all four (tools/corpus/dump-cache.lua over
// $HOME/.charon/dyld/4.3/dyld_shared_cache_armv7, and v-audio's 6.1.3 armv7 dump, 2026-10-03):
//
//   _VTDecompressionSessionDecodeFrameWithMultiImageCapableOutputHandler   4.3=0  6.1.3=0
//   _VTDecompressionSessionSetMultiImageCallback                           4.3=0  6.1.3=0
//   _VTCompressionSessionEncodeMultiImageFrame                             4.3=0  6.1.3=0
//   _VTCompressionSessionEncodeMultiImageFrameWithOutputHandler            4.3=0  6.1.3=0
//   _VTDecompressionSessionDecodeFrame                                      4.3=1  6.1.3=1
//   _VTCompressionSessionEncodeFrame                                        4.3=1  6.1.3=1
//
// So the single-frame entry points ARE the release's and the four variants are the port's. What decides each
// one is not the missing symbol but WHAT THE CALLER'S ARGUMENT IS:
//
//   - the two decode variants take a CMTaggedBufferGroup through their callback - a group of several images
//     for one frame, which arrived with iOS 14 - and the release's own decode callback has no parameter to
//     receive one: the 16.4 SDK's VTDecompressionOutputCallback ends at CVImageBuffer imageBuffer. A
//     callback the release cannot call is a block the port would have to call itself, and a port that called
//     it would be inventing the multi-image decode it has no decoder for. So both refuse with the release's
//     own decoder code and do no work;
//   - the two encode variants take a CMTaggedBufferGroupRef as their SOURCE, and there is no release
//     function that reads one: the release's encode entry point takes a CVImageBuffer. Same answer, with
//     the encoder's own code.
//
// kVTVideoDecoderNotAvailableNowErr and kVTVideoEncoderNotAvailableNowErr are the release's own constants
// (VTErrors.h:42 and :45) and they are what the same argument earned for the 9.0 output-handler pair, which
// this branch already refuses in VTSessionOutputHandler9_0.m. A variant that accepted its argument and did
// nothing with it would be the silent fake the brief forbids; a variant that refuses says so in the status,
// before any work, and the caller sees it.

// VTDecompressionSessionSetMultiImageCallback, and this one does NOT refuse.
//
// The first version of this function answered kVTVideoDecoderNotAvailableNowErr (-12913) on the reasoning
// that the release's decode callback ends at CVImageBuffer and so could never call the callback it is given.
// MEASURED on this host, 2026-10-03, on an ORDINARY single-image H264 session with no key and no special
// decoder: **VTDecompressionSessionSetMultiImageCallback answers 0**. The host installs the callback and
// reports success, so a caller that has done nothing unusual is told it worked. A port that answered -12913
// here would refuse a call the release accepts, which is worse than the reverse: the caller is told no where
// the real thing says yes.
//
// So this stores what it was given and answers noErr, and the honest part is the storing. The callback and
// its reference value go into a table this file owns, keyed by the session's address as a VALUE rather than
// by sending it a message: a VTDecompressionSessionRef is an opaque CF type with no toll-free ObjC class on
// this side, so -hash and -isEqual: cannot be sent to it, and NSValue is what carries the pointer instead.
// What the table is FOR is stated here rather than left to be found: a session this port creates is the
// RELEASE's session, and the release's decode has no multi-image output at all, so nothing in this port calls
// what is stored - on this band or on any band the port builds. It is stored because the function's contract
// is "install this callback", and a version that accepted the argument and discarded it would be claiming an
// installation that never happened.
static NSMutableDictionary *charon_multi_image_callbacks(void)
{
    static NSMutableDictionary *table = nil;
    if (!table)
        table = [[NSMutableDictionary alloc] init];
    return table;
}

// The callback and its reference value together, because one without the other is not the callback.
@interface CharonVTMultiImageCallback : NSObject {
@public
    VTDecompressionOutputMultiImageCallback _callback;
    void *_refcon;
}
@end

@implementation CharonVTMultiImageCallback
- (void)dealloc
{
    _callback = NULL;
    _refcon = NULL;
}
@end

OSStatus VTDecompressionSessionSetMultiImageCallback(
    VTDecompressionSessionRef CM_NONNULL decompressionSession,
    VTDecompressionOutputMultiImageCallback CM_NONNULL outputMultiImageCallback,
    void * CM_NULLABLE outputMultiImageRefcon)
{
    if (!decompressionSession || !outputMultiImageCallback)
        return kVTParameterErr;
    CharonVTMultiImageCallback *stored = [[CharonVTMultiImageCallback alloc] init];
    stored->_callback = outputMultiImageCallback;
    stored->_refcon = outputMultiImageRefcon;
    charon_multi_image_callbacks()[[NSValue valueWithPointer:decompressionSession]] = stored;
    return noErr;
}

// VTDecompressionSessionDecodeFrameWithMultiImageCapableOutputHandler. The header is explicit that the block
// "will not be called" if this returns an error, so refusing is the documented shape of the answer and not
// a way of hiding one: the caller is told, and the block it passed is not retained.
OSStatus VTDecompressionSessionDecodeFrameWithMultiImageCapableOutputHandler(
    VTDecompressionSessionRef CM_NONNULL session,
    CMSampleBufferRef CM_NONNULL sampleBuffer,
    VTDecodeFrameFlags decodeFlags,
    VTDecodeInfoFlags * CM_NULLABLE infoFlagsOut,
    VTDecompressionMultiImageCapableOutputHandler CM_NONNULL multiImageCapableOutputHandler)
{
    (void)session;
    (void)sampleBuffer;
    (void)decodeFlags;
    // Nothing has been decoded, so there is no flag to report. Saying so beats writing a value nothing
    // measured: the two flags the header names are set by the decoder, and this call did not reach one.
    if (infoFlagsOut)
        *infoFlagsOut = 0;
    (void)multiImageCapableOutputHandler;
    return kVTVideoDecoderNotAvailableNowErr;
}

// VTCompressionSessionEncodeMultiImageFrame: the multi-image ENCODE, whose source is the group itself.
OSStatus VTCompressionSessionEncodeMultiImageFrame(
    VTCompressionSessionRef CM_NONNULL session,
    CMTaggedBufferGroupRef CM_NONNULL taggedBufferGroup,
    CMTime presentationTimeStamp,
    CMTime duration,
    CFDictionaryRef CM_NULLABLE frameProperties,
    void * CM_NULLABLE sourceFrameRefcon,
    VTEncodeInfoFlags * CM_NULLABLE infoFlagsOut)
{
    (void)session;
    (void)taggedBufferGroup;
    (void)presentationTimeStamp;
    (void)duration;
    (void)frameProperties;
    (void)sourceFrameRefcon;
    if (infoFlagsOut)
        *infoFlagsOut = 0;
    return kVTVideoEncoderNotAvailableNowErr;
}

// VTCompressionSessionEncodeMultiImageFrameWithOutputHandler: the same source, delivered by a block. Its
// header says the block "may be called asynchronously, on a different thread from the one that calls" it,
// which is another promise this port cannot keep: there is no encode to run the block after.
OSStatus VTCompressionSessionEncodeMultiImageFrameWithOutputHandler(
    VTCompressionSessionRef CM_NONNULL session,
    CMTaggedBufferGroupRef CM_NONNULL taggedBufferGroup,
    CMTime presentationTimeStamp,
    CMTime duration,
    CFDictionaryRef CM_NULLABLE frameProperties,
    VTEncodeInfoFlags * CM_NULLABLE infoFlagsOut,
    VTCompressionOutputHandler CM_NONNULL outputHandler)
{
    (void)session;
    (void)taggedBufferGroup;
    (void)presentationTimeStamp;
    (void)duration;
    (void)frameProperties;
    if (infoFlagsOut)
        *infoFlagsOut = 0;
    (void)outputHandler;
    return kVTVideoEncoderNotAvailableNowErr;
}