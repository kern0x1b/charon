#import <Foundation/Foundation.h>
#import <Security/SecProtocolTypes.h>
#import <Security/SecProtocolOptions.h>
#import <CoreFoundation/CoreFoundation.h>

// The sec_protocol_options family, from Security/SecProtocolOptions.h. This file carries the five
// functions whose answer is a FACT rather than a setting: the four defaults and the comparator.
//
// THE OBJECT IS THE PORT'S OWN, as clang -E emits the type:
//
//     @protocol OS_sec_protocol_options <NSObject> @end
//     typedef NSObject<OS_sec_protocol_options> * __attribute__((objc_independent_class))
//         sec_protocol_options_t;
//
// and its state is the SETTINGS a caller put on it. Nothing in 6.1.3 ever reads that state: this API's
// stack does not exist on the release, which negotiates through SecureTransport. So every setter here is
// inert - callable, holding, with the effect stated as "the handshake ignores it" - while a GETTER that
// reads back what was put is implemented, because that is the one thing the port can answer truthfully.

@interface CharonSecProtocolOptions : NSObject <OS_sec_protocol_options>
{
    tls_protocol_version_t _minTLS, _maxTLS, _minDTLS, _maxDTLS;
    BOOL _hasMinTLS, _hasMaxTLS;
}
- (void)charonSetMinTLS:(tls_protocol_version_t)version;
- (void)charonSetMaxTLS:(tls_protocol_version_t)version;
- (tls_protocol_version_t)charonMinTLS;
- (tls_protocol_version_t)charonMaxTLS;
- (BOOL)charonHasVersionSettings;
@end

@implementation CharonSecProtocolOptions
- (void)charonSetMinTLS:(tls_protocol_version_t)version { _minTLS = version; _hasMinTLS = YES; }
- (void)charonSetMaxTLS:(tls_protocol_version_t)version { _maxTLS = version; _hasMaxTLS = YES; }
- (tls_protocol_version_t)charonMinTLS { return _minTLS; }
- (tls_protocol_version_t)charonMaxTLS { return _maxTLS; }
- (BOOL)charonHasVersionSettings { return _hasMinTLS && _hasMaxTLS; }
@end

// THE FOUR DEFAULTS. The @return above each of them in the header reads "The default minimum TLS
// version", "The default maximum DTLS version" and so on - it NAMES THE QUANTITY and does not state a
// number, so the value is not the header's to read. A caller asking "what would I get by default" must
// hear something 6.1.3 can HONOUR, and the rule applied is: the release's own stack's range.
//
//     tls_protocol_version_TLSv10  = 0x0301     tls_protocol_version_TLSv12  = 0x0303
//     tls_protocol_version_TLSv13  = 0x0304     tls_protocol_version_DTLSv10 = 0xfeff
//     tls_protocol_version_DTLSv12 = 0xfefd
//
// min TLS 0x0301 (TLSv10), max TLS 0x0303 (TLSv12), min DTLS 0xfeff, max DTLS 0xfeff - the release's
// stack has kTLSProtocol12 as its top and DTLS 1.0 only.
//
// NOT MEASURED ON 6.1.3. These four numbers are a decision from the release's stack constants, and a
// guest measurement - SSLCreateContext then SSLGetProtocolVersionMin/Max on a fresh context, which needs
// no identity - would replace them. Until that runs they are recorded as a crutch, and the row says so.

//    211  tls_protocol_version_t sec_protocol_options_get_default_min_tls_protocol_version(void);
tls_protocol_version_t sec_protocol_options_get_default_min_tls_protocol_version(void)
{
    return tls_protocol_version_TLSv10;
}

//    223  tls_protocol_version_t sec_protocol_options_get_default_min_dtls_protocol_version(void);
tls_protocol_version_t sec_protocol_options_get_default_min_dtls_protocol_version(void)
{
    return tls_protocol_version_DTLSv10;
}

//    268  tls_protocol_version_t sec_protocol_options_get_default_max_tls_protocol_version(void);
tls_protocol_version_t sec_protocol_options_get_default_max_tls_protocol_version(void)
{
    return tls_protocol_version_TLSv12;   // TLSv13 is NEVER returned: 6.1.3 cannot negotiate it
}

//    280  tls_protocol_version_t sec_protocol_options_get_default_max_dtls_protocol_version(void);
tls_protocol_version_t sec_protocol_options_get_default_max_dtls_protocol_version(void)
{
    return tls_protocol_version_DTLSv10;  // DTLSv12 is NEVER returned: the release has DTLS 1.0 only
}

//    86   bool sec_protocol_options_are_equal(sec_protocol_options_t optionsA,
//                                              sec_protocol_options_t optionsB)
//
// THE COMPARATOR IS A REAL ANSWER rather than a setting nobody reads: it compares the settings the port
// HOLDS, and a caller that set two option objects to the same values must be told they are equal. It is
// implemented, and the equality is the port's own state and nothing else - a comparison against the
// release's stack would be a comparison of nothing, because there is no such stack.
bool sec_protocol_options_are_equal(sec_protocol_options_t optionsA, sec_protocol_options_t optionsB)
{
    if (optionsA == optionsB)
        return true;                        // the same object is trivially equal to itself
    if (!optionsA || !optionsB)
        return false;
    if (![optionsA conformsToProtocol:@protocol(OS_sec_protocol_options)]
        || ![optionsB conformsToProtocol:@protocol(OS_sec_protocol_options)])
        return false;
    CharonSecProtocolOptions *a = (CharonSecProtocolOptions *)optionsA;
    CharonSecProtocolOptions *b = (CharonSecProtocolOptions *)optionsB;
    if (a.charonHasVersionSettings != b.charonHasVersionSettings)
        return false;                       // one has a range and the other does not
    if (!a.charonHasVersionSettings)
        return true;                        // neither has been given a range: nothing to disagree about
    return a.charonMinTLS == b.charonMinTLS && a.charonMaxTLS == b.charonMaxTLS;
}
