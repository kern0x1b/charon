#import "CharonVideoToolbox.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VTDecompressionSession.h>
#include <VideoToolbox/VTCompressionSession.h>
#include <VideoToolbox/VTErrors.h>

// Two of VideoToolbox's queries, both of which SDK 26.2 declares at 11.0 and neither of which any release
// this port builds exports (tools/corpus/dump-cache.lua over $HOME/.charon/dyld/4.3/dyld_shared_cache_armv7
// and over the 6.1.3 armv7 dump, 2026-10-03: zero hits for _VTIsHardwareDecodeSupported and for
// _VTCopySupportedPropertyDictionaryForEncoder), so the port exports both.
//
// NEITHER IS ANSWERED FROM A TABLE OF WHAT THIS HARDWARE HAS. That is the whole design, and the reason is
// measured: the obvious oracle for VTIsHardwareDecodeSupported is the decoder's own supported-property
// dictionary, and **that function does not exist at any band this port builds or any band this wave
// holds** -
//
//   _VTDecompressionSessionCopySupportedPropertyDictionaryForDecoder  4.3=0 6.1.3=0 6.0=0 7.0.1=0
//                                                                     10.3.4=0 12.0=0 16.0=0 18.0=0
//   _VTCompressionSessionCopySupportedPropertyDictionaryForEncoder    4.3=0 6.1.3=0 6.0=0 7.0.1=0
//                                                                     10.3.4=0 12.0=0 16.0=0 18.0=0
//
// so there is no dictionary to ask. What the release DOES have, at every band, is a specification key -
//
//   _kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder  4.3=1 6.1.3=1
//   _kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder  4.3=1 6.1.3=1
//   _VTDecompressionSessionCreate 4.3=1  6.1.3=1     _VTCompressionSessionCreate 4.3=1 6.1.3=1
//   _CMVideoFormatDescriptionCreate 4.3=1 6.1.3=1    _VTSessionCopySupportedPropertyDictionary 4.3=1 6.1.3=1
//
// and a session created with the hardware requirement set exists only if the release can do it in
// hardware. So asking the release by creating that session IS the release's answer, and it is a different
// answer on different hardware - which is what the function is for. CMVideoFormatDescriptionCreate takes
// the codec type, the width and the height and nothing else (CMFormatDescription.h:909, iOS 4.0), so the
// probe needs no parameter sets and works for every codec type the caller names.

// The size the probe asks the release about. A session's existence turns on the CODEC and the hardware
// requirement, not on the dimensions, and the release's own decoder dictionaries are asked by the apps that
// ship at sizes no bigger than this; 320x240 is also what the host measurement of the sibling function used
// (facts/VideoToolbox/Queries.md).
static const int32_t kCharonVTProbeWidth = 320;
static const int32_t kCharonVTProbeHeight = 240;

// The release's own answer to "can you decode this codec in hardware", asked by trying. A NULL session with
// noErr is not possible - VTDecompressionSessionCreate either hands one back or fails - so the status is
// the answer and nothing else is consulted.
static Boolean charon_can_decode(CMVideoCodecType codecType, CFStringRef requirement)
{
    CMVideoFormatDescriptionRef format = NULL;
    if (CMVideoFormatDescriptionCreate(kCFAllocatorDefault, codecType, kCharonVTProbeWidth,
                                      kCharonVTProbeHeight, NULL, &format) != noErr || !format)
        return false;
    const void *keys[] = { requirement };
    const void *values[] = { kCFBooleanTrue };
    CFDictionaryRef specification = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
                                                       &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
    VTDecompressionSessionRef session = NULL;
    // No destination attributes and no output callback: nothing is decoded here, the session's existence is
    // the whole of the question, and both of those parameters are documented as optional.
    OSStatus created = specification ? VTDecompressionSessionCreate(kCFAllocatorDefault, format, specification,
                                                                    NULL, NULL, &session)
                                    : kVTInvalidSessionErr;
    if (session) {
        VTDecompressionSessionInvalidate(session);
        CFRelease(session);
    }
    if (specification)
        CFRelease(specification);
    CFRelease(format);
    return created == noErr;
}

Boolean VTIsHardwareDecodeSupported(CMVideoCodecType codecType)
{
    return charon_can_decode(codecType, kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder);
}

// The encoder side of the same question has no SDK 26.2 entry point of its own - there is no
// VTIsHardwareEncodeSupported - so nothing here answers it and nothing above needs it to. What the encoder
// side IS asked for is below, and it is asked without the hardware requirement: the supported-property
// dictionary belongs to the encoder the release would actually choose, which is not necessarily a hardware
// one, and forcing the requirement first would answer a different question.

// VTCopySupportedPropertyDictionaryForEncoder: "Builds a list of supported properties and encoder ID for an
// encoder", and the caller must release both. Everything it returns is the RELEASE's own, asked for:
//
//   - the encoder ID is the compression session's kVTCompressionPropertyKey_EncoderID, read back through
//     the release's VTSessionCopyProperty;
//   - the property dictionary is the release's VTSessionCopySupportedPropertyDictionary for that session -
//     which is where the KEY SET and the per-key ATTRIBUTE DICTIONARY come from, and the port adds nothing
//     to either. Measured on this host, 2026-10-03 (facts/VideoToolbox/Queries.md): H264 gives 140 keys
//     with 0 NULL values, each value an attribute dictionary such as
//     { PropertyType = Number; ReadWriteStatus = ReadWrite; }, of which 45 are the EMPTY dictionary;
//     HEVC 169 keys with 43 empty; ProRes422 59 keys with all 59 empty; JPEG 54 keys with 52 empty;
//   - a codec with NO encoder answers kVTCouldNotFindVideoEncoderErr (-12908) with no encoder ID and no
//     dictionary, measured for MPEG2 and for AV1 on this host, and NOT an empty dictionary.
OSStatus VTCopySupportedPropertyDictionaryForEncoder(
    int32_t width, int32_t height, CMVideoCodecType codecType, CFDictionaryRef encoderSpecification,
    CFStringRef *encoderIDOut, CFDictionaryRef *supportedPropertiesOut)
{
    if (encoderIDOut)
        *encoderIDOut = NULL;
    if (supportedPropertiesOut)
        *supportedPropertiesOut = NULL;
    if (width <= 0 || height <= 0)
        return kVTParameterErr;

    // The 16.4 SDK's VTCompressionSessionCreate takes no codec list - the encoderSpecification IS how a
    // caller names an encoder - so the caller's dictionary goes in the position the header gives it and
    // nothing is invented on either side.
    VTCompressionSessionRef session = NULL;
    OSStatus created = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, codecType,
                                                  encoderSpecification, NULL, NULL, NULL, NULL, &session);
    if (created != noErr || !session) {
        // No encoder for this codec, or the caller's own specification refused it. Both are the -12908 the
        // host answers for a codec it has no encoder for, which is the release's own code (VTErrors.h:37),
        // and the header's "caller must release" is satisfied by handing back nothing to release.
        if (session)
            CFRelease(session);
        return created == noErr ? kVTCouldNotFindVideoEncoderErr : created;
    }

    OSStatus status = noErr;
    CFTypeRef identifier = NULL;
    if (VTSessionCopyProperty(session, kVTCompressionPropertyKey_EncoderID, NULL, &identifier) == noErr &&
        identifier) {
        if (encoderIDOut)
            *encoderIDOut = (CFStringRef)identifier;
        else
            CFRelease(identifier);
    }
    CFDictionaryRef supported = NULL;
    if (VTSessionCopySupportedPropertyDictionary(session, &supported) == noErr && supported) {
        if (supportedPropertiesOut)
            *supportedPropertiesOut = supported;
        else
            CFRelease(supported);
    }
    VTCompressionSessionInvalidate(session);
    CFRelease(session);
    return status;
}