#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Security/SecureTransport.h>
#import <stdio.h>

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

int main(int argc, char **argv)
{
    (void)argc; (void)argv;
    // one line first, so a run that produces nothing else is still a report rather than silence
    printf("ssl-defaults-probe\tstart\n");

    SSLContextRef context = SSLCreateContext(NULL, kSSLClientSide, kSSLStreamType);
    if (!context) {
        printf("context\tNULL\n");
        return 1;
    }
    printf("context\tok\n");

    // the two ends of the range. Either may be absent on this release, and that is a result.
    if (SSLGetProtocolVersionMin != NULL) {
        SSLProtocol min = 0;
        if (SSLGetProtocolVersionMin(context, &min) == noErr)
            report("min", (long)min);
        else
            printf("min\tunavailable\n");
    } else {
        printf("min\tabsent\n");
    }
    if (SSLGetProtocolVersionMax != NULL) {
        SSLProtocol max = 0;
        if (SSLGetProtocolVersionMax(context, &max) == noErr)
            report("max", (long)max);
        else
            printf("max\tunavailable\n");
    } else {
        printf("max\tabsent\n");
    }

    // Per protocol, by the SDK's own enumerators. kTLSProtocol13 is asked on purpose: the 16.4 SDK
    // declares it, and whether 6.1.3 enables it is the open question the four rows turn on.
    struct { const char *name; SSLProtocol protocol; } asked[] = {
        { "enabled-ssl3",  kSSLProtocol3  },
        { "enabled-tls1",  kTLSProtocol1  },
        { "enabled-tls11", kTLSProtocol11 },
        { "enabled-tls12", kTLSProtocol12 },
        { "enabled-tls13", kTLSProtocol13 },
        { "enabled-dtls1", kDTLSProtocol1 },
    };
    for (unsigned i = 0; i < sizeof asked / sizeof asked[0]; i++) {
        if (SSLGetProtocolVersionEnabled == NULL) {
            printf("%s\tabsent\n", asked[i].name);
            continue;
        }
        Boolean on = false;
        if (SSLGetProtocolVersionEnabled(context, asked[i].protocol, &on) == noErr)
            report(asked[i].name, on ? 1 : 0);
        else
            printf("%s\tunavailable\n", asked[i].name);
    }

    SSLClose(context);
    CFRelease(context);
    printf("ssl-defaults-probe\tdone\n");
    return 0;
}
