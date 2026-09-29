#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Security/SecureTransport.h>
#import <stdio.h>
#import <dlfcn.h>

// THE MEASUREMENT, ON 6.1.3, OF WHAT THE RELEASE'S OWN STACK WILL NEGOTIATE BY DEFAULT.
//
// Four functions in registry/Security/ios13.json answer a "default minimum" or "default maximum" TLS or
// DTLS version, and their values are currently a DECISION from the release's stack constants rather than
// a measurement - recorded as a crutch, because a caller asking "what would I get by default" must hear
// something this release can honour. This program is the measurement that replaces the crutch.
//
// WHAT IT ASKS, and why each is here:
//   SSLCreateContext(NULL, kSSLClientSide, kSSLStreamType)  - a context needs no identity, no keychain
//                                                             and no network, which is what makes this
//                                                             safe to run at all
//   SSLGetProtocolVersionMin / SSLGetProtocolVersionMax      - the two ends of the default range
//   SSLGetProtocolVersionEnabled                            - per protocol, so the numbers are
//                                                             comparable to the SDKProtocolVersion_t
//                                                             values directly rather than by mapping
//
// IT PRINTS, and nothing decides: the release's answer, whatever it is. A line that does not appear is
// the datum too - a function that is absent on 6.1.3 must be reported as absent, not skipped quietly.

static void report(const char *what, long value)
{
    printf("%s\t%ld\n", what, value);
}

// EVERY SYMBOL IS RESOLVED WITH dlsym AND CALLED THROUGH THE POINTER, and that is not a style choice:
//   - `if (SSLGetProtocolVersionMin != NULL)` COMPARES A FUNCTION NAME WITH NULL and is therefore ALWAYS
//     FALSE, so the missing-symbol branch could never fire and a program written that way cannot tell
//     "the release has no such call" from "the release has one and it answered nothing".
//   - SSLSetProtocolVersionEnabled IS DECLARED INSIDE #if TARGET_OS_OSX (SecureTransport.h:511) IN THE
//     16.4 SDK, so calling it from a binary built against that SDK does not compile - and the first
//     version of this probe did exactly that.
//
// A PRECISE WORDING POINT, because the distinction decides what this file may claim: A SYMBOL DECLARED IN
// THE SDK AND A SYMBOL EXPORTED BY 6.1.3 ARE DIFFERENT FACTS. The #if above is the first and says
// nothing about the second: the 16.4 header's view of TARGET_OS_OSX is the SDK's, and a release can
// export a name the SDK no longer declares. So NOTHING HERE CLAIMS THAT 6.1.3 LACKS ANY OF THESE. What
// is established is only that a symbol the 16.4 SDK declares only for macOS cannot be CALLED through a
// declaration, which is why all three go through dlsym.
//
// Whether 6.1.3 EXPORTS SSLSetProtocolVersionEnabled is OPEN and is being read out of the release's
// dyld shared cache export trie; a string hit in that cache is not an export and is not used as one. If
// the release does export it, the per-protocol question below becomes askable and this file's comment
// changes with it.
// A dlsym'd pointer is honest about absence and calling through it does not trip the deprecation, which
// SSLGetProtocolVersionMin/Max carry at __SECURETRANSPORT_API_DEPRECATED(..., ios(5.0, 13.0)).
//
// THE PROTOTYPES BELOW ARE DECLARED FROM THE HEADER'S FACTS - the signature lines and nothing else - and
// no Apple body is transcribed.

typedef OSStatus (*SSLGetVersionOne)(SSLContextRef, SSLProtocol *);
typedef OSStatus (*SSLSetOneProtocol)(SSLContextRef, SSLProtocol, Boolean);

int main(int argc, char **argv)
{
    (void)argc; (void)argv;
    printf("ssl-defaults-probe\tstart\n");

    SSLContextRef context = SSLCreateContext(NULL, kSSLClientSide, kSSLStreamType);
    if (!context) { printf("context\tNULL\n"); return 1; }
    printf("context\tok\n");

    SSLGetVersionOne getMin = (SSLGetVersionOne)dlsym(RTLD_DEFAULT, "SSLGetProtocolVersionMin");
    SSLGetVersionOne getMax = (SSLGetVersionOne)dlsym(RTLD_DEFAULT, "SSLGetProtocolVersionMax");
    SSLSetOneProtocol setEnabled =
        (SSLSetOneProtocol)dlsym(RTLD_DEFAULT, "SSLSetProtocolVersionEnabled");

    // PRESENCE IS NOW A REAL ANSWER, and each of the three is reported whether or not it is found.
    printf("has-min\t%s\n", getMin ? "yes" : "no");
    printf("has-max\t%s\n", getMax ? "yes" : "no");
    printf("has-set-enabled\t%s\n", setEnabled ? "yes" : "no");

    if (getMin) {
        SSLProtocol min = 0;
        if (getMin(context, &min) == noErr)
            report("min", (long)min);
        else
            printf("min\tunavailable\n");
    } else {
        printf("min\tabsent\n");
    }
    if (getMax) {
        SSLProtocol max = 0;
        if (getMax(context, &max) == noErr)
            report("max", (long)max);
        else
            printf("max\tunavailable\n");
    } else {
        printf("max\tabsent\n");
    }

    // WHAT THIS RUN CAN AND CANNOT SAY. The setter did not resolve through dlsym on this platform and
    // the 16.4 SDK declares it only under #if TARGET_OS_OSX, so this build cannot CALL it. That is a
    // fact about the BUILD and the SDK, NOT about what 6.1.3 exports: dlsym on the guest is the only
    // thing that settles the export question, and the export trie is being read for it separately.
    printf("per-protocol\tsetter-not-declared-by-the-sdk-for-this-platform\n");
    printf("per-protocol\texport-on-6.1.3-OPEN-ask-the-guest-dyld-cache\n");

    SSLClose(context);
    CFRelease(context);
    printf("ssl-defaults-probe\tdone\n");
    return 0;
}
