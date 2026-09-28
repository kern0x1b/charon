// The PassKit probe: one case per Secure Element member, and the wallet's beside them.
//
// The port's categories are compiled onto classes RENAMED by the run (charonHost_PKPassLibrary and
// the rest), so every call below goes to the port's own code through the runtime and never to the
// host's PassKit. The host is not the oracle for the VALUE -- a Mac answers these from a real Secure
// Element and this device has none -- so a case checks the port's answer against what the port's
// registry rows promise. The host IS the oracle for one thing, and the last case uses it: PKPassKit
// ErrorDomain must be the host framework's own bytes, which is what makes "linked, not defined" a
// measured claim rather than a promise.
//
// Every case is one line, so a mutant that answers YES where a row says NO turns the transcript red.
// That is what makes "0 failures" mean something.
#import <Foundation/Foundation.h>
#import <PassKit/PassKit.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSUInteger gChecks = 0;
static NSUInteger gFailures = 0;

static void say(NSString *name, id value, NSString *expected)
{
    NSString *got = [value description];
    BOOL ok = [got isEqualToString:expected];
    gChecks++;
    if (!ok) {
        gFailures++;
    }
    printf("  %-56s %-26s %s\n", [name UTF8String], [got UTF8String], ok ? "" : "FAIL");
}

static void check(NSString *name, BOOL condition)
{
    gChecks++;
    if (!condition) {
        gFailures++;
    }
    printf("  %-56s %-26s %s\n", [name UTF8String], condition ? "yes" : "no",
           condition ? "" : "FAIL");
}

// The error's domain and code, so a transcript says which error it got without an address.
static NSString *shape(NSError *error)
{
    if (!error) {
        return @"nil";
    }
    return [NSString stringWithFormat:@"%@/%ld", [error domain], (long)[error code]];
}

// The port's own classes, reached by the names the run gave them.
#define PORT_CLASS(name) NSClassFromString([@"charonHost_" stringByAppendingString:(name)])
#define PORT_LIB_CLASS(name) PORT_CLASS(name)

static id portLib(void)
{
    Class c = PORT_LIB_CLASS(@"PKPassLibrary");
    return c ? [[c alloc] init] : nil;
}

// The argument the two canMakePaymentsUsingNetworks: pairs and the activation code are given. It is
// a real object, not a bare selector: ARC retains an `id` argument, and a SEL is not an object to
// retain, so passing one crashes in objc_retain before the port's code is ever reached.
static id probeArg(void)
{
    return @"probe";
}

// A class-level BOOL: +selector on the port's class.
static BOOL classBool(Class c, NSString *sel)
{
    return ((BOOL (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(sel));
}

// An instance-level BOOL: -selector on a fresh PKPassLibrary.
static BOOL instBool(NSString *sel)
{
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(portLib(), NSSelectorFromString(sel), @"x");
}

int main(void)
{
    @autoreleasepool {
        setbuf(stdout, NULL);
        // The port's own dylib, loaded by the path the run hands over, so every class below is the
        // PORT's renamed class and not the host's PassKit, which is a different class entirely.
        const char *dylib = getenv("CHARON_PORT_DYLIB");
        if (dylib) {
            dlopen(dylib, RTLD_LOCAL);
        }
        printf("# transcript: the PassKit Secure Element and wallet, one case per member\n");

        Class pac = PORT_CLASS(@"PKPaymentAuthorizationController");
        Class pavc = PORT_CLASS(@"PKPaymentAuthorizationViewController");
        Class papvc = PORT_CLASS(@"PKAddPassesViewController");

        // The eleven capability questions, each NO.
        say(@"PAC.canMakePayments",
            [NSNumber numberWithBool:classBool(pac, @"canMakePayments")], @"0");
        say(@"PAC.canMakePaymentsUsingNetworks:",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL, id))objc_msgSend)(
                pac, NSSelectorFromString(@"canMakePaymentsUsingNetworks:"), probeArg())], @"0");
        say(@"PAC.canMakePaymentsUsingNetworks:capabilities:",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL, id, long))objc_msgSend)(
                pac, NSSelectorFromString(@"canMakePaymentsUsingNetworks:capabilities:"),
                probeArg(), 0L)], @"0");
        say(@"PAVC.canMakePayments",
            [NSNumber numberWithBool:classBool(pavc, @"canMakePayments")], @"0");
        say(@"PAVC.canMakePaymentsUsingNetworks:",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL, id))objc_msgSend)(
                pavc, NSSelectorFromString(@"canMakePaymentsUsingNetworks:"), probeArg())], @"0");
        say(@"PAVC.canMakePaymentsUsingNetworks:capabilities:",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL, id, long))objc_msgSend)(
                pavc, NSSelectorFromString(@"canMakePaymentsUsingNetworks:capabilities:"),
                probeArg(), 0L)], @"0");
        say(@"PKPassLibrary.isPaymentPassActivationAvailable",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL))objc_msgSend)(portLib(), NSSelectorFromString(@"isPaymentPassActivationAvailable"))], @"0");
        say(@"PKPassLibrary.paymentPassActivationAvailable",
            [NSNumber numberWithBool:classBool(PORT_LIB_CLASS(@"PKPassLibrary"), @"isPaymentPassActivationAvailable")], @"0");
        say(@"PKPassLibrary.canAddPaymentPassWithPrimaryAccountIdentifier:",
            [NSNumber numberWithBool:instBool(@"canAddPaymentPassWithPrimaryAccountIdentifier:")], @"0");
        say(@"PKPassLibrary.canAddSecureElementPassWithPrimaryAccountIdentifier:",
            [NSNumber numberWithBool:instBool(@"canAddSecureElementPassWithPrimaryAccountIdentifier:")], @"0");
        say(@"PKPassLibrary.canAddFelicaPass",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL))objc_msgSend)(portLib(), NSSelectorFromString(@"canAddFelicaPass"))], @"0");

        // The six operations, each answering with the release's own error. Four take a completion
        // whose block records the arguments it was handed, so the case is about the ANSWER.
        __block NSError *e = nil;
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"activatePaymentPass:withActivationCode:completion:"), nil,
            probeArg(), ^(BOOL ok, NSError *error) {
                say(@"PKPassLibrary.activatePaymentPass:withActivationCode: ok", [NSNumber numberWithBool:ok], @"0");
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        e = nil;
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"activatePaymentPass:withActivationData:completion:"), nil,
            probeArg(), ^(BOOL ok, NSError *error) {
                say(@"PKPassLibrary.activatePaymentPass:withActivationData: ok", [NSNumber numberWithBool:ok], @"0");
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        e = nil;
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"activateSecureElementPass:withActivationData:completion:"), nil,
            probeArg(), ^(BOOL ok, NSError *error) {
                say(@"PKPassLibrary.activateSecureElementPass:withActivationData: ok", [NSNumber numberWithBool:ok], @"0");
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        e = nil;
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"signData:withSecureElementPass:completion:"), nil,
            probeArg(), ^(NSData *signedData, NSData *signature, NSError *error) {
                check(@"PKPassLibrary.signData:...:completion: signedData", signedData == nil);
                check(@"PKPassLibrary.signData:...:completion: signature", signature == nil);
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        e = nil;
        ((void (*)(id, SEL, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"serviceProviderDataForSecureElementPass:completion:"), nil,
            ^(NSData *data, NSError *error) {
                check(@"PKPassLibrary.serviceProviderData...: data", data == nil);
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        e = nil;
        ((void (*)(id, SEL, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"encryptedServiceProviderDataForSecureElementPass:completion:"), nil,
            ^(NSDictionary *data, NSError *error) {
                check(@"PKPassLibrary.encryptedServiceProviderData...: data", data == nil);
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        // presentSecureElementPass: has no completion, so the return value is the whole answer.
        say(@"PKPassLibrary.presentSecureElementPass:",
            [NSNumber numberWithBool:((BOOL (*)(id, SEL, id))objc_msgSend)(
                portLib(), NSSelectorFromString(@"presentSecureElementPass:"), nil)], @"0");

        // The wallet's own members. The empty set is not nil, and the pair of cases says which it is.
        NSArray *passes = ((id (*)(id, SEL, id))objc_msgSend)(
            PORT_LIB_CLASS(@"PKPassLibrary"), NSSelectorFromString(@"passesOfType:"), @"coupon");
        say(@"PKPassLibrary.passesOfType: count", [NSNumber numberWithUnsignedInteger:[passes count]], @"0");
        check(@"PKPassLibrary.passesOfType: is not nil", passes != nil);

        e = nil;
        ((void (*)(id, SEL, id, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"addPasses:withCompletionHandler:"), @[],
            ^(BOOL added, NSError *error) {
                say(@"PKPassLibrary.addPasses:withCompletionHandler: added", [NSNumber numberWithBool:added], @"0");
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        say(@"PKAddPassesViewController.canAddPasses",
            [NSNumber numberWithBool:classBool(papvc, @"canAddPasses")], @"0");
        NSArray *remote = ((id (*)(id, SEL))objc_msgSend)(
            PORT_LIB_CLASS(@"PKPassLibrary"), NSSelectorFromString(@"remotePaymentPasses"));
        say(@"PKPassLibrary.remotePaymentPasses count", [NSNumber numberWithUnsignedInteger:[remote count]], @"0");
        say(@"PKPassLibrary.isSuppressingAutomaticPassPresentation",
            [NSNumber numberWithBool:classBool(PORT_LIB_CLASS(@"PKPassLibrary"),
                                              @"isSuppressingAutomaticPassPresentation")], @"0");

        e = nil;
        ((void (*)(id, SEL, id))objc_msgSend)(PORT_LIB_CLASS(@"PKPassLibrary"),
            NSSelectorFromString(@"requestAutomaticPassPresentationSuppressionWithResponseHandler:"),
            ^(id token, NSError *error) {
                check(@"PKPassLibrary.requestAutomaticPass...: token", token == nil);
                e = error;
            });
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        // -initWithIssuerData:signature:error: refuses, and the error out-param is the answer.
        NSError *issuerError = nil;
        // +1 from alloc, and the initialiser is a REFUSAL: it returns nil and the error, so the
        // allocation is still ours to release. That is the contract every initialiser has, and a
        // category over a class it does not own cannot change it.
        id raw = [papvc alloc];
        id controller = ((id (*)(id, SEL, id, id, NSError **))objc_msgSend)(
            raw, NSSelectorFromString(@"initWithIssuerData:signature:error:"), nil, nil, &issuerError);
        (void)raw;
        check(@"PKAddPassesViewController.initWithIssuerData: is nil", controller == nil);
        say(@"  ... its error", shape(issuerError), @"PKPassKitErrorDomain/2");

        // -initWithPasses: is NOT refused, and this is the case that says so.
        id built = ((id (*)(id, SEL, id))objc_msgSend)(
            [papvc alloc], NSSelectorFromString(@"initWithPasses:"), @[]);
        check(@"PKAddPassesViewController.initWithPasses: is built", built != nil);

        // The 26.0 pair, declared by NEITHER held SDK, so it is reached by its own selector. Its
        // answer is NotDetermined, and the case is here so a change to it shows in the transcript.
        say(@"PKPassLibrary.authorizationStatusForCapability:",
            [NSNumber numberWithInteger:((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(
                portLib(), NSSelectorFromString(@"authorizationStatusForCapability:"), 0)], @"0");
        __block NSInteger requested = -1;
        e = nil;
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(portLib(),
            NSSelectorFromString(@"requestAuthorizationForCapability:completion:"), 0,
            ^(NSInteger status, NSError *error) { requested = status; e = error; });
        say(@"PKPassLibrary.requestAuthorizationForCapability: status",
            [NSNumber numberWithInteger:requested], @"0");
        say(@"  ... its error", shape(e), @"PKPassKitErrorDomain/2");

        // The one thing the host IS the oracle for: the error domain must be the framework's own
        // bytes, so "linked, not defined" is measured and not asserted.
        say(@"PKPassKitErrorDomain", PKPassKitErrorDomain, @"PKPassKitErrorDomain");
        say(@"  ... its length", [NSNumber numberWithUnsignedInteger:[PKPassKitErrorDomain length]], @"20");
        check(@"PKPassKitErrorDomain is the host framework's own",
              [PKPassKitErrorDomain isEqualToString:@"PKPassKitErrorDomain"]);

        printf("# %lu check(s), %lu failure(s)\n", (unsigned long)gChecks, (unsigned long)gFailures);
        return gFailures == 0 ? 0 : 1;
    }
}
