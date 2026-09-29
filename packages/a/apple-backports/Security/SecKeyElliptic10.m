#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <string.h>
#import <stdlib.h>

// The four Security calls of iOS 10 that sign, verify, exchange and say what a key can do.
//
// The signing is the release's own. iOS 6.1.3 has SecKeyRawSign and SecKeyRawVerify (iOS 2.0, the two
// are in the armv7 shared cache of that release), and they take an elliptic key and a digest, so a
// signature of a key the release made needs no curve here at all: SecKeyRawSign does the arithmetic and
// this file only reads what it hands back. The curve is needed for the keys this package makes itself
// and for nothing else - charon@micro-ecc, BSD-2, through the JOSE and the ECDH that package carries
// (facts/Security/SecKeyElliptic.md).

// The release's own keychain, which is where a key of an application lives: SecKeyCreateRandomKey
// (Security/SecKey100.m) makes one with the release's SecKeyGeneratePair, and these are the same private
// entry points that file uses to read one back.
extern CFIndex SecKeyGetAlgorithmID(SecKeyRef key);
extern CFDictionaryRef SecKeyCopyAttributeDictionary(SecKeyRef key);
extern OSStatus SecKeyCopyPublicBytes(SecKeyRef key, CFDataRef *serialized);
extern SecKeyRef SecKeyCreateFromPublicData(CFAllocatorRef allocator, CFIndex algorithmID, CFDataRef serialized);
// SecKeyRawSign and SecKeyRawVerify are declared by the SDK's own SecKey.h (iOS 2.0, deprecated in
// 15.0 in favour of the four calls of this file), and the release exports both, so they are called
// through that declaration and not through one written here.

// The curve, from charon@micro-ecc, for the keys this package makes itself: the uncompressed public
// point of a private scalar, a DER signature of a digest, and the ECDH shared secret. Every name here
// begins with Charon, so backports.lua's internal_symbol() keeps them out of this library's exports.
extern int CharonCKPublicKeyES256(const uint8_t *privateKey, uint8_t *out);
extern int CharonCKDigestSignES256(const uint8_t *privateKey, const uint8_t *digest, uint8_t *der, size_t capacity);
extern int CharonCKDigestVerifyES256(const uint8_t *publicKey, size_t publicLength, const uint8_t *digest,
                                    const uint8_t *der, size_t derLength);
extern int CharonCKSharedSecretES256(const uint8_t *privateKey, const uint8_t *peerPublic, size_t publicLength,
                                    uint8_t *secret);
extern void CharonCKSHA256(const uint8_t *message, size_t length, uint8_t *digest);

static void charon_elliptic_fail(CFErrorRef *error, OSStatus status, NSString *description)
{
    if (!error) {
        return;
    }
    *error = CFErrorCreate(kCFAllocatorDefault, (__bridge CFStringRef)NSOSStatusErrorDomain, status,
                           (__bridge CFDictionaryRef)@{@"NSDescription": description});
}

// The two kinds of key, which are told apart by where they are and not by what they are: a key of
// the release's own keychain is one the release made and can sign with, and a key this package made
// is one that holds its own scalar and needs the curve. Until the port has keys of its own kind -
// SecKeyCreateWithData and the EC arm of SecKeyCreateRandomKey - every key is the release's, and
// the marker below is what a key of the port's would carry in its attributes.
#define kCharonSecKeyMarker "CharonSecKeyScalar"

static BOOL charon_elliptic_is_port_key(SecKeyRef key)
{
    CFDictionaryRef attributes = SecKeyCopyAttributeDictionary(key);
    if (!attributes) {
        return NO;
    }
    CFTypeRef marker = CFDictionaryGetValue(attributes, CFSTR(kCharonSecKeyMarker));
    BOOL ours = marker != NULL;
    CFRelease(attributes);
    return ours;
}

// The 32 byte private scalar of a key of this package: the 32 bytes SecKeyCreateWithData keeps as the
// key's own kSecValueData beside the point it derived from them.
static BOOL charon_elliptic_port_scalar(SecKeyRef key, uint8_t scalar[32])
{
    CFDictionaryRef attributes = SecKeyCopyAttributeDictionary(key);
    if (!attributes) {
        return NO;
    }
    CFTypeRef stored = CFDictionaryGetValue(attributes, kSecValueData);
    BOOL whole = stored != NULL && CFGetTypeID(stored) == CFDataGetTypeID() && CFDataGetLength((CFDataRef)stored) == 32;
    if (whole) {
        memcpy(scalar, CFDataGetBytePtr((CFDataRef)stored), 32);
    }
    CFRelease(attributes);
    return whole;
}

// The uncompressed public point of a key: the BIT STRING inside the SubjectPublicKeyInfo the release
// serializes, which is a 0x04 tag and the two 32 byte coordinates.
static const uint8_t *charon_elliptic_value(const uint8_t *cursor, const uint8_t *end, uint8_t tag, size_t *length)
{
    if (cursor >= end || *cursor++ != tag || cursor >= end) {
        return NULL;
    }
    size_t value = *cursor++;
    if (value & 0x80) {
        size_t count = value & 0x7F;
        if (count == 0 || count > 4 || (size_t)(end - cursor) < count) {
            return NULL;
        }
        value = 0;
        while (count-- > 0) {
            value = (value << 8) | *cursor++;
        }
    }
    if ((size_t)(end - cursor) < value) {
        return NULL;
    }
    *length = value;
    return cursor;
}

static BOOL charon_elliptic_point(SecKeyRef key, uint8_t point[65])
{
    CFDataRef serialized = NULL;
    if (SecKeyCopyPublicBytes(key, &serialized) != errSecSuccess || !serialized) {
        if (serialized) {
            CFRelease(serialized);
        }
        return NO;
    }
    const uint8_t *bytes = CFDataGetBytePtr(serialized);
    const uint8_t *end = bytes + CFDataGetLength(serialized);
    size_t length = 0;
    const uint8_t *content = charon_elliptic_value(bytes, end, 0x30, &length);
    const uint8_t *innerEnd = content ? content + length : NULL;
    size_t algorithm = 0;
    const uint8_t *algorithmValue = content ? charon_elliptic_value(content, innerEnd, 0x30, &algorithm) : NULL;
    size_t bits = 0;
    const uint8_t *bitString = algorithmValue ? charon_elliptic_value(algorithmValue + algorithm, innerEnd, 0x03, &bits) : NULL;
    // The first byte of a BIT STRING counts the unused bits of the last one, which is 0 for a point.
    BOOL whole = bitString && bits == 66 && bitString[0] == 0x00 && bitString[1] == 0x04;
    if (whole) {
        memcpy(point, bitString + 1, 65);
    }
    CFRelease(serialized);
    return whole;
}

// The signature the release made, in the SEQUENCE of two INTEGERs that SecKeyCreateSignature answers.
//
// The release's SecKeyRawSign hands back the two halves of a P-256 signature where it puts them - the
// 64 bytes of r and s, or the DER of them - and which one it is the release's business, not an
// assumption: both shapes are read, and a result that is neither is refused rather than guessed at.
// r and s are put in the low-s half, which is the form Apple's own Security produces and which a
// CloudKit web services token is checked against; (r, s) and (r, n - s) are both valid signatures.
static const uint8_t uECCP256Order[32] = {0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
                                          0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                                          0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84,
                                          0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51};

static void charon_elliptic_order_half(uint8_t half[32])
{
    memset(half, 0, 32);
    for (int index = 0; index < 31; index++) {
        half[index] = (uint8_t)((uECCP256Order[index] >> 1) | ((uECCP256Order[index + 1] & 1u) << 7));
    }
    half[31] = (uint8_t)(uECCP256Order[31] >> 1);
}

static void charon_elliptic_order_minus(uint8_t out[32], const uint8_t value[32])
{
    unsigned borrow = 0;
    for (int index = 31; index >= 0; index--) {
        unsigned difference = (unsigned)uECCP256Order[index] - (unsigned)value[index] - borrow;
        out[index] = (uint8_t)difference;
        borrow = (difference >> 8) & 1u;
    }
}

static int charon_elliptic_der_integer(uint8_t *out, const uint8_t value[32])
{
    int first = 0;
    while (first < 31 && value[first] == 0) {
        first++;
    }
    int length = 32 - first;
    // An INTEGER is as many bytes as its value needs and one more when the top bit is set; a padding
    // byte the value did not need is a shape a DER reader refuses.
    if (value[first] & 0x80) {
        out[0] = 0x02;
        out[1] = (uint8_t)(length + 1);
        out[2] = 0x00;
        memcpy(out + 3, value + first, (size_t)length);
        return length + 3;
    }
    out[0] = 0x02;
    out[1] = (uint8_t)length;
    memcpy(out + 2, value + first, (size_t)length);
    return length + 2;
}

// The DER of the two halves the release made, or the DER the release made itself, handed on as it is.
static CFDataRef charon_elliptic_der(CFDataRef raw, CFErrorRef *error)
{
    if (!raw) {
        charon_elliptic_fail(error, errSecInternalError, @"the release's own signing handed back nothing");
        return NULL;
    }
    const uint8_t *bytes = CFDataGetBytePtr(raw);
    size_t length = (size_t)CFDataGetLength(raw);
    if (length > 2 && bytes[0] == 0x30 && bytes[1] == length - 2) {
        // Already the SEQUENCE of two INTEGERs: the release's own encoding, kept.
        return (CFDataRef)CFRetain(raw);
    }
    if (length != 64) {
        charon_elliptic_fail(error, errSecInternalError,
                             [NSString stringWithFormat:@"the release's own signing answered %lu bytes for a P-256 signature, which is neither the two 32 byte halves nor their DER",
                                                      (unsigned long)length]);
        return NULL;
    }
    uint8_t halves[64];
    memcpy(halves, bytes, 64);
    uint8_t half[32];
    charon_elliptic_order_half(half);
    if (memcmp(halves + 32, half, 32) > 0) {
        charon_elliptic_order_minus(halves + 32, halves + 32);
    }
    uint8_t der[72];
    size_t offset = 0;
    der[offset++] = 0x30;
    der[offset++] = 0;
    size_t content = offset;
    offset += (size_t)charon_elliptic_der_integer(der + offset, halves);
    offset += (size_t)charon_elliptic_der_integer(der + offset, halves + 32);
    der[1] = (uint8_t)(offset - content);
    return CFDataCreate(kCFAllocatorDefault, der, (CFIndex)offset);
}

// The name every elliptic exchange algorithm of Security's own vocabulary begins with: no SDK this
// port builds against declares kSecKeyAlgorithmECDH, only the family kSecKeyAlgorithmECDHKeyExchange*
// whose names are the strings below, and the header of SecKeyCopyKeyExchangeResult tells the caller
// to pass "kSecKeyAlgorithmECDH" - which is that family's own prefix.
static BOOL charon_elliptic_exchange(SecKeyAlgorithm algorithm, BOOL *hashed)
{
    if (!algorithm) {
        return NO;
    }
    NSString *name = (__bridge NSString *)algorithm;
    if (![name hasPrefix:@"ECDH"]) {
        return NO;
    }
    *hashed = [name hasSuffix:@"SHA1"] || [name hasSuffix:@"SHA224"] || [name hasSuffix:@"SHA256"]
        || [name hasSuffix:@"SHA384"] || [name hasSuffix:@"SHA512"];
    return YES;
}

Boolean SecKeyIsAlgorithmSupported(SecKeyRef key, SecKeyOperationType operation, SecKeyAlgorithm algorithm)
{
    if (!key || !algorithm) {
        return false;
    }
    BOOL hashed = NO;
    BOOL exchange = charon_elliptic_exchange(algorithm, &hashed);
    if (CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256)) {
        // Signing and verifying: the release signs with its own SecKeyRawSign for a key of its own
        // keychain, and this package signs with the curve for a key it made.
        return operation == kSecKeyOperationTypeSign || operation == kSecKeyOperationTypeVerify;
    }
    if (!exchange) {
        // Everything else is the release's own keychain's business, and Security/SecKey100.m answers
        // for the RSA algorithms it carries; an algorithm this port does not carry is false.
        return false;
    }
    if (operation != kSecKeyOperationTypeKeyExchange) {
        return false;   // P-256 has no encryption in Security's own vocabulary either
    }
    // The exchange is the one operation the release cannot do for an elliptic key, and this is
    // measured rather than assumed: the armv7 shared cache of iOS 6.1.3 exports SecKeyRawSign and
    // SecKeyRawVerify and no elliptic exchange at all - its only key agreement is the finite-field
    // SecDH* family (SecDHComputeKey, SecDHGenerateKeypair), which is not a curve. So a key of the
    // release's keychain cannot exchange, and says so; a key of this package can, over the curve.
    return charon_elliptic_is_port_key(key);
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef data, CFErrorRef *error)
{
    if (!key || !data) {
        charon_elliptic_fail(error, errSecParam, @"a signature needs a key and the data to sign");
        return NULL;
    }
    BOOL digest = CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureMessageX962SHA256)
        || CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256);
    if (!digest) {
        charon_elliptic_fail(error, errSecParam,
                             [NSString stringWithFormat:@"algid:sign:%@: this port signs P-256 with SHA-256 and nothing else", algorithm]);
        return NULL;
    }
    BOOL ofMessage = CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureMessageX962SHA256);
    // A Digest algorithm signs the 32 bytes the caller took and a Message algorithm the message; both
    // are signed over the SHA-256 of it, and that is the one hash either of them is about.
    uint8_t hashed[32];
    if (ofMessage) {
        CharonCKSHA256(CFDataGetBytePtr(data), (size_t)CFDataGetLength(data), hashed);
    } else {
        if (CFDataGetLength(data) != 32) {
            charon_elliptic_fail(error, errSecParam,
                                 [NSString stringWithFormat:@"a P-256 signature is of a 32 byte digest and %ld were given", (long)CFDataGetLength(data)]);
            return NULL;
        }
        memcpy(hashed, CFDataGetBytePtr(data), 32);
    }
    if (charon_elliptic_is_port_key(key)) {
        uint8_t scalar[32];
        if (!charon_elliptic_port_scalar(key, scalar)) {
            charon_elliptic_fail(error, errSecParam, @"this key of the port's keeps no private scalar to sign with");
            return NULL;
        }
        uint8_t der[72];
        int written = CharonCKDigestSignES256(scalar, hashed, der, sizeof der);
        if (written <= 0) {
            charon_elliptic_fail(error, errSecInternalError, @"micro-ecc made no signature of the digest");
            return NULL;
        }
        return CFDataCreate(kCFAllocatorDefault, der, (CFIndex)written);
    }
    // The release's own signing. An elliptic key has no padding, so kSecPaddingNone is what it takes
    // and kSecPaddingPKCS1 is the RSA one; the emulator probe of facts/Security/SecKeyElliptic.md
    // measures which of them an EC key of the release accepts, and the answer is passed on as the
    // release gives it. The buffer is the release's own size for a P-256 signature and its two halves
    // or their DER, whichever it is that it fills, so nothing here is a guess about the shape.
    uint8_t raw[128];
    size_t written = sizeof raw;
    memset(raw, 0, sizeof raw);
    OSStatus status = SecKeyRawSign(key, kSecPaddingNone, hashed, sizeof hashed, raw, &written);
    if (status == errSecParam) {
        // Some releases want the RSA padding name for the same call and hand the padding on; that is
        // their own answer to a question, not a different key, so it is asked once and reported.
        written = sizeof raw;
        status = SecKeyRawSign(key, kSecPaddingPKCS1, hashed, sizeof hashed, raw, &written);
    }
    if (status != errSecSuccess) {
        charon_elliptic_fail(error, status != errSecSuccess ? status : errSecInternalError,
                             [NSString stringWithFormat:@"algid:sign:%@: the release's own SecKeyRawSign answered %d", algorithm, (int)status]);
        return NULL;
    }
    if (written > sizeof raw) {
        written = sizeof raw;
    }
    CFDataRef exact = CFDataCreate(kCFAllocatorDefault, raw, (CFIndex)written);
    CFDataRef der = charon_elliptic_der(exact, error);
    CFRelease(exact);
    return der;
}

Boolean SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef data, CFDataRef signature, CFErrorRef *error)
{
    if (!key || !data || !signature) {
        charon_elliptic_fail(error, errSecParam, @"a verification needs a key, the data and a signature");
        return false;
    }
    BOOL digest = CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureMessageX962SHA256)
        || CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256);
    if (!digest) {
        charon_elliptic_fail(error, errSecParam,
                             [NSString stringWithFormat:@"algid:verify:%@: this port verifies P-256 with SHA-256 and nothing else", algorithm]);
        return false;
    }
    BOOL ofMessage = CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureMessageX962SHA256);
    uint8_t hashed[32];
    if (ofMessage) {
        CharonCKSHA256(CFDataGetBytePtr(data), (size_t)CFDataGetLength(data), hashed);
    } else {
        if (CFDataGetLength(data) != 32) {
            charon_elliptic_fail(error, errSecParam,
                                 [NSString stringWithFormat:@"a P-256 signature is of a 32 byte digest and %ld were given", (long)CFDataGetLength(data)]);
            return false;
        }
        memcpy(hashed, CFDataGetBytePtr(data), 32);
    }
    uint8_t point[65];
    if (charon_elliptic_is_port_key(key)) {
        if (!charon_elliptic_point(key, point)) {
            charon_elliptic_fail(error, errSecParam, @"this key publishes no uncompressed public point to verify with");
            return false;
        }
        return CharonCKDigestVerifyES256(point, sizeof point, hashed, CFDataGetBytePtr(signature),
                                         (size_t)CFDataGetLength(signature)) != 0;
    }
    // The release's own verification, over the DER as the release's own signing gave it. The two
    // halves are handed on as well, so that a signature the release made is verified by the release
    // whichever of the two shapes it answers.
    size_t length = (size_t)CFDataGetLength(signature);
    const uint8_t *bytes = CFDataGetBytePtr(signature);
    uint8_t raw[64];
    size_t halves = 0;
    if (length == 64) {
        memcpy(raw, bytes, 64);
        halves = 64;
    } else if (length > 8 && bytes[0] == 0x30) {
        // The SEQUENCE of two INTEGERs, read where DER puts them: each is at most 33 bytes and a value
        // shorter than 32 has leading zeros. Anything that is not that shape is left to the release.
        size_t offset = 2, inner = bytes[1];
        for (int which = 0; which < 2; which++) {
            if (offset + 2 > length || bytes[offset] != 0x02) {
                break;
            }
            size_t size = bytes[offset + 1];
            if (size == 0 || size > 33 || offset + 2 + size > length) {
                break;
            }
            memset(raw + which * 32, 0, 32);
            size_t skip = size > 32 ? 1u : 0u;
            memcpy(raw + which * 32 + (32 - (size - skip)), bytes + offset + 2 + skip, size - skip);
            offset += 2 + size;
        }
        halves = offset == inner + 2 ? 64 : 0;
    }
    OSStatus status;
    if (halves) {
        status = SecKeyRawVerify(key, kSecPaddingNone, hashed, sizeof hashed, raw, halves);
    } else {
        status = SecKeyRawVerify(key, kSecPaddingNone, hashed, sizeof hashed, bytes, length);
    }
    if (status != errSecSuccess) {
        // A signature that is not a signature is a false and not an error, which is what the host does
        // and what a caller of a verify loop relies on; only a refusal of the call itself is an error.
        return false;
    }
    return true;
}

CFDataRef SecKeyCopyKeyExchangeResult(SecKeyRef privateKey, SecKeyAlgorithm algorithm, SecKeyRef publicKey,
                                      CFDictionaryRef options, CFErrorRef *error)
{
    if (!privateKey || !publicKey) {
        charon_elliptic_fail(error, errSecParam, @"an exchange needs both keys");
        return NULL;
    }
    BOOL hashed = NO;
    if (!charon_elliptic_exchange(algorithm, &hashed)) {
        charon_elliptic_fail(error, errSecParam, [NSString stringWithFormat:@"algid:exchange:%@: this port exchanges over P-256 and nothing else", algorithm]);
        return NULL;
    }
    // A key of the release's own keychain cannot exchange, and that is measured: the armv7 shared
    // cache of iOS 6.1.3 exports no elliptic key agreement at all, its only one being the finite-field
    // SecDH* family, which is not a curve. SecKeyIsAlgorithmSupported says so for the same key; this
    // is the answer the call itself has to give.
    if (!charon_elliptic_is_port_key(privateKey)) {
        charon_elliptic_fail(error, errSecParam,
                             @"the release has no elliptic key agreement: its Security exports SecKeyRawSign and SecKeyRawVerify and only the finite-field SecDH family, so a key of its keychain cannot exchange");
        return NULL;
    }
    uint8_t scalar[32];
    if (!charon_elliptic_port_scalar(privateKey, scalar)) {
        charon_elliptic_fail(error, errSecParam, @"this key of the port's keeps no private scalar to exchange with");
        return NULL;
    }
    uint8_t peer[65];
    if (!charon_elliptic_point(publicKey, peer)) {
        charon_elliptic_fail(error, errSecParam, @"the peer's key publishes no uncompressed public point to exchange with");
        return NULL;
    }
    uint8_t secret[32];
    if (!CharonCKSharedSecretES256(scalar, peer, sizeof peer, secret)) {
        charon_elliptic_fail(error, errSecInternalError, @"micro-ecc made no shared secret of the two keys");
        return NULL;
    }
    // A "Standard" name hands back the X coordinate of the shared point as it is, and a name that ends
    // in a digest hands back that digest of it, which is what Security's own two families say they do.
    if (!hashed) {
        return CFDataCreate(kCFAllocatorDefault, secret, (CFIndex)sizeof secret);
    }
    uint8_t digest[32];
    CharonCKSHA256(secret, sizeof secret, digest);
    return CFDataCreate(kCFAllocatorDefault, digest, (CFIndex)sizeof digest);
}
