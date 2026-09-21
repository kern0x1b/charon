#import <CoreMedia/CoreMedia.h>

static const OSStatus invalidParameter = -12710;
static const OSStatus malformedRecord = -12712;

OSStatus CMVideoFormatDescriptionGetH264ParameterSetAtIndex(CMFormatDescriptionRef videoDesc, size_t parameterSetIndex, const uint8_t **parameterSetPointerOut,
                                                            size_t *parameterSetSizeOut, size_t *parameterSetCountOut, int *NALUnitHeaderLengthOut)
{
    if (!videoDesc || CMFormatDescriptionGetMediaType(videoDesc) != kCMMediaType_Video || CMFormatDescriptionGetMediaSubType(videoDesc) != kCMVideoCodecType_H264)
        return invalidParameter;
    CFDictionaryRef atoms = CMFormatDescriptionGetExtension(videoDesc, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
    CFDataRef record = atoms && CFGetTypeID(atoms) == CFDictionaryGetTypeID() ? CFDictionaryGetValue(atoms, CFSTR("avcC")) : NULL;
    if (!record || CFGetTypeID(record) != CFDataGetTypeID())
        return invalidParameter;
    if (parameterSetPointerOut)
        *parameterSetPointerOut = NULL;
    if (parameterSetSizeOut)
        *parameterSetSizeOut = 0;
    if (parameterSetCountOut)
        *parameterSetCountOut = 0;
    if (NALUnitHeaderLengthOut)
        *NALUnitHeaderLengthOut = 0;
    const uint8_t *bytes = CFDataGetBytePtr(record);
    size_t length = (size_t)CFDataGetLength(record);
    if (length < 6 || bytes[0] != 1)
        return malformedRecord;
    if (NALUnitHeaderLengthOut)
        *NALUnitHeaderLengthOut = (bytes[4] & 3) + 1;
    if (NALUnitHeaderLengthOut && !parameterSetPointerOut && !parameterSetSizeOut && !parameterSetCountOut)
        return 0;
    size_t at = 5;
    size_t seen = 0;
    BOOL extended = bytes[1] == 100 || bytes[1] == 110 || bytes[1] == 122 || bytes[1] == 144;
    for (int group = 0; group < (extended ? 3 : 2); group++) {
        if (group == 2) {
            if (at == length)
                break;
            if (at + 4 > length)
                return malformedRecord;
            at += 3;
        }
        if (at >= length)
            return malformedRecord;
        size_t n = group == 0 ? (bytes[at] & 0x1F) : bytes[at];
        at++;
        for (size_t i = 0; i < n; i++) {
            if (at + 2 > length)
                return malformedRecord;
            size_t size = ((size_t)bytes[at] << 8) | bytes[at + 1];
            at += 2;
            if (at + size > length)
                return malformedRecord;
            if (seen == parameterSetIndex) {
                if (parameterSetPointerOut)
                    *parameterSetPointerOut = bytes + at;
                if (parameterSetSizeOut)
                    *parameterSetSizeOut = size;
                if (!parameterSetCountOut)
                    return 0;
            }
            seen++;
            at += size;
        }
    }
    if (parameterSetCountOut)
        *parameterSetCountOut = seen;
    if (!parameterSetPointerOut && !parameterSetSizeOut)
        return 0;
    return parameterSetIndex < seen ? 0 : malformedRecord;
}
