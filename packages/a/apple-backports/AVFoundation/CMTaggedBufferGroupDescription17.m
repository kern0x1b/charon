#import <CoreMedia/CoreMedia.h>
#import <CoreFoundation/CoreFoundation.h>
#import "CharonCMTag26.h"
#import "CharonCMTagSupport.h"
#import "CharonCMTaggedBufferGroup26.h"
#import <Foundation/Foundation.h>

// The five CMTaggedBufferGroup format-description and sample-buffer functions, measured against the host
// in facts/CoreMedia/cmtag-fixtures/taggedgroup-measure.m and its answers beside it; the answers are what
// the differential holds this to, and commit 2fbdb758c is where they were taken.
//
// What a format description IS, here, is the platform's own CMFormatDescription: created with
// CMFormatDescriptionCreate, media subtype 'tbgr', with the group's per-entry tag collections in its
// extensions dictionary under CharonEntriesKey. That is not a wrapper and not a new opaque object - the
// host's own answer has CFTypeID CMFormatDescriptionGetTypeID()'s, measured, and a caller who hands this
// to CMSampleBufferGetFormatDescription gets something the platform understands.
//
// What Matches compares is the per-entry collections, in order and by content, and nothing else. The
// host's answer settles what that excludes: a group of the same tags over different buffers matches, so
// buffers are not part of it, and a group of the same entry SIZES over different tags does not match, so
// it is not a count. Both are in the differential as their own cases.
//
// Two things about ownership, because both are CF's and neither is a choice made here: the extensions
// dictionary holds the array and the array holds the collections, so a description keeps its group's
// collections alive, and the sample buffer's attachment holds the group, so the buffer keeps the group
// alive. Both are released with what holds them, and the differential runs under AddressSanitizer so a
// missing retain or an over-release is a report rather than a crash later.

// The key the per-entry collections travel under, inside the description's extensions dictionary. It is
// the port's own: 26.2 gives no key for it, and the dictionary is ours to write into.
static NSString *const CharonEntriesKeyName = @"charon.taggedbuffergroup.entries";
// The attachment key the group travels under on the sample buffer.
static NSString *const CharonGroupKeyName = @"charon.taggedbuffergroup.group";

#define CharonEntriesKey ((__bridge CFStringRef)CharonEntriesKeyName)
#define CharonGroupKey ((__bridge CFStringRef)CharonGroupKeyName)

// 16.4's media type for a video format description, and the subtype the host's answers carry, measured as
// 1952606066 - 'tbgr', TaggedBufferGroup.
static const FourCharCode CharonTaggedBufferGroupSubtype = 'tbgr';

// The group's per-entry collections, in order, as the description carries them.
//
// NOT as an array of the collection objects. That was the first shape tried and 16.4 refuses it:
 // CMFormatDescriptionCreate answers kCMFormatDescriptionError_InvalidParameter (-12710) for an
// extensions dictionary holding bridged Objective-C values, while a NULL group - the same call with no
// such value in it - answers 0. The modern framework that took the measurement tolerates them, so the
// difference is the old platform's, and the port is the one that has to live with it.
//
// So the entries travel as CFData, which is what 16.4 will accept: for each collection in order, a
// CMItemCount and then that collection's tags as they sit in memory. A CMTag is three machine words and
// has no lifetime of its own, so copying its bytes is copying the whole of it, and the tags come back
// out of the port's own sorted storage in the same order they went in.
static CFDataRef CharonCopyEntriesData(CMTaggedBufferGroupRef group)
{
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    if (!group)
        return data;
    NSArray *collections = ((__bridge CharonCMTaggedBufferGroup *)group).charon_collections;
    for (id collection in collections) {
        CharonCMTagCollection *one = (CharonCMTagCollection *)collection;
        CMItemCount count = (CMItemCount)one.charon_count;
        CFDataAppendBytes(data, (const UInt8 *)&count, sizeof count);
        if (count)
            CFDataAppendBytes(data, (const UInt8 *)one.charon_tags, count * sizeof(CMTag));
    }
    return data;
}

// The count and tags of entry `index` in a payload built by CharonCopyEntriesData, or NO if the payload
// does not hold that many entries.
static BOOL CharonEntriesDataAtIndex(CFDataRef data, CFIndex index, CMItemCount *countOut, const CMTag **tagsOut)
{
    const UInt8 *bytes = (const UInt8 *)CFDataGetBytePtr(data);
    CFIndex length = (CFIndex)CFDataGetLength(data);
    CFIndex offset = 0;
    for (CFIndex entry = 0; entry <= index; entry++) {
        if (offset + (CFIndex)sizeof(CMItemCount) > length)
            return NO;
        CMItemCount count;
        memcpy(&count, bytes + offset, sizeof count);
        offset += (CFIndex)sizeof(CMItemCount);
        if (offset + (CFIndex)(count * sizeof(CMTag)) > length)
            return NO;
        if (entry == index) {
            *countOut = count;
            *tagsOut = (const CMTag *)(bytes + offset);
            return YES;
        }
        offset += (CFIndex)(count * sizeof(CMTag));
    }
    return NO;
}

// How many entries the payload holds, which is what the count comparison is really about: a group of two
// entries over a description of three has to answer false, and that is decided before any tag is read.
static CFIndex CharonEntriesDataCount(CFDataRef data)
{
    const UInt8 *bytes = (const UInt8 *)CFDataGetBytePtr(data);
    CFIndex length = (CFIndex)CFDataGetLength(data);
    CFIndex offset = 0, entries = 0;
    while (offset + (CFIndex)sizeof(CMItemCount) <= length) {
        CMItemCount count;
        memcpy(&count, bytes + offset, sizeof count);
        offset += (CFIndex)sizeof(CMItemCount) + (CFIndex)(count * sizeof(CMTag));
        if (offset > length)
            break;
        entries++;
    }
    return entries;
}

OSStatus CMTaggedBufferGroupFormatDescriptionCreateForTaggedBufferGroupWithExtensions(
    CFAllocatorRef CM_NULLABLE allocator, CMTaggedBufferGroupRef CM_NONNULL taggedBufferGroup,
    CFDictionaryRef CM_NULLABLE extensions,
    CMTaggedBufferGroupFormatDescriptionRef CM_NULLABLE * CM_NONNULL formatDescriptionOut)
{
    if (!formatDescriptionOut)
        return kCMFormatDescriptionError_InvalidParameter;

    // The caller's extensions keep their own keys, and ours is added alongside them rather than over
    // them, so a caller can read back what it passed. With a NULL dictionary this is just our key.
    CFMutableDictionaryRef payload = NULL;
    if (extensions)
        payload = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, extensions);
    else
        payload = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);

    // A NULL group is not a failure: the host answers 0 and hands back a real description that matches
    // nothing, and the reason is visible here - there are no entries to record. The array is empty, not
    // absent, so the description is a description of nothing rather than of an unknown.
    CFDataRef entries = CharonCopyEntriesData(taggedBufferGroup);
    CFDictionarySetValue(payload, CharonEntriesKey, entries);
    CFRelease(entries);

    CMFormatDescriptionRef description = NULL;
    OSStatus status = CMFormatDescriptionCreate(allocator, kCMMediaType_Video, CharonTaggedBufferGroupSubtype,
                                                payload, &description);
    CFRelease(payload);
    if (status)
        return status;
    *formatDescriptionOut = description;
    return noErr;
}

OSStatus CMTaggedBufferGroupFormatDescriptionCreateForTaggedBufferGroup(
    CFAllocatorRef CM_NULLABLE allocator, CMTaggedBufferGroupRef CM_NONNULL taggedBufferGroup,
    CMTaggedBufferGroupFormatDescriptionRef CM_NULLABLE * CM_NONNULL formatDescriptionOut)
{
    return CMTaggedBufferGroupFormatDescriptionCreateForTaggedBufferGroupWithExtensions(
        allocator, taggedBufferGroup, NULL, formatDescriptionOut);
}

Boolean CMTaggedBufferGroupFormatDescriptionMatchesTaggedBufferGroup(
    CMTaggedBufferGroupFormatDescriptionRef CM_NONNULL desc,
    CMTaggedBufferGroupRef CM_NONNULL taggedBufferGroup)
{
    if (!desc || !taggedBufferGroup)
        return false;

    CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(desc);
    if (!extensions)
        return false;
    CFDataRef recorded = (CFDataRef)CFDictionaryGetValue(extensions, CharonEntriesKey);
    if (!recorded)
        return false;

    // The count is checked first because it is cheap and because it is the first thing that differs: the
    // host answers 0 for a group of two entries over three. What the count does NOT decide on its own is
    // the case of equal sizes over different tags, which the entry-by-entry comparison below catches -
    // which is why both of those are separate cases in the differential rather than one.
    CharonCMTaggedBufferGroup *group = (__bridge CharonCMTaggedBufferGroup *)taggedBufferGroup;
    NSArray *collections = group.charon_collections;
    if ((CFIndex)collections.count != CharonEntriesDataCount(recorded))
        return false;

    for (CFIndex index = 0; index < (CFIndex)collections.count; index++) {
        CMItemCount theirCount = 0;
        const CMTag *theirTags = NULL;
        if (!CharonEntriesDataAtIndex(recorded, index, &theirCount, &theirTags))
            return false;
        CharonCMTagCollection *mine = (CharonCMTagCollection *)collections[index];
        if ((CMItemCount)mine.charon_count != theirCount)
            return false;
        const CMTag *myTags = mine.charon_tags;
        for (NSUInteger tag = 0; tag < mine.charon_count; tag++) {
            if (!charon_tag_equal(myTags[tag], theirTags[tag]))
                return false;
        }
    }
    return true;
}

OSStatus CMSampleBufferCreateForTaggedBufferGroup(
    CFAllocatorRef CM_NULLABLE allocator, CMTaggedBufferGroupRef CM_NONNULL taggedBufferGroup,
    CMTime sbufPTS, CMTime sbufDuration,
    CMTaggedBufferGroupFormatDescriptionRef CM_NONNULL formatDescription,
    CMSampleBufferRef CM_NULLABLE * CM_NONNULL sBufOut)
{
    if (!sBufOut)
        return kCMFormatDescriptionError_InvalidParameter;

    // A real platform sample buffer, one sample, the timing the caller gave - the host answers numSamples
    // 1, data ready, and hands the presentation timestamp and duration back unchanged - and the format
    // description just made. The block buffer is the one iOS 4 has; there is no media in it, and the
    // measured contract says none is expected.
    CMBlockBufferRef backing = NULL;
    OSStatus status = CMBlockBufferCreateEmpty(kCFAllocatorDefault, 0, kCMBlockBufferAssureMemoryNowFlag,
                                               &backing);
    if (status)
        return status;

    // four fields, not five: 16.4's CMSampleTimingInfo has no sampleSize, and the port targets 16.4
    CMSampleTimingInfo timing = { sbufDuration, sbufPTS, kCMTimeInvalid, kCMTimeInvalid };
    const size_t sizes[1] = { 0 };
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreate(allocator, backing, true, NULL, NULL, formatDescription,
                                  1, 1, &timing, 1, sizes, &sampleBuffer);
    CFRelease(backing);
    if (status)
        return status;

    // The attachment is what carries the group, and it retains it: kCMAttachmentMode_ShouldNotPropagate,
    // so a buffer that is copied does not hand its group to the copy. GetTaggedBufferGroup reads it back,
    // and a buffer that never had one answers NULL - measured, and it is what makes the pair specific to
    // this kind of sample buffer rather than a property of sample buffers in general.
    CMSetAttachment(sampleBuffer, CharonGroupKey, taggedBufferGroup, kCMAttachmentMode_ShouldNotPropagate);
    *sBufOut = sampleBuffer;
    return noErr;
}

CMTaggedBufferGroupRef CM_NULLABLE CMSampleBufferGetTaggedBufferGroup(CMSampleBufferRef CM_NONNULL sbuf)
{
    if (!sbuf)
        return NULL;
    return (CMTaggedBufferGroupRef)CMGetAttachment(sbuf, CharonGroupKey, NULL);
}
