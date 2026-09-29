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
//   - SSLSetProtocolVersionEnabled IS INSIDE #if TARGET_OS_OSX (SecureTransport.h:511), so it has NEVER
//     been on iOS. Calling it from an iOS binary does not compile, and the first version of this probe
//     did exactly that.
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

    // THE PER-PROTOCOL QUESTION CANNOT BE ASKED ON iOS. SSLSetProtocolVersionEnabled is macOS-only
    // (#if TARGET_OS_OSX at SecureTransport.h:511), so there is no setter to enable a protocol with and no
    // getter to read one back - the release offers NEITHER half of the pair, and that is the finding.
    printf("per-protocol\tno-setter-and-no-getter-on-ios\n");

    SSLClose(context);
    CFRelease(context);
    printf("ssl-defaults-probe\tdone\n");
    return 0;
}
