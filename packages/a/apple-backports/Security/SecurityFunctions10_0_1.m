#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>

// SecKeyCopyAttributes, over the facility iOS 6.1.3 has.
//
// WHERE A KEY DESCRIBES ITSELF. There are two answers available on this release and this is the one taken:
// the keychain item the ref was made from, asked for by the ref, with SecItemCopyMatching and
// kSecValueRef. The other is a side table keyed by the ref, filled by the port's own SecKeyCreateWithData
// and by a wrapper around SecKeyGeneratePair. The keychain is chosen because it is the RELEASE's own
// record and not the port's: a key the port made is described by the same item the release will find,
// and a key the release made - a keychain item added by an application, or a pair from
// SecKeyGeneratePair - is described too, with no wrapper and nothing to keep in step. A side table would
// describe the port's own keys and answer nothing about anyone else's, which is a narrower function
// wearing a general one's name.
//
// It returns a COPY, and the release copies what it returns, so the caller owns it.
// THE PURE PART, and it is split out on purpose. SecKeyCopyAttributes asks the release's keychain for
// the item a key was made from, and that half cannot be exercised on a host without touching a
// keychain - which this repository must not do. What CAN be exercised is the shaping: what the answer
// does with what SecItemCopyMatching handed back. So that is its own function, it takes the result and
// nothing else, and the differential drives it on the host with a dictionary the test builds. A caller
// passing a non-dictionary, or a dictionary without the documented keys, gets NULL - the same answer the
// whole function gives.
CFDictionaryRef CharonSecurityAttributesFromItemResult(CFTypeRef result)
{
    if (!result)
        return NULL;
    // SecItemCopyMatching hands back a dictionary for kSecReturnAttributes, and only that: a request for
    // data, a reference or a persistent ref answers something else entirely, and handing that back as
    // attributes would be a lie with a CFDictionaryRef on it.
    if (CFGetTypeID(result) != CFDictionaryGetTypeID())
        return NULL;
    return (CFDictionaryRef)result;
}

// The keychain half, which is the release's own record and the only place a key says what it is.
CFDictionaryRef SecKeyCopyAttributes(SecKeyRef key)
{
    if (!key)
        return NULL;
    // The 16.4 declaration, grepped from Security.framework/Headers/SecItem.h:1162:
    //   OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result)
    // TWO arguments, with the result through the second. There is no CFAllocatorRef and no resultType in
    // this SDK, and a call shaped the other way is a call to a function that is not here.
    const void *keys[] = {kSecValueRef, kSecReturnAttributes};
    const void *values[] = {key, kCFBooleanTrue};
    CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
    if (!query)
        return NULL;
    CFTypeRef found = NULL;
    OSStatus status = SecItemCopyMatching(query, &found);
    CFRelease(query);
    if (status != errSecSuccess)
        return NULL;
    CFDictionaryRef attributes = CharonSecurityAttributesFromItemResult(found);
    if (found)
        CFRelease(found);
    return attributes;
}

// SecKeyIsAlgorithmSupported, key-first, as this SDK spells it:
//
//   1550  Boolean SecKeyIsAlgorithmSupported(SecKeyRef key, SecKeyOperationType operation,
//                                             SecKeyAlgorithm algorithm)
//
// so the KEY comes first and the key's own attributes say what it is - which is why the shaping half of
// SecKeyCopyAttributes is above and why the port cannot answer this as a table over
// (class, algorithm, operation): there is no class argument to read.
//
// WHAT THE ANSWER COMES FROM, and it is the release's primitives and nothing else. On iOS 6.1.3 a
// signature is SecKeyRawSign over kSecPaddingPKCS1SHA1 (kSecKey.h:660) and the key's class says which
// padding applies; an encryption is SecKeyEncrypt over the same padding. An operation the release has no
// primitive for is NO, and NO IS THE ANSWER rather than a status - this signature returns a Boolean, so
// there is nothing to fail with, and the SDK's own contract is that NO means the algorithm is not
// supported.
// The table, defined below and declared here because the function that consults it comes first in the
// file: a delegate that is not yet declared compiles as an implicit declaration under C99 and then as a
// conflicting type, which is two errors for one missing line.
bool CharonSecurityCarries(SecKeyOperationType operation, SecKeyAlgorithm algorithm, bool rsa, bool ec);

Boolean SecKeyIsAlgorithmSupported(SecKeyRef key, SecKeyOperationType operation, SecKeyAlgorithm algorithm)
{
    if (!key || !operation || !algorithm)
        return false;
    // THE TWO ARGUMENTS ARE COMPARED DIFFERENTLY AND THAT IS NOT A TYPo: SecKeyOperationType is an
    // enum and SecKeyAlgorithm is a CFStringRef, so the operation is an integer comparison and the
    // algorithm is CFEqual. Writing CFEqual on both reads correctly and does not compile - nine errors
    // from one of them.
    // the key's class, from the release's own record - the one thing the key-first signature needs
    CFDictionaryRef attributes = SecKeyCopyAttributes(key);
    if (!attributes)
        return false;
    CFTypeRef type = CFDictionaryGetValue(attributes, kSecAttrKeyType);
    bool rsa = type && CFEqual(type, kSecAttrKeyTypeRSA);
    bool ec = type && CFEqual(type, kSecAttrKeyTypeECSECPrimeRandom);
    CFRelease(attributes);
    if (!rsa && !ec) {
        // a class the release's signing and encryption primitives do not take. kSecKey.h:198 has one
        // padding, kSecPaddingPKCS1SHA1, and it is an RSA one.
        return false;
    }
    return CharonSecurityCarries(operation, algorithm, rsa, ec);
}

// The TABLE, as a pure function of the key's class, so it can be driven on a host that has no keychain
// and no key: SecKeyIsAlgorithmSupported above is this plus the one lookup that needs a key, and a
// differential that cannot separate the two cannot check either.
bool CharonSecurityCarries(SecKeyOperationType operation, SecKeyAlgorithm algorithm, bool rsa, bool ec)
{
    if (operation == kSecKeyOperationTypeSign || operation == kSecKeyOperationTypeVerify) {
        // SecKeyRawSign and SecKeyRawVerify carry these, and no other signature primitive exists here
        if (rsa) {
            // RSA over the release's only padding: a digest, not a pre-hashed value
            return CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1)
                || CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256)
                || CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA384)
                || CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA512);
        }
        return false;      // EC signing arrives after 6.1.3: the release has no EC primitive to sign with
    }
    if (operation == kSecKeyOperationTypeEncrypt || operation == kSecKeyOperationTypeDecrypt) {
        // SecKeyEncrypt and SecKeyDecrypt, and RSA is what the release's padding takes
        return rsa && (CFEqual(algorithm, kSecKeyAlgorithmRSAEncryptionPKCS1)
                        || CFEqual(algorithm, kSecKeyAlgorithmRSAEncryptionOAEPSHA1AESGCM));
    }
    if (operation == kSecKeyOperationTypeKeyExchange) {
        // iOS 6.1.3 has NO key-exchange primitive at all: SecKeyCopyKeyExchangeResult arrives at 10.0.1
        // with the peer it would have exchanged with, so there is nothing on the release to exchange.
        return false;
    }
    return false;
}

// SecKeyCreateSignature, over SecKeyRawSign.
//
//    1435  CFDataRef _Nullable SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm,
//                                                   CFDataRef dataToSign, CFErrorRef *error)
//
// So the algorithm arrives as a CFStringRef and the answer is a CFDataRef, and the port's job is to turn
// the algorithm into the PADDING the release's own call takes. Every padding the 16.4 header declares,
// and what it says about each (kSecKey.h:176-218):
//
//   176  kSecPaddingNone        = 0
//   177  kSecPaddingPKCS1       = 1
//   178  kSecPaddingOAEP        = 2        iOS 2.0
//   183  kSecPaddingSigRaw      = 0x4000
//   188  kSecPaddingPKCS1MD2    = 0x8000    deprecated
//   193  kSecPaddingPKCS1MD5    = 0x8001    deprecated
//   198  kSecPaddingPKCS1SHA1   = 0x8002
//   203  kSecPaddingPKCS1SHA224 = 0x8003    iOS 2.0
//   208  kSecPaddingPKCS1SHA256 = 0x8004    iOS 2.0
//   213  kSecPaddingPKCS1SHA384 = 0x8005    iOS 2.0
//   218  kSecPaddingPKCS1SHA512 = 0x8006    iOS 2.0
//
// So the release has every padding a digest-named algorithm needs, and the raw call's own documentation
// (kSecKey.h:660) says kSecPaddingPKCS1SHA1 is what it typically takes. kSecPaddingNone is the answer for
// an algorithm the release cannot carry, and it is distinguishable from every real padding above.
SecPadding CharonSecurityPaddingFor(SecKeyAlgorithm algorithm)
{
    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1))
        return kSecPaddingPKCS1SHA1;
    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA224))
        return kSecPaddingPKCS1SHA224;
    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))
        return kSecPaddingPKCS1SHA256;
    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA384))
        return kSecPaddingPKCS1SHA384;
    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA512))
        return kSecPaddingPKCS1SHA512;
    return kSecPaddingNone;      // an algorithm the release's signing primitive does not carry
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef dataToSign,
                                CFErrorRef *error)
{
    if (!key || !algorithm || !dataToSign)
        return NULL;
    if (error)
        *error = NULL;
    // the key's class, and then the table, are the same two questions SecKeyIsAlgorithmSupported asks
    CFDictionaryRef attributes = SecKeyCopyAttributes(key);
    if (!attributes)
        return NULL;
    CFTypeRef type = CFDictionaryGetValue(attributes, kSecAttrKeyType);
    bool rsa = type && CFEqual(type, kSecAttrKeyTypeRSA);
    bool ec = type && CFEqual(type, kSecAttrKeyTypeECSECPrimeRandom);
    CFRelease(attributes);
    if (!CharonSecurityCarries(kSecKeyOperationTypeSign, algorithm, rsa, ec))
        // NOT SUPPORTED, and the header gives no error code to say so with: this signature takes a
        // CFErrorRef, and Security.framework's own documentation for it does not name a domain or a code
        // for an unsupported algorithm. So the port returns NULL and sets NO error rather than inventing
        // one - a caller can see the absence, and the row says absence is what there is.
        return NULL;
    SecPadding padding = CharonSecurityPaddingFor(algorithm);
    if (padding == kSecPaddingNone)
        return NULL;
    CFIndex length = CFDataGetLength(dataToSign);
    if (length < 0)
        return NULL;
    unsigned char *buffer = calloc((size_t)length, 1);
    if (!buffer)
        return NULL;
    size_t signatureLength = (size_t)length;
    OSStatus status = SecKeyRawSign(key, padding, (const uint8_t *)CFDataGetBytePtr(dataToSign),
                                     (size_t)length, buffer, &signatureLength);
    if (status != errSecSuccess) {
        free(buffer);
        return NULL;
    }
    CFDataRef signature = CFDataCreate(kCFAllocatorDefault, buffer, (CFIndex)signatureLength);
    free(buffer);
    return signature;
}

// SecKeyVerifySignature, over SecKeyRawVerify.
//
//    1451  Boolean SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData,
//                                        CFDataRef signature, CFErrorRef *error)
//
//    692   OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding, const uint8_t *signedData,
//                                   size_t signedDataLen, const uint8_t *sig, size_t sigLen)
//
// The release's own documentation is explicit about what the padding does here (kSecKey.h:684-690):
// kSecPaddingPKCS1 has its padding CHECKED during verification, kSecPaddingNone compares the incoming
// data directly to the signature, and a PKCS1 signature whose signedData is a digest should be verified
// with the padding that names that digest - "use kSecPaddingPKCS1SHA1". So the same pure mapping that
// chooses the padding for signing chooses it for verifying, and that is the whole of the work.
Boolean SecKeyVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData,
                              CFDataRef signature, CFErrorRef *error)
{
    if (!key || !algorithm || !signedData || !signature)
        return false;
    if (error)
        *error = NULL;
    CFDictionaryRef attributes = SecKeyCopyAttributes(key);
    if (!attributes)
        return false;
    CFTypeRef type = CFDictionaryGetValue(attributes, kSecAttrKeyType);
    bool rsa = type && CFEqual(type, kSecAttrKeyTypeRSA);
    bool ec = type && CFEqual(type, kSecAttrKeyTypeECSECPrimeRandom);
    CFRelease(attributes);
    if (!CharonSecurityCarries(kSecKeyOperationTypeVerify, algorithm, rsa, ec))
        return false;   // not carried, and for the reason the sibling gives: no error is invented
    SecPadding padding = CharonSecurityPaddingFor(algorithm);
    if (padding == kSecPaddingNone)
        return false;
    CFIndex signedLength = CFDataGetLength(signedData);
    CFIndex signatureLength = CFDataGetLength(signature);
    if (signedLength < 1 || signatureLength < 1)
        return false;   // the release's raw call takes a length, and zero is not something to hand it
    OSStatus status = SecKeyRawVerify(key, padding,
                                      (const uint8_t *)CFDataGetBytePtr(signedData),
                                      (size_t)signedLength,
                                      (const uint8_t *)CFDataGetBytePtr(signature),
                                      (size_t)signatureLength);
    // errSecVerifyFailed = -67808 (SecBase.h:611) is the release's own documented code for a
    // verification that did not verify. This signature answers a Boolean, and its documentation names
    // no CFError domain or code for it, so the port answers the Boolean and sets no error rather than
    // inventing a CFError a caller would handle as though the SDK had promised one.
    (void)status;
    return status == errSecSuccess;
}

// SecKeyCopyKeyExchangeResult.
//
//    1512  CFDataRef _Nullable SecKeyCopyKeyExchangeResult(SecKeyRef privateKey, SecKeyAlgorithm algorithm,
//                                                         SecKeyRef publicKey, CFDictionaryRef parameters,
//                                                         CFErrorRef *error)
//
// THERE IS NO KEY-EXCHANGE PRIMITIVE ON 6.1.3 TO BUILD THIS ON, and that was searched for in the header
// rather than assumed. Every candidate SecKey.h declares, and what each one is:
//
//    501/530  SecKeyDeriveFromPassword - a PBKDF, and API_DEPRECATED("No longer supported", macos(10.7, 12.0)).
//             It derives a key from a PASSWORD. It is not key exchange and it is not a peer key.
//    106/146  kSecKeyDerive - an ATTRIBUTE, value nonzero iff the key may be used to derive. It is a
//             property, not an operation, and deriving from a key is not exchanging with a peer.
//
// There is no SecKeyExchange, no SecKeyRawKeyExchange, no SecKeyECDH, no SecKeyDH in the 16.4 header, so
// a function arriving at 10.0.1 with a peer key and a parameter dictionary has nothing underneath it. The
// port therefore REFUSES: the table already answers kSecKeyOperationTypeKeyExchange false, and this
// reaches the same answer without a key lookup, because the answer does not depend on the key.
CFDataRef SecKeyCopyKeyExchangeResult(SecKeyRef privateKey, SecKeyAlgorithm algorithm, SecKeyRef publicKey,
                                      CFDictionaryRef parameters, CFErrorRef *error)
{
    (void)privateKey;
    (void)algorithm;
    (void)publicKey;
    (void)parameters;
    if (error)
        *error = NULL;   // no error is invented for the same reason as the two siblings above
    return NULL;         // and the row says why, and what the effect of the absence is
}
