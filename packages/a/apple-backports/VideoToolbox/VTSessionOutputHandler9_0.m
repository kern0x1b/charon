#import "CharonVideoToolbox.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VTCompressionSession.h>
#include <VideoToolbox/VTDecompressionSession.h>
#include <VideoToolbox/VTErrors.h>

OSStatus VTCompressionSessionEncodeFrameWithOutputHandler(
    VTCompressionSessionRef session, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp,
    CMTime duration, CFDictionaryRef CM_NULLABLE frameProperties,
    VTEncodeInfoFlags * CM_NULLABLE infoFlagsOut, VTCompressionOutputHandler outputHandler)
{
    // The encode itself is the release's own, and its status is passed back untouched: the frame really
    // is compressed. What cannot be done is delivering the result to outputHandler, because no API on
    // this release installs a per-call callback - see the comment at the head of this file. The frame the
    // encoder emits goes where the release sends output for a session created with a NULL callback,
    // which is nowhere.
    return VTCompressionSessionEncodeFrame(session, imageBuffer, presentationTimeStamp, duration,
                                           frameProperties, NULL, infoFlagsOut);
}

OSStatus VTDecompressionSessionDecodeFrameWithOutputHandler(
    VTDecompressionSessionRef session, CMSampleBufferRef sampleBuffer, VTDecodeFrameFlags decodeFlags,
    VTDecodeInfoFlags * CM_NULLABLE infoFlagsOut, VTDecompressionOutputHandler outputHandler)
{
    // The same shape as the compression side and the same cause: VTDecompressionSessionCreate fixes the
    // callback and no VTDecompressionSessionSetOutputCallback exists to change it, so the decoded frame
    // cannot be routed to the block. The decode is the release's own and its status is passed back.
    return VTDecompressionSessionDecodeFrame(session, sampleBuffer, decodeFlags, NULL, infoFlagsOut);
}