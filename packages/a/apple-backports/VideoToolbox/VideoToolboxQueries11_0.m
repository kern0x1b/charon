#import "CharonVideoToolbox.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VTCompressionSession.h>
#include <VideoToolbox/VTErrors.h>

// VTCopySupportedPropertyDictionaryForEncoder: "Builds a list of supported properties and encoder ID for an
// encoder", and the caller must release both. SDK 26.2 declares it at 11.0 (VTVideoEncoderList.h:55-64) and
// no release this port builds exports it (_VTCopySupportedPropertyDictionaryForEncoder is absent from the 4.3
// and the 6.1.3 armv7 caches), so the port exports it.
//
// ONE ROW OF THE SAME FAMILY IS NOT HERE AND SAYS SO. VTIsHardwareDecodeSupported was written against this
// release's own kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder - a session created with
// that key exists only if the release can decode the codec in hardware - and then measured on the 6.1.3
// release itself through xmake emulate, per codec, with and without the key:
//
//   H264     noKey=-12906  withKey=-12906        JPEG  noKey=0  withKey=-12906
//   MPEG4    noKey=-12906  withKey=-12906        HEVC  noKey=-12906  withKey=-12906
//   ProRes   noKey=-12906  withKey=-12906
//
// -12906 is kVTVideoDecoderMalfunctionErr, which is what the release answers for a format description with
// no parameter sets, so four of the five codecs never reached the question; and the emulator has NO decoder
// hardware at all, so "JPEG creates without the key and fails with it" is also exactly what a release that
// DOES honour the key answers on a machine with no hardware JPEG decoder. The run therefore cannot tell an
// ignored key from an honoured one, which is the stronger reason the row is owed: the oracle is a device
// with real parameter sets. The function is not written, because a gate that finds an owed row answered by
// the build is a gate that has caught something true.



// Two of VideoToolbox's queries, both of which SDK 26.2 declares at 11.0 and neither of which any release
// this port builds exports (tools/corpus/dump-cache.lua over $HOME/.charon/dyld/4.3/dyld_shared_cache_armv7
// and over the 6.1.3 armv7 dump, 2026-10-03: zero hits for _VTIsHardwareDecodeSupported and for
// _VTCopySupportedPropertyDictionaryForEncoder), so the port exports both.
//
// The decoder's own supported-property dictionary would be the oracle for the other row of this family and
// **does not exist at any band this port builds or any band this wave holds** -
// _VTDecompressionSessionCopySupportedPropertyDictionaryForDecoder is absent from the 4.3, 6.0, 6.1.3, 7.0.1,
// 10.3.4, 12.0, 16.0 and 18.0 caches alike - which is part of why that row is owed rather than answered.

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