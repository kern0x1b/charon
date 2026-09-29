// port-shims.h - what the host does not declare, so the port's own SecKeyElliptic10.m can be compiled
// and run against the host's Security in a differential.
//
// The port's file reaches four things of the release: SecKeyRawSign and SecKeyRawVerify (iOS 2.0, which
// the macOS SDK's SecKey.h does not declare at all) and the private keychain entry points that
// SecKey100.m already uses, which no SDK declares. Here each of them is answered by the host's own
// Security, so the port's code runs unmodified against a real P-256 key:
//
//   * SecKeyRawSign and SecKeyRawVerify become SecKeyCreateSignature and SecKeyVerifySignature with
//     the ECDSA-with-SHA-256 algorithm - which is what the release's own raw call does for a key of its
//     keychain, and the host's real signature and verification underneath.
//   * SecKeyCopyPublicBytes answers a SubjectPublicKeyInfo the way the release serialises one, so the
//     port's own DER reading runs and is not replaced by a convenient shape.
//   * SecKeyCopyAttributeDictionary answers the host's own attributes, which hold no kSecValueData for a
//     key: the port therefore sees a key of a keychain, which is the case it is written for, and takes
//     the release's signing path rather than the curve.

#ifndef PORT_SHIMS_H
#define PORT_SHIMS_H

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>

OSStatus SecKeyRawSign(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                       uint8_t *signature, size_t *signatureLength);
OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                         const uint8_t *signature, size_t signatureLength);
CFIndex SecKeyGetAlgorithmID(SecKeyRef key);
CFDictionaryRef SecKeyCopyAttributeDictionary(SecKeyRef key);
OSStatus SecKeyCopyPublicBytes(SecKeyRef key, CFDataRef *serialized);
SecKeyRef SecKeyCreateFromPublicData(CFAllocatorRef allocator, CFIndex algorithmID, CFDataRef serialized);

// The SubjectPublicKeyInfo of an EC public key, which is what the release's SecKeyCopyPublicBytes gives:
// a SEQUENCE of an AlgorithmIdentifier of the prime256v1 OIDs and a BIT STRING holding the point.
static const uint8_t CharonShimSubjectPublicKeyInfo[] = {
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08,
    0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00};

static OSStatus CharonShimRawSign(SecKeyRef key, const uint8_t *bytes, size_t length,
                                  uint8_t *signature, size_t *signatureLength)
{
    CFErrorRef error = NULL;
    SecKeyAlgorithm algorithm = kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
    CFDataRef digest = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
    CFDataRef made = SecKeyCreateSignature(key, algorithm, digest, &error);
    CFRelease(digest);
    if (error) {
        CFRelease(error);
    }
    if (!made) {
        return errSecInternalError;
    }
    size_t room = *signatureLength;
    size_t written = (size_t)CFDataGetLength(made);
    if (written > room) {
        CFRelease(made);
        return errSecParam;
    }
    memcpy(signature, CFDataGetBytePtr(made), written);
    CFRelease(made);
    *signatureLength = written;
    return errSecSuccess;
}

static OSStatus CharonShimRawVerify(SecKeyRef key, const uint8_t *bytes, size_t length,
                                    const uint8_t *signature, size_t signatureLength)
{
    SecKeyAlgorithm algorithm = kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
    CFDataRef digest = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
    CFDataRef made = CFDataCreate(kCFAllocatorDefault, signature, (CFIndex)signatureLength);
    CFErrorRef error = NULL;
    BOOL valid = SecKeyVerifySignature(key, algorithm, digest, made, &error);
    CFRelease(digest);
    CFRelease(made);
    if (error) {
        CFRelease(error);
    }
    return valid ? errSecSuccess : errSecVerifyFailed;
}

static CFDataRef CharonShimPublicBytes(SecKeyRef key)
{
    SecKeyRef publicKey = SecKeyCopyPublicKey(key);
    if (!publicKey) {
        return NULL;
    }
    CFErrorRef error = NULL;
    CFDataRef point = SecKeyCopyExternalRepresentation(publicKey, &error);
    CFRelease(publicKey);
    if (error) {
        CFRelease(error);
    }
    if (!point) {
        return NULL;
    }
    size_t length = (size_t)CFDataGetLength(point);
    if (length != 65) {
        CFRelease(point);
        return NULL;
    }
    uint8_t buffer[sizeof CharonShimSubjectPublicKeyInfo + 65];
    memcpy(buffer, CharonShimSubjectPublicKeyInfo, sizeof CharonShimSubjectPublicKeyInfo);
    memcpy(buffer + sizeof CharonShimSubjectPublicKeyInfo, CFDataGetBytePtr(point), 65);
    CFRelease(point);
    return CFDataCreate(kCFAllocatorDefault, buffer, (CFIndex)sizeof buffer);
}

OSStatus SecKeyRawSign(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                       uint8_t *signature, size_t *signatureLength)
{
    (void)padding;
    return CharonShimRawSign(key, bytes, length, signature, signatureLength);
}

OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                         const uint8_t *signature, size_t signatureLength)
{
    (void)padding;
    return CharonShimRawVerify(key, bytes, length, signature, signatureLength);
}

CFIndex SecKeyGetAlgorithmID(SecKeyRef key)
{
    (void)key;
    return 0;
}

CFDictionaryRef SecKeyCopyAttributeDictionary(SecKeyRef key)
{
    // The host's own attributes, which for an EC key hold no kSecValueData: the port sees a key of a
    // keychain and takes the release's own signing path, which is what this differential is about.
    return SecKeyCopyAttributes(key);
}

OSStatus SecKeyCopyPublicBytes(SecKeyRef key, CFDataRef *serialized)
{
    CFDataRef bytes = CharonShimPublicBytes(key);
    if (!bytes) {
        return errSecInternalError;
    }
    *serialized = bytes;
    return errSecSuccess;
}

SecKeyRef SecKeyCreateFromPublicData(CFAllocatorRef allocator, CFIndex algorithmID, CFDataRef serialized)
{
    (void)algorithmID;
    (void)serialized;
    return NULL;
}

#endif
