#import <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <AudioToolbox/AudioToolbox.h>
#include <stdlib.h>
#include <string.h>

const CFStringRef kCMSampleBufferAttachmentKey_ForceKeyFrame = CFSTR("ForceKeyFrame");
const CFStringRef kCMSampleBufferNotificationParameter_OSStatus = CFSTR("OSStatus");
const CFStringRef kCMSampleBufferNotification_DataFailed = CFSTR("CMSampleBufferDataFailed");

OSStatus CMSampleBufferCreateReady(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, CMFormatDescriptionRef formatDescription,
                                   CMItemCount numSamples, CMItemCount numSampleTimingEntries, const CMSampleTimingInfo *sampleTimingArray,
                                   CMItemCount numSampleSizeEntries, const size_t *sampleSizeArray, CMSampleBufferRef *sampleBufferOut)
{
    return CMSampleBufferCreate(allocator, dataBuffer, true, NULL, NULL, formatDescription, numSamples, numSampleTimingEntries,
                                sampleTimingArray, numSampleSizeEntries, sampleSizeArray, sampleBufferOut);
}

OSStatus CMSampleBufferCreateReadyWithImageBuffer(CFAllocatorRef allocator, CVImageBufferRef imageBuffer, CMVideoFormatDescriptionRef formatDescription,
                                                  const CMSampleTimingInfo *sampleTiming, CMSampleBufferRef *sampleBufferOut)
{
    return CMSampleBufferCreateForImageBuffer(allocator, imageBuffer, true, NULL, NULL, formatDescription, sampleTiming, sampleBufferOut);
}

OSStatus CMSampleBufferCallBlockForEachSample(CMSampleBufferRef sbuf, OSStatus (^handler)(CMSampleBufferRef sampleBuffer, CMItemCount index))
{
    if (!sbuf || !handler)
        return kCMSampleBufferError_RequiredParameterMissing;
    CMItemCount samples = CMSampleBufferGetNumSamples(sbuf);
    if (!samples)
        return 0;
    size_t *sizes = calloc(samples, sizeof *sizes);
    if (!sizes)
        return kCMSampleBufferError_AllocationFailed;
    CMItemCount got = 0;
    OSStatus status = CMSampleBufferGetSampleSizeArray(sbuf, samples, sizes, &got);
    if (status == kCMSampleBufferError_BufferHasNoSampleSizes || got < samples)
        status = kCMSampleBufferError_CannotSubdivide;
    CMBlockBufferRef data = status ? NULL : CMSampleBufferGetDataBuffer(sbuf);
    size_t offset = 0;
    for (CMItemCount index = 0; status == 0 && index < samples; index++) {
        CMSampleTimingInfo timing;
        status = CMSampleBufferGetSampleTimingInfo(sbuf, index, &timing);
        CMBlockBufferRef piece = NULL;
        CMSampleBufferRef one = NULL;
        if (status == 0)
            status = CMBlockBufferCreateWithBufferReference(kCFAllocatorDefault, data, offset, sizes[index], 0, &piece);
        if (status == 0)
            status = CMSampleBufferCreate(kCFAllocatorDefault, piece, true, NULL, NULL, CMSampleBufferGetFormatDescription(sbuf), 1, 1, &timing, 1, &sizes[index], &one);
        if (status == 0) {
            status = handler(one, index);
            CFRelease(one);
        }
        if (piece)
            CFRelease(piece);
        offset += sizes[index];
    }
    free(sizes);
    return status;
}
