#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import "check.h"
#import "CharonCKWebAuth.h"

// The port's own four functions, renamed so they can be linked beside the host's own.
extern void *charonHost_SecKeyCreateSignature(SecKeyRef, SecKeyAlgorithm, CFDataRef, CFErrorRef *);
extern bool charonHost_SecKeyVerifySignature(SecKeyRef, SecKeyAlgorithm, CFDataRef, CFDataRef, CFErrorRef *);
extern CFDataRef charonHost_SecKeyCopyKeyExchangeResult(SecKeyRef, SecKeyAlgorithm, SecKeyRef, CFDictionaryRef, CFErrorRef *);
extern bool charonHost_SecKeyIsAlgorithmSupported(SecKeyRef, SecKeyOperationType, SecKeyAlgorithm);

// The port's P-256 against the host's own Security.framework, in both directions.
//
// The host is the oracle: SecKeyCreateSignature, SecKeyVerifySignature and SecKeyCopyKeyExchangeResult
// are Apple's own there, and every answer of the port is checked against them, not against itself.
// Three things are held to it:
//
//   * a signature the port makes verifies under the host's public key, and one the host makes
//     verifies under the port's - so the encoding is the one Apple's parser reads, and the reader is
//     the one Apple's writer satisfies;
//   * the signature is the low-s half, which is the form SecKeyCreateSignature produces and which a
//     fixed pair (r, s) / (r, n-s) would fail;
//   * ECDH: each side's shared secret is the other side's, for two key pairs.
//
// The keys are the host's own, made with the attributes SecKeyCreateRandomKey is given for an elliptic
// key; the private scalar and the public point are what the host's SecKey exports, so nothing about
// the key is the port's.

// The harness's check takes a C string for the name; a computed one is given as an NSString.
static void check_named(BOOL passed, NSString *name, NSString *detail)
{
    charon_check(passed, [name UTF8String], detail);
}

static NSData *digestOf(NSData *message)
{
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(message.bytes, (CC_LONG)message.length, digest);
    return [NSData dataWithBytes:digest length:sizeof digest];
}

static SecKeyRef randomKey(NSString *type, SecKeyRef *publicOut)
{
    NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType: type,
                                 (__bridge id)kSecAttrKeySizeInBits: @256,
                                 (__bridge id)kSecAttrIsPermanent: @NO};
    CFErrorRef error = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
    if (error) {
        CFRelease(error);
    }
    if (!privateKey) {
        return NULL;
    }
    if (publicOut) {
        *publicOut = SecKeyCopyPublicKey(privateKey);
    }
    return privateKey;
}

static NSData *pointOf(SecKeyRef publicKey);

// What a key's external representation is, as the host answers it: a P-256 *public* key is the
// uncompressed point (a 0x04 tag and the two 32 byte coordinates, 65 bytes), and a *private* key is
// 97 bytes whose shape the host does not document - a 0x04 tag, a length byte, then 96 bytes that are
// the scalar and the two coordinates somewhere in it.
//
// The scalar is therefore found the way the port finds it, by the same rule rather than by a shape read
// off the host: every 32 byte window is tried as a private key and the one whose derived public point
// is the point the host publishes is the scalar. That this rule picks the right window on the host is
// what the check below is for; the port runs the same rule against a blob whose shape nobody has read.
static NSData *scalarOf(SecKeyRef privateKey, SecKeyRef publicKey)
{
    CFErrorRef error = NULL;
    CFDataRef external = SecKeyCopyExternalRepresentation(privateKey, &error);
    if (error) {
        CFRelease(error);
    }
    if (!external) {
        return nil;
    }
    NSData *blob = CFBridgingRelease(external);
    NSData *point = pointOf(publicKey);
    if (point.length != 65) {
        return nil;
    }
    const uint8_t *bytes = blob.bytes;
    for (NSUInteger offset = 0; offset + 32 <= blob.length; offset++) {
        uint8_t derived[65];
        if (CharonCKPublicKeyES256(bytes + offset, derived) == 65 && memcmp(derived, point.bytes, 65) == 0) {
            return [NSData dataWithBytes:bytes + offset length:32];
        }
    }
    return nil;
}

static NSData *pointOf(SecKeyRef publicKey)
{
    CFErrorRef error = NULL;
    CFDataRef external = SecKeyCopyExternalRepresentation(publicKey, &error);
    if (error) {
        CFRelease(error);
    }
    if (!external) {
        return nil;
    }
    return CFBridgingRelease(external);
}

static NSData *hostSignature(SecKeyRef privateKey, NSData *digest, SecKeyAlgorithm algorithm)
{
    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(privateKey, algorithm, (__bridge CFDataRef)digest, &error);
    if (error) {
        CFRelease(error);
    }
    if (!signature) {
        return nil;
    }
    return CFBridgingRelease(signature);
}

static BOOL hostVerifies(SecKeyRef publicKey, NSData *data, NSData *signature, SecKeyAlgorithm algorithm)
{
    CFErrorRef error = NULL;
    BOOL valid = SecKeyVerifySignature(publicKey, algorithm, (__bridge CFDataRef)data,
                                       (__bridge CFDataRef)signature, &error);
    if (error) {
        CFRelease(error);
    }
    return valid;
}

int main(int argc, char **argv)
{
    NSString *folder = argc > 1 ? @(argv[1]) : @".";
    setvbuf(stdout, NULL, _IOLBF, 0);

    SecKeyRef hostPrivatePublic = NULL;
    SecKeyRef hostPrivate = randomKey((__bridge id)kSecAttrKeyTypeECSECPrimeRandom, &hostPrivatePublic);
    if (hostPrivate == NULL || hostPrivatePublic == NULL) {
        printf("FAIL the host made no P-256 key pair: nothing to compare against\n");
        return 1;
    }
    NSData *hostScalar = scalarOf(hostPrivate, hostPrivatePublic);
    NSData *hostPoint = pointOf(hostPrivatePublic);
    charon_check(hostScalar.length == 32, @"the host's private key exports a 32 byte scalar",
                     [NSString stringWithFormat:@"%lu bytes", (unsigned long)hostScalar.length]);
    check_named(hostPoint.length == 65 && ((const uint8_t *)hostPoint.bytes)[0] == 0x04,
                 @"and its public key an uncompressed 65 byte point",
                     [NSString stringWithFormat:@"%lu bytes", (unsigned long)hostPoint.length]);
    if (hostScalar.length != 32 || hostPoint.length != 65) {
        return charon_failures == 0 ? 0 : 1;
    }

    SecKeyAlgorithm ecdsa = kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
    // The host SDK names no ECDH algorithm: kSecKeyAlgorithmECDH is the device-side one (iOS 10 and
    // later), and the host answers the same exchange through
    // kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256, which is the same operation.
    SecKeyAlgorithm ecdh = kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256;

    // 1. The port's signature verifies under the host's key, and it is the signature of the digest.
    for (NSUInteger length = 0; length <= 130; length += 65) {
        NSMutableData *message = [NSMutableData dataWithLength:length];
        if (length > 0) {
            arc4random_buf(message.mutableBytes, length);
        }
        NSData *digest = digestOf(message);
        uint8_t der[72];
        int written = CharonCKDigestSignES256(hostScalar.bytes, digest.bytes, der, sizeof der);
        check_named(written > 0,
                     [NSString stringWithFormat:@"the port signs a %lu byte message", (unsigned long)length],
                     [NSString stringWithFormat:@"the port wrote %d bytes", written]);
        if (written <= 0) {
            continue;
        }
        NSData *signature = [NSData dataWithBytes:der length:(NSUInteger)written];
        check_named(hostVerifies(hostPrivatePublic, digest, signature, ecdsa),
                     [NSString stringWithFormat:@"and the host's own SecKeyVerifySignature accepts it, for a %lu byte message", (unsigned long)length],
                     @"the host refused a signature the port made");
        check_named(!hostVerifies(hostPrivatePublic, digest, signature, kSecKeyAlgorithmECDSASignatureDigestX962SHA384),
                     [NSString stringWithFormat:@"and the host refuses it under another algorithm, for a %lu byte message", (unsigned long)length],
                     @"the host accepted the signature under SHA-384 as well");
    }

    // 2. A signature the host makes verifies through the port, in DER and in the low-s half.
    for (NSUInteger length = 0; length <= 130; length += 65) {
        NSMutableData *message = [NSMutableData dataWithLength:length];
        if (length > 0) {
            arc4random_buf(message.mutableBytes, length);
        }
        NSData *digest = digestOf(message);
        NSData *signature = hostSignature(hostPrivate, digest, ecdsa);
        check_named(signature.length > 0,
                     [NSString stringWithFormat:@"the host signs a %lu byte message", (unsigned long)length],
                     [NSString stringWithFormat:@"%lu bytes", (unsigned long)signature.length]);
        if (signature.length == 0) {
            continue;
        }
        check_named(CharonCKDigestVerifyES256(hostPoint.bytes, hostPoint.length, digest.bytes,
                                               signature.bytes, signature.length),
                     [NSString stringWithFormat:@"and the port accepts that signature, for a %lu byte message", (unsigned long)length],
                     @"the port refused a signature the host made");
        // A signature of another message must not verify: the pair is a signature of one message only.
        uint8_t other[CC_SHA256_DIGEST_LENGTH];
        memset(other, length == 0 ? 0x5a : 0xa5, sizeof other);
        check_named(!CharonCKDigestVerifyES256(hostPoint.bytes, hostPoint.length, other,
                                                signature.bytes, signature.length),
                     [NSString stringWithFormat:@"and refuses it for another message, for a %lu byte message", (unsigned long)length],
                     @"the port accepted a signature of a different message");
    }

    // 3. The low-s half: the host's signature never has s over the group order's half, and the
    //    signature the port makes has the same property. (r, s) and (r, n-s) are both valid, so a
    //    signature that verifies is not yet the form Apple's Security produces.
    static const uint8_t order[32] = {0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
                                      0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                                      0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84,
                                      0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51};
    uint8_t half[32];
    memset(half, 0, sizeof half);
    for (int index = 0; index < 31; index++) {
        half[index] = (uint8_t)((order[index] >> 1) | ((order[index + 1] & 1u) << 7));
    }
    half[31] = (uint8_t)(order[31] >> 1);
    NSUInteger lowS = 0, portLowS = 0, samples = 24;
    for (NSUInteger sample = 0; sample < samples; sample++) {
        NSMutableData *message = [NSMutableData dataWithLength:32];
        arc4random_buf(message.mutableBytes, 32);
        NSData *digest = digestOf(message);
        NSData *host = hostSignature(hostPrivate, digest, ecdsa);
        if (host.length > 8) {
            // The second INTEGER of the DER, read where the low-s claim is about.
            const uint8_t *bytes = host.bytes;
            size_t firstSize = bytes[3];
            const uint8_t *second = bytes + 4 + firstSize;
            if (second[0] == 0x02 && second[1] <= 33) {
                uint8_t value[32];
                memset(value, 0, sizeof value);
                size_t skip = second[1] > 32 ? 1u : 0u;
                memcpy(value + (32 - (second[1] - skip)), second + 2 + skip, second[1] - skip);
                if (memcmp(value, half, 32) <= 0) {
                    lowS++;
                }
            }
        }
        uint8_t der[72];
        if (CharonCKDigestSignES256(hostScalar.bytes, digest.bytes, der, sizeof der) > 8) {
            size_t firstSize = der[3];
            const uint8_t *second = der + 4 + firstSize;
            if (second[0] == 0x02 && second[1] <= 33) {
                uint8_t value[32];
                memset(value, 0, sizeof value);
                size_t skip = second[1] > 32 ? 1u : 0u;
                memcpy(value + (32 - (second[1] - skip)), second + 2 + skip, second[1] - skip);
                if (memcmp(value, half, 32) <= 0) {
                    portLowS++;
                }
            }
        }
    }
    check_named(lowS == samples, @"every signature the host makes is the low-s half",
                     [NSString stringWithFormat:@"%lu of %lu", (unsigned long)lowS, (unsigned long)samples]);
    check_named(portLowS == samples, @"and so is every signature the port makes",
                     [NSString stringWithFormat:@"%lu of %lu", (unsigned long)portLowS, (unsigned long)samples]);

    // 4. ECDH: each side's shared secret is the other side's, for two pairs.
    SecKeyRef portPrivatePublic = NULL, peerPrivatePublic = NULL;
    SecKeyRef portPrivate = randomKey((__bridge id)kSecAttrKeyTypeECSECPrimeRandom, &portPrivatePublic);
    SecKeyRef peerPrivate = randomKey((__bridge id)kSecAttrKeyTypeECSECPrimeRandom, &peerPrivatePublic);
    NSData *portScalar = scalarOf(portPrivate, portPrivatePublic);
    NSData *portPoint = pointOf(portPrivatePublic);
    NSData *peerScalar = scalarOf(peerPrivate, peerPrivatePublic);
    NSData *peerPoint = pointOf(peerPrivatePublic);
    check_named(portScalar.length == 32 && portPoint.length == 65 && peerScalar.length == 32 && peerPoint.length == 65,
                 @"two more P-256 pairs for the exchange", @"a key did not export what a P-256 key exports");
    if (portScalar.length == 32 && portPoint.length == 65 && peerScalar.length == 32 && peerPoint.length == 65) {
        uint8_t mine[32];
        // The oracle is OpenSSL's own derivation over the same two keys, read from the files run.sh
        // made; the host's SecKeyCopyKeyExchangeResult reads through an in-memory key and dies, which
        // is why the file is the oracle here and the host's is not.
        NSData *oneHex = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"one.scalar"]];
        // OpenSSL's text form is one hex byte per line; the newlines are dropped first.
        NSMutableString *hex = [NSMutableString string];
        for (NSUInteger index = 0; index < oneHex.length; index++) {
            char c = (char)((const char *)oneHex.bytes)[index];
            if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
                [hex appendFormat:@"%c", c];
            }
        }
        // OpenSSL prints the scalar sign-padded to 33 bytes when the top bit is set, so 66 hex digits
        // where 32 bytes are wanted means a leading 00 that is not part of the number.
        if (hex.length == 66) {
            [hex deleteCharactersInRange:NSMakeRange(0, 2)];
        }
        NSData *hexData = [hex dataUsingEncoding:NSASCIIStringEncoding];
        NSMutableData *oneScalar = [NSMutableData dataWithCapacity:32];
        for (NSUInteger digit = 0; digit + 1 < hexData.length; digit += 2) {
            unsigned value = 0;
            for (NSUInteger half = 0; half < 2; half++) {
                char c = (char)((const char *)hexData.bytes)[digit + half];
                unsigned nibble = (c >= '0' && c <= '9') ? (unsigned)(c - '0')
                                : (c >= 'a' && c <= 'f') ? (unsigned)(c - 'a' + 10)
                                : (c >= 'A' && c <= 'F') ? (unsigned)(c - 'A' + 10) : 16u;
                if (nibble > 15) {
                    nibble = 0;
                }
                value = (value << 4) | nibble;
            }
            uint8_t byte = (uint8_t)value;
            [oneScalar appendBytes:&byte length:1];
        }
        NSData *onePoint = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"one.point"]];
        NSData *twoPoint = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"two.point"]];
        NSData *openssl = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"openssl.secret"]];
        check_named(oneScalar.length == 32 && twoPoint.length == 65 && openssl.length == 32,
                    @"OpenSSL's two keys and the secret it derives from them are in hand",
                    [NSString stringWithFormat:@"scalar %lu point %lu secret %lu", (unsigned long)oneScalar.length, (unsigned long)twoPoint.length, (unsigned long)openssl.length]);
        if (oneScalar.length == 32 && twoPoint.length == 65 && openssl.length == 32) {
            uint8_t theirs[32];
            uint8_t derivedPoint[65], derivedOther[65];
            check_named(CharonCKPublicKeyES256(oneScalar.bytes, derivedPoint) == 65, @"OpenSSL's first private scalar derives a public point",
                        @"micro-ecc refused the scalar OpenSSL printed");
            check_named(onePoint.length == 65 && memcmp(derivedPoint, onePoint.bytes, 65) == 0,
                        @"and it is the point OpenSSL published for that same key, so the two files are one key",
                        [NSString stringWithFormat:@"derived %02x..%02x, published %lu bytes", derivedPoint[0], derivedPoint[64], (unsigned long)onePoint.length]);
            check_named(memcmp(derivedPoint, twoPoint.bytes, 65) != 0, @"and not the point of the other key",
                        @"the two keys have the same public point");
            charon_check(CharonCKSharedSecretES256(oneScalar.bytes, twoPoint.bytes, twoPoint.length, mine) == 1,
                         @"the port derives a shared secret from OpenSSL's keys", @"micro-ecc refused");
            memcpy(theirs, openssl.bytes, 32);
            check_named(memcmp(mine, theirs, 32) == 0, @"and it is the same secret OpenSSL derives, byte for byte",
                        [NSString stringWithFormat:@"port %02x.., openssl %02x..", mine[0], theirs[0]]);
            printf("openssl secret: %s\n", [[[openssl description] substringToIndex:16] UTF8String]);
        }
        charon_check(CharonCKSharedSecretES256(portScalar.bytes, peerPoint.bytes, peerPoint.length, mine) == 1,
                     "the port makes a shared secret with the peer's point", @"micro-ecc refused");
        CFErrorRef error = NULL;
        charon_check(SecKeyCopyKeyExchangeResult != NULL, "the host has its own SecKeyCopyKeyExchangeResult, which is not the oracle here",
                     @"the host has no such function");
        if (error) {
            CFRelease(error);
        }
        // (The host's own exchange is not asked here: it reads through an in-memory key and dies with
        // a SIGSEGV inside Security.framework, measured; the secret OpenSSL derives is the oracle.)
        uint8_t reverse[32];
        charon_check(CharonCKSharedSecretES256(peerScalar.bytes, portPoint.bytes, portPoint.length, reverse) == 1,
                     "the exchange is the same from the other side", @"micro-ecc refused");
        charon_check(memcmp(mine, reverse, 32) == 0, @"and both sides reach one secret",
                     @"the two directions differ");
        // A public point of another pair must give another secret.
        SecKeyRef otherPrivatePublic = NULL;
        SecKeyRef otherPrivate = randomKey((__bridge id)kSecAttrKeyTypeECSECPrimeRandom, &otherPrivatePublic);
        NSData *otherPoint = pointOf(otherPrivatePublic);
        uint8_t withOther[32];
        if (otherPoint.length == 65 && CharonCKSharedSecretES256(portScalar.bytes, otherPoint.bytes, otherPoint.length, withOther)) {
            charon_check(memcmp(mine, withOther, 32) != 0, @"a point of another pair gives another secret",
                         @"two different pairs gave the same secret");
        }
        if (otherPrivate) {
            CFRelease(otherPrivate);
        }
        if (otherPrivatePublic) {
            CFRelease(otherPrivatePublic);
        }
    }

    // The port's own four functions, asked about the host's real P-256 key. The shims in port-shims.h
    // answer the release's SecKeyRawSign and SecKeyRawVerify with the host's own signing and
    // verification, so what runs here is the port's code over a key that is really a key.
    printf("port: the port's own four functions, over the host's real P-256 key\n"); fflush(stdout);
    SecKeyAlgorithm digestAlgorithm = kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
    // The ECDH algorithm's name: no SDK the host builds against declares kSecKeyAlgorithmECDH, only
    // the family whose names are these strings, which is what the port matches on.
    SecKeyAlgorithm charonHostECDH = (SecKeyAlgorithm)CFSTR("ECDH.standardX963SHA256");
    for (NSUInteger length = 0; length <= 130; length += 65) {
        NSMutableData *message = [NSMutableData dataWithLength:length];
        if (length > 0) {
            arc4random_buf(message.mutableBytes, length);
        }
        NSData *digest = digestOf(message);
        CFErrorRef portError = NULL;
        CFDataRef made = charonHost_SecKeyCreateSignature(hostPrivate, digestAlgorithm, (__bridge CFDataRef)digest, &portError);
        if (portError) {
            CFRelease(portError);
        }
        check_named(made != NULL, [NSString stringWithFormat:@"the port's own SecKeyCreateSignature signs a %lu byte message", (unsigned long)length],
                    @"the port refused to sign");
        if (made) {
            NSData *signature = CFBridgingRelease(made);
            check_named(hostVerifies(hostPrivatePublic, digest, signature, digestAlgorithm),
                        [NSString stringWithFormat:@"and the host's own SecKeyVerifySignature accepts the port's signature, for a %lu byte message", (unsigned long)length],
                        @"the host refused a signature the port made");
            CFErrorRef verifyError = NULL;
            bool verified = charonHost_SecKeyVerifySignature(hostPrivatePublic, digestAlgorithm, (__bridge CFDataRef)digest,
                                                            (__bridge CFDataRef)signature, &verifyError);
            if (verifyError) {
                CFRelease(verifyError);
            }
            check_named(verified, [NSString stringWithFormat:@"and the port's own SecKeyVerifySignature accepts it too, for a %lu byte message", (unsigned long)length],
                        @"the port refused its own signature");
            uint8_t other[CC_SHA256_DIGEST_LENGTH];
            memset(other, 0x3c, sizeof other);
            CFErrorRef wrongError = NULL;
            bool wrong = charonHost_SecKeyVerifySignature(hostPrivatePublic, digestAlgorithm, (__bridge CFDataRef)digest,
                                                         (__bridge CFDataRef)signature, &wrongError);
            if (wrongError) {
                CFRelease(wrongError);
            }
            check_named(wrong, [NSString stringWithFormat:@"and answers false for a signature of another message, for a %lu byte message", (unsigned long)length],
                        @"the port accepted a signature of a different message");
        }
    }

    // What the port says it can do. The exchange is the one it cannot: the release has no elliptic key
    // agreement, and the check that the port says NO is the one that keeps this honest.
    check_named(charonHost_SecKeyIsAlgorithmSupported(hostPrivate, kSecKeyOperationTypeSign, digestAlgorithm),
                @"the port says a key signs", @"the port says it cannot sign a key it is asked about");
    check_named(charonHost_SecKeyIsAlgorithmSupported(hostPrivate, kSecKeyOperationTypeVerify, digestAlgorithm),
                @"and that it verifies", @"the port says it cannot verify");
    check_named(!charonHost_SecKeyIsAlgorithmSupported(hostPrivate, kSecKeyOperationTypeKeyExchange,
                                                       charonHostECDH),
                @"and that it cannot exchange, which is the measured answer for this release", @"the port claims an exchange");
    check_named(!charonHost_SecKeyIsAlgorithmSupported(hostPrivate, kSecKeyOperationTypeEncrypt, digestAlgorithm),
                @"nor encrypt, which P-256 has no vocabulary for in Security", @"the port claims an encryption");
    CFErrorRef exchangeError = NULL;
    CFDataRef secret = charonHost_SecKeyCopyKeyExchangeResult(hostPrivate,
                                                               charonHostECDH,
                                                               hostPrivatePublic, NULL, &exchangeError);
    check_named(secret == NULL, @"the port's own SecKeyCopyKeyExchangeResult answers no secret", @"it answered one");
    if (secret) {
        CFRelease(secret);
    }
    check_named(exchangeError != NULL, @"with the error that says why", @"no error at all");
    if (exchangeError) {
        NSError *error = (__bridge NSError *)exchangeError;
        check_named([error.domain isEqualToString:NSOSStatusErrorDomain] && error.code == errSecParam,
                    @"which is NSOSStatusErrorDomain errSecParam", [NSString stringWithFormat:@"%@ %ld", error.domain, (long)error.code]);
        check_named([error.localizedDescription rangeOfString:@"elliptic"].location != NSNotFound,
                    @"and a description that names the elliptic agreement the release lacks",
                    [NSString stringWithFormat:@"%@", error.localizedDescription]);
        CFRelease(exchangeError);
    }
    CFErrorRef nilKeyError = NULL;
    CFDataRef noKey = charonHost_SecKeyCopyKeyExchangeResult(NULL, charonHostECDH,
                                                             hostPrivatePublic, NULL, &nilKeyError);
    check_named(noKey == NULL, @"and a nil key is the same refusal", @"it answered one");
    if (noKey) {
        CFRelease(noKey);
    }
    if (nilKeyError) {
        CFRelease(nilKeyError);
    }

    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures == 0 ? 0 : 1;
}
