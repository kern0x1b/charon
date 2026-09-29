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
//     the release's signing path rather than the curve - unless the key was registered with
//     CharonShimMarkPortKey, which is how a key *of the port's own kind* is put in the port's hands.
//
// Why the registration exists. SecKeyElliptic10.m tells the two kinds of key apart by one attribute:
// kCharonSecKeyScalar, beside the 32 byte kSecValueData of the private scalar, is what a key the port
// made would carry, and only SecKeyCreateWithData - the one entry point of that family the port has not
// written - would put it there. So without this the whole of the port's own curve path was unreachable
// from a host differential, and a mutant in it passed: the three CharonCK* calls the file makes at its
// lines 311, 378 and 456 were never executed. With it, the port is handed a key of its own kind and
// does the arithmetic itself; what the harness supplies is the key's material and the attribute the port
// looks for, which is the release's own contract for such a key, not a replacement for the port's code.
//
// The two spellings of the attribute key - this string and the port's #define - cannot be checked here,
// because the port's .m is a separate translation unit that never sees this header. They are not needed
// to be: if the two ever part company, the port stops recognising its own keys, takes the release's
// signing path for them, and the checks that name the curve's own signature and exchange fail. The run
// is the check.
//
// No keychain, no kSecAttrIsPermanent, no SecItem* call: the key the differential registers is one the
// host made in memory with SecKeyCreateWithData and nothing else, and it dies with the process.

#ifndef PORT_SHIMS_H
#define PORT_SHIMS_H

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <string.h>


static OSStatus SecKeyRawSign(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                              uint8_t *signature, size_t *signatureLength);
static OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                                const uint8_t *signature, size_t signatureLength);
static CFIndex SecKeyGetAlgorithmID(SecKeyRef key);
static CFDictionaryRef SecKeyCopyAttributeDictionary(SecKeyRef key);
static OSStatus SecKeyCopyPublicBytes(SecKeyRef key, CFDataRef *serialized);
static SecKeyRef SecKeyCreateFromPublicData(CFAllocatorRef allocator, CFIndex algorithmID, CFDataRef serialized);

// The attribute SecKeyElliptic10.m tells a key of the port's own kind by, spelled here because the
// harness has to answer SecKeyCopyAttributeDictionary and the port's translation unit never sees this
// header. The header's own comment above says why the run, and not this header, is what proves the two
// spellings agree.
#define CHARON_SHIM_SECKEY_MARKER "CharonSecKeyScalar"

// The keys registered as the port's own, and the scalar beside each. One slot each, because the
// differential registers two pairs and calls them one after another; a list would be a second thing to
// get wrong for no case the run has.
static SecKeyRef CharonShimPortKey = NULL;
static SecKeyRef CharonShimPortPublicKey = NULL;
static uint8_t CharonShimPortScalar[32];
static size_t CharonShimPortScalarLength = 0;

// Registers a key of the port's own kind. `scalar` is the private scalar the port will sign and
// exchange with, or NULL for a public key, which the port's verify path never asks a scalar of. Both
// the key and the attribute are what SecKeyCreateWithData would leave behind; nothing else about the
// key is the harness's.
//
// Not static, and that is the whole difference from the functions above it: this one is called from
// differential.m, which cannot include this header - the -D renames of the four port names would reach
// every mention of a name in it, and the header says what that costs. One definition, in the one
// translation unit that includes the header, and one declaration in the caller.
void CharonShimMarkPortKey(SecKeyRef privateKey, const uint8_t *scalar, size_t length)
{
    CharonShimPortKey = privateKey;
    if (scalar && length == sizeof CharonShimPortScalar) {
        memcpy(CharonShimPortScalar, scalar, sizeof CharonShimPortScalar);
        CharonShimPortScalarLength = length;
    }
}

void CharonShimMarkPortPublicKey(SecKeyRef publicKey)
{
    CharonShimPortPublicKey = publicKey;
}

// The SubjectPublicKeyInfo of an EC public key, which is what the release's SecKeyCopyPublicBytes gives:
// a SEQUENCE of an AlgorithmIdentifier of the prime256v1 OIDs and a BIT STRING holding the point.
static const uint8_t CharonShimSubjectPublicKeyInfo[] = {
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08,
    0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00};

// The host's own two functions are reached by name through dlsym, not by calling them: the
// differential renames the port's SecKeyCreateSignature and SecKeyVerifySignature to
// charonHost_SecKeyCreateSignature and charonHost_SecKeyVerifySignature with -D, and a -D renames
// every mention of the name in this header too - so a direct call here becomes a call back into the
// port, which calls the shim again, and the recursion ends on the stack guard page. The string in
// dlsym is not a mention, so the host's function is the one that is found.
static SecKeyAlgorithm CharonShimDigestAlgorithm(void)
{
    return kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
}

static OSStatus CharonShimRawSign(SecKeyRef key, const uint8_t *bytes, size_t length,
                                  uint8_t *signature, size_t *signatureLength)
{
    typedef CFDataRef (*CharonShimCreateSignature)(SecKeyRef, SecKeyAlgorithm, CFDataRef, CFErrorRef *);
    static CharonShimCreateSignature host = NULL;
    if (!host) {
        host = (CharonShimCreateSignature)dlsym(RTLD_DEFAULT, "SecKeyCreateSignature");
    }
    if (!host) {
        return errSecUnimplemented;
    }
    CFErrorRef error = NULL;
    SecKeyAlgorithm algorithm = CharonShimDigestAlgorithm();
    CFDataRef digest = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
    CFDataRef made = host(key, algorithm, digest, &error);
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
    typedef Boolean (*CharonShimVerifySignature)(SecKeyRef, SecKeyAlgorithm, CFDataRef, CFDataRef, CFErrorRef *);
    static CharonShimVerifySignature host = NULL;
    if (!host) {
        host = (CharonShimVerifySignature)dlsym(RTLD_DEFAULT, "SecKeyVerifySignature");
    }
    if (!host) {
        return errSecUnimplemented;
    }
    SecKeyAlgorithm algorithm = CharonShimDigestAlgorithm();
    CFDataRef digest = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
    // The release's SecKeyRawVerify takes the two halves of an elliptic signature where the host's
    // SecKeyVerifySignature takes their DER, so 64 bytes are put back into the SEQUENCE of two
    // INTEGERs here - the same shape the port's own signing reads and writes, which is what makes
    // this shim the release and not a convenience.
    uint8_t der[72];
    const uint8_t *given = signature;
    size_t givenLength = signatureLength;
    if (signatureLength == 64) {
        size_t offset = 0;
        der[offset++] = 0x30;
        der[offset++] = 0;
        size_t content = offset;
        for (int half = 0; half < 2; half++) {
            const uint8_t *value = signature + half * 32;
            int first = 0;
            while (first < 31 && value[first] == 0) {
                first++;
            }
            int size = 32 - first;
            if (value[first] & 0x80) {
                der[offset++] = 0x02;
                der[offset++] = (uint8_t)(size + 1);
                der[offset++] = 0x00;
            } else {
                der[offset++] = 0x02;
                der[offset++] = (uint8_t)size;
            }
            memcpy(der + offset, value + first, (size_t)size);
            offset += (size_t)size;
        }
        der[1] = (uint8_t)(offset - content);
        given = der;
        givenLength = offset;
    }
    CFDataRef made = CFDataCreate(kCFAllocatorDefault, given, (CFIndex)givenLength);
    CFErrorRef error = NULL;
    BOOL valid = host(key, algorithm, digest, made, &error);
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

static OSStatus SecKeyRawSign(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                              uint8_t *signature, size_t *signatureLength)
{
    (void)padding;
    return CharonShimRawSign(key, bytes, length, signature, signatureLength);
}

static OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding, const uint8_t *bytes, size_t length,
                                const uint8_t *signature, size_t signatureLength)
{
    (void)padding;
    return CharonShimRawVerify(key, bytes, length, signature, signatureLength);
}

static CFIndex SecKeyGetAlgorithmID(SecKeyRef key)
{
    (void)key;
    return 0;
}

static CFDictionaryRef SecKeyCopyAttributeDictionary(SecKeyRef key)
{
    // The host's own attributes for every key, so nothing the port reads of them changes: a key of the
    // release's keychain is a key of the release's keychain here, and it takes the release's path.
    CFDictionaryRef hostAttributes = SecKeyCopyAttributes(key);
    if (key != CharonShimPortKey && key != CharonShimPortPublicKey) {
        return hostAttributes;
    }
    // A key of the port's own kind, which is one that holds its own scalar: the marker the port reads
    // is added, and beside it the 32 bytes of kSecValueData that SecKeyCreateWithData would have left,
    // because the port's sign and exchange paths read the scalar from there and nowhere else. A public
    // key gets the marker and no scalar - the port's verify path asks it only for the point, which
    // SecKeyCopyPublicBytes below answers from the host's own key.
    CFMutableDictionaryRef attributes = hostAttributes
        ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, hostAttributes)
        : CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                    &kCFTypeDictionaryValueCallBacks);
    if (!attributes) {
        if (hostAttributes) {
            CFRelease(hostAttributes);
        }
        return NULL;
    }
    CFDictionarySetValue(attributes, CFSTR(CHARON_SHIM_SECKEY_MARKER), kCFBooleanTrue);
    if (key == CharonShimPortKey && CharonShimPortScalarLength == sizeof CharonShimPortScalar) {
        CFDataRef scalar = CFDataCreate(kCFAllocatorDefault, CharonShimPortScalar, (CFIndex)CharonShimPortScalarLength);
        if (scalar) {
            CFDictionarySetValue(attributes, kSecValueData, scalar);
            CFRelease(scalar);
        }
    }
    if (hostAttributes) {
        CFRelease(hostAttributes);
    }
    return attributes;
}

static OSStatus SecKeyCopyPublicBytes(SecKeyRef key, CFDataRef *serialized)
{
    CFDataRef bytes = CharonShimPublicBytes(key);
    if (!bytes) {
        return errSecInternalError;
    }
    *serialized = bytes;
    return errSecSuccess;
}

static SecKeyRef SecKeyCreateFromPublicData(CFAllocatorRef allocator, CFIndex algorithmID, CFDataRef serialized)
{
    (void)algorithmID;
    (void)serialized;
    return NULL;
}

#endif
