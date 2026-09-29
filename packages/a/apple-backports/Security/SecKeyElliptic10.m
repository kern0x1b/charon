#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <string.h>

// The four Security calls of iOS 10 that sign, verify, exchange and say what a key can do. The
// arithmetic is charon@micro-ecc's (BSD-2), through the JOSE and the ECDH that package carries; what
// this file is about is the other half: where the release keeps the key, and how the scalar is read
// out of it. iOS 6.1.3 has no SecKey at all, and no CommonCrypto elliptic curve, so nothing here could
// be written without a curve to call (facts/Security/SecKeyElliptic.md).

// The release's own keychain, which is where SecKeyCreateRandomKey (Security/SecKey100.m) puts the key
// it makes, reached the way that file reaches it.
extern CFIndex SecKeyGetAlgorithmID(SecKeyRef key);
extern CFDictionaryRef SecKeyCopyAttributeDictionary(SecKeyRef key);
extern OSStatus SecKeyCopyPublicBytes(SecKeyRef key, CFDataRef *serialized);
extern SecKeyRef SecKeyCreateFromPublicData(CFAllocatorRef allocator, CFIndex algorithmID, CFDataRef serialized);

// The curve, from charon@micro-ecc: the uncompressed public point of a 32 byte private key, a DER
// signature of a digest the caller took, and the ECDH shared secret. Every name here begins with
// Charon, so backports.lua's internal_symbol() keeps them out of this library's exports.
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

// The uncompressed public point of a key of the release's own keychain: the BIT STRING inside the
// SubjectPublicKeyInfo the release serializes, which is a 0x04 tag and the two 32 byte coordinates.
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

// The 32 byte private scalar of a key of the release's own keychain.
//
// The release keeps the key in its keychain and does not say where in the blob it keeps the scalar,
// and the shape it keeps it in cannot be read from here: no release this port runs can be asked, and
// the host's own SecKey keeps a different shape again (measured: 97 bytes, a 0x04 tag, a length byte,
// then the scalar and the two coordinates). So the scalar is *found* rather than assumed: every
// 32 byte window of the stored bytes is tried as a private key, the public point it derives is
// compared with the point the key itself publishes, and the window that derives the key's own point is
// the scalar. A blob whose shape nothing matches is refused, so a wrong answer cannot be signed with.
static BOOL charon_elliptic_scalar(SecKeyRef key, uint8_t scalar[32])
{
    uint8_t point[65];
    if (!charon_elliptic_point(key, point)) {
        return NO;
    }
    CFDataRef stored = NULL;
    CFDictionaryRef attributes = SecKeyCopyAttributeDictionary(key);
    if (attributes) {
        CFTypeRef value = CFDictionaryGetValue(attributes, kSecValueData);
        if (value && CFGetTypeID(value) == CFDataGetTypeID()) {
            stored = (CFDataRef)value;
        }
    }
    if (!stored) {
        if (attributes) {
            CFRelease(attributes);
        }
        return NO;
    }
    const uint8_t *bytes = CFDataGetBytePtr(stored);
    size_t length = (size_t)CFDataGetLength(stored);
    BOOL found = NO;
    for (size_t offset = 0; !found && offset + 32 <= length; offset++) {
        uint8_t derived[65];
        if (!CharonCKPublicKeyES256(bytes + offset, derived)) {
            continue;
        }
        if (memcmp(derived, point, 65) == 0) {
            memcpy(scalar, bytes + offset, 32);
            found = YES;
        }
    }
    CFRelease(attributes);
    return found;
}

// The name every elliptic exchange algorithm of Security's own vocabulary begins with: there is no
// kSecKeyAlgorithmECDH constant in any SDK this port builds against, only the family
// kSecKeyAlgorithmECDHKeyExchangeStandardX963* and ...CofactorX963* whose names are the strings below,
// and the header of SecKeyCopyKeyExchangeResult tells the caller to pass "kSecKeyAlgorithmECDH" - which
// is that family's own prefix. So the name is matched, not a constant that no header declares.
static BOOL charon_elliptic_exchange(SecKeyAlgorithm algorithm, BOOL *hashed)
{
    if (!algorithm) {
        return NO;
    }
    NSString *name = (__bridge NSString *)algorithm;
    if (![name hasPrefix:@"ECDH"]) {
        return NO;
    }
    // A name that ends in a digest is the one that hands back the hash of the shared secret; the
    // Standard names hand back its X coordinate as it is, which is what the header of the "Standard"
    // family says and what a caller of ECDH needs to make a key with.
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
    BOOL elliptic = CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256)
        || charon_elliptic_exchange(algorithm, &hashed);
    if (!elliptic) {
        // Everything else is the release's own keychain's business, and Security/SecKey100.m already
        // answers for the RSA algorithms it carries; an algorithm this port does not carry is false.
        return false;
    }
    uint8_t point[65];
    if (!charon_elliptic_point(key, point)) {
        return NO;
    }
    switch (operation) {
        case kSecKeyOperationTypeSign:
        case kSecKeyOperationTypeVerify:
            return CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256) ? true : false;
        case kSecKeyOperationTypeKeyExchange:
            return true;
        case kSecKeyOperationTypeEncrypt:
        case kSecKeyOperationTypeDecrypt:
            return false;   // P-256 has no encryption in Security's own vocabulary either
        default:
            return false;
    }
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef data, CFErrorRef *error)
{
    if (!key || !data) {
        charon_elliptic_fail(error, errSecParam, @"a signature needs a key and the data to sign");
        return NULL;
    }
    if (!CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256)) {
        charon_elliptic_fail(error, errSecParam, [NSString stringWithFormat:@"algid:sign:%@: this port signs with P-256 and SHA-256 and nothing else", algorithm]);
        return NULL;
    }
    // The algorithm says Digest: the data is the digest the caller took, and it is signed as it stands.
    if (CFDataGetLength(data) != 32) {
        charon_elliptic_fail(error, errSecParam,
                             [NSString stringWithFormat:@"a P-256 signature is of a 32 byte digest and %ld were given", (long)CFDataGetLength(data)]);
        return NULL;
    }
    uint8_t scalar[32];
    if (!charon_elliptic_scalar(key, scalar)) {
        charon_elliptic_fail(error, errSecParam,
                             @"the release's own keychain does not keep a 32 byte private scalar for this key that derives its public point");
        return NULL;
    }
    uint8_t der[72];
    int written = CharonCKDigestSignES256(scalar, CFDataGetBytePtr(data), der, sizeof der);
    if (written <= 0) {
        charon_elliptic_fail(error, errSecInternalError, @"micro-ecc made no signature of the digest");
        return NULL;
    }
    return CFDataCreate(kCFAllocatorDefault, der, (CFIndex)written);
}

Boolean SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef data, CFDataRef signature, CFErrorRef *error)
{
    if (!key || !data || !signature) {
        charon_elliptic_fail(error, errSecParam, @"a verification needs a key, the data and a signature");
        return false;
    }
    if (!CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256)) {
        charon_elliptic_fail(error, errSecParam, [NSString stringWithFormat:@"algid:verify:%@: this port verifies P-256 with SHA-256 and nothing else", algorithm]);
        return false;
    }
    if (CFDataGetLength(data) != 32) {
        charon_elliptic_fail(error, errSecParam,
                             [NSString stringWithFormat:@"a P-256 signature is of a 32 byte digest and %ld were given", (long)CFDataGetLength(data)]);
        return false;
    }
    uint8_t point[65];
    if (!charon_elliptic_point(key, point)) {
        charon_elliptic_fail(error, errSecParam, @"the release's own keychain publishes no uncompressed public point for this key");
        return false;
    }
    return CharonCKDigestVerifyES256(point, sizeof point, CFDataGetBytePtr(data), CFDataGetBytePtr(signature),
                                     (size_t)CFDataGetLength(signature)) != 0;
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
    uint8_t peer[65];
    if (!charon_elliptic_point(publicKey, peer)) {
        charon_elliptic_fail(error, errSecParam, @"the release's own keychain publishes no uncompressed public point for the peer's key");
        return NULL;
    }
    uint8_t scalar[32];
    if (!charon_elliptic_scalar(privateKey, scalar)) {
        charon_elliptic_fail(error, errSecParam,
                             @"the release's own keychain does not keep a 32 byte private scalar for this key that derives its public point");
        return NULL;
    }
    uint8_t secret[32];
    if (!CharonCKSharedSecretES256(scalar, peer, sizeof peer, secret)) {
        charon_elliptic_fail(error, errSecInternalError, @"micro-ecc made no shared secret of the two keys");
        return NULL;
    }
    // A "Standard" name hands back the X coordinate of the shared point as it is, and a name that
    // ends in a digest hands back that digest of it, which is what Security's own two families say
    // they do and what a caller of the hashed one needs to make a key with.
    if (!hashed) {
        return CFDataCreate(kCFAllocatorDefault, secret, (CFIndex)sizeof secret);
    }
    uint8_t digest[32];
    CharonCKSHA256(secret, sizeof secret, digest);
    return CFDataCreate(kCFAllocatorDefault, digest, (CFIndex)sizeof digest);
}
