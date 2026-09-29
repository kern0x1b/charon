#import <Foundation/Foundation.h>
#import <Security/SecCertificate.h>
#import <Security/SecTrust.h>
#import <Security/SecPolicy.h>
#import <Security/SecProtocolTypes.h>
#import <CoreFoundation/CoreFoundation.h>

// The sec_certificate_t and sec_trust_t wrappers, and the first slice of the nine owed rows.
//
// THE TYPES ARE DECLARED, NOT FILLED IN. SecProtocolTypes.h:41-43 declares the three with
// SEC_OBJECT_DECL, and as the preprocessor emits it the type is a POINTER TO A PROTOCOL:
//
//     @protocol OS_sec_certificate <NSObject> @end
//     typedef NSObject<OS_sec_certificate> * __attribute__((objc_independent_class)) sec_certificate_t;
//
// so there is no sec_certificate class to add a method to and no ivar to add to one: the port supplies
// the OBJECT under its own name, implementing the protocol, and implements the functions the header
// declares. A first attempt declared @interface sec_certificate and the nine prototypes, and that is
// a second declaration of things the header already declares rather than an implementation of them.
//
// A SecCertificateRef AND A SecTrustRef BOTH EXIST ON 6.1.3 and BOTH ARE MADE WITHOUT A KEYCHAIN:
// SecCertificateCreateWithData builds one from DER, and SecTrustCreateWithCertificates builds one from a
// certificate and a policy. So these four are REAL WRAPPERS OF REAL REFS, not answers that report an
// absence, and what is being tested is the wrapper's own ownership.
//
// THE STATE IS THE OBJECT'S OWN: the CFTypeRef is a strong ivar, so ARC retains at init and releases at
// dealloc, and a copy_ref hands back +1 over the ref the object holds. A copy that did not retain would
// leave the caller with a ref the object may still be the only owner of.

@interface CharonSecCertificate : NSObject <OS_sec_certificate>
{
    SecCertificateRef _certificate;
}
- (instancetype)initWithCertificate:(SecCertificateRef)certificate;
- (SecCertificateRef)charonCertificate;
@end

@implementation CharonSecCertificate
- (instancetype)initWithCertificate:(SecCertificateRef)certificate
{
    self = [super init];
    if (self)
        _certificate = certificate ? (SecCertificateRef)CFRetain(certificate) : NULL;
    return self;
}
- (SecCertificateRef)charonCertificate { return _certificate; }
- (void)dealloc { if (_certificate) CFRelease(_certificate); }
@end

@interface CharonSecTrust : NSObject <OS_sec_trust>
{
    SecTrustRef _trust;
}
- (instancetype)initWithTrust:(SecTrustRef)trust;
- (SecTrustRef)charonTrust;
@end

@implementation CharonSecTrust
- (instancetype)initWithTrust:(SecTrustRef)trust
{
    self = [super init];
    if (self)
        _trust = trust ? (SecTrustRef)CFRetain(trust) : NULL;
    return self;
}
- (SecTrustRef)charonTrust { return _trust; }
- (void)dealloc { if (_trust) CFRelease(_trust); }
@end

//    303  sec_certificate_t sec_certificate_create(SecCertificateRef certificate)
//
// THE COMPILER SAYS THE RESULT IS NON-NULL AND THE HEADER LINE SAYS NOTHING ABOUT NULLABILITY:
//   "null returned from function that requires a non-null return value [-Wnonnull]" at this file's line
//   86, which is the `return NULL` INSIDE sec_certificate_copy_ref - not in this creator. The creator
//   is declared as sec_certificate_create(SecCertificateRef certificate) and the two -Wnonnull warnings
//   in this file are both in the two copy_ref functions, at their own `return NULL` for an object that
//   holds nothing. So the wrapper is ALWAYS created, holding the ref it was given, and a caller that
//   passed NULL finds out at copy_ref, which answers NULL - the annotation is on the getter, and the
//   getter has nothing to return for an object that was never given a ref.
//
// A claim here that the header "says these never return NULL" was wrong: -Wnonnull is the compiler's
// inference from the nullability annotations on the copy_ref declarations, and reading it as a property
// of the creators sent me looking at the wrong two functions.
sec_certificate_t sec_certificate_create(SecCertificateRef certificate)
{
    return (sec_certificate_t)[[CharonSecCertificate alloc] initWithCertificate:certificate];
}

//    318  SecCertificateRef sec_certificate_copy_ref(sec_certificate_t certificate)
SecCertificateRef sec_certificate_copy_ref(sec_certificate_t certificate)
{
    if (![certificate isKindOfClass:CharonSecCertificate.class])
        return NULL;
    SecCertificateRef held = [(CharonSecCertificate *)certificate charonCertificate];
    return held ? (SecCertificateRef)CFRetain(held) : NULL;
}

//    188  sec_trust_t sec_trust_create(SecTrustRef trust)
//  Always returns a wrapper, for the reason given above: the -Wnonnull warnings in this file are in the
//  two copy_ref functions, not in these creators.
sec_trust_t sec_trust_create(SecTrustRef trust)
{
    return (sec_trust_t)[[CharonSecTrust alloc] initWithTrust:trust];
}

//    203  SecTrustRef sec_trust_copy_ref(sec_trust_t trust)
SecTrustRef sec_trust_copy_ref(sec_trust_t trust)
{
    if (![trust isKindOfClass:CharonSecTrust.class])
        return NULL;
    SecTrustRef held = [(CharonSecTrust *)trust charonTrust];
    return held ? (SecTrustRef)CFRetain(held) : NULL;
}
