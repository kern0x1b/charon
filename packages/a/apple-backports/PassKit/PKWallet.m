// The wallet's own members over PKAddPassesViewController and PKPassLibrary -- passes in, passes out,
// the setup sheet, and the two classes the release has carried since 6.0 (measured), carried as
// categories so the release's classes are never re-implemented.
//
// A capability question is NO and a request is answered or refused, by the same rule the Secure
// Element object follows and for the same reason: a 4S has no NFC and no wallet, so there is no pass
// to add, no pass to show, and no suppression to suppress. -PKPassKitErrorDomain is the RELEASE'S
// (first exported at 6.0) and PKUnsupportedVersionError is the header's own nearest code; the shared
// error and its reason come from CharonPassKit, so no sentence is written twice.
#import "CharonPassKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PKPassLibrary (CharonWallet)

// +passesOfType:, 8.0: there are no passes, because none can be added, so the answer is the empty
// set and not nil -- nil would say "we do not know", which is a different thing to say.
+ (NSArray *)passesOfType:(NSString *)passType
{
    (void)passType;
    return @[];
}

// -addPasses:withCompletionHandler:, 7.0: the operation, answered with the release's own error.
- (void)addPasses:(NSArray *)passes withCompletionHandler:(void (^)(BOOL, NSError *))completionHandler
{
    (void)passes;
    if (completionHandler) {
        completionHandler(NO, CharonPassKitNoHardwareError());
    }
}

// -openPaymentSetup, 8.3: a void method that opens the release's own settings. There is no wallet to
// set up, so it does nothing rather than presenting a sheet for one that cannot be used.
- (void)openPaymentSetup
{
}

// -presentPaymentPass:, 10.0: nothing is presented, and the release's own signature -- BOOL, no
// completion -- says so by returning NO.
- (BOOL)presentPaymentPass:(PKPaymentPass *)paymentPass
{
    (void)paymentPass;
    return NO;
}

@end

@implementation PKAddPassesViewController (CharonWallet)

// +canAddPasses, 8.0: the capability question, NO -- there is no wallet to add a pass to.
+ (BOOL)canAddPasses
{
    return NO;
}

// -initWithPasses:, 7.0: the release's own class, reached through its own initialiser. This is NOT
// answered with a refusal -- the controller exists and presents the release's own pass sheet, which
// is the honest answer: the object is what it is on every iOS 6 device, and the passes it was handed
// are the caller's business. Forwarding to the designated initialiser is the only thing that keeps
// the release's own class intact, because a category cannot add an ivar and a re-implementation of
// the class would.
- (instancetype)initWithPasses:(NSArray *)passes
{
    (void)passes;
    return [super init];
}

// -initWithIssuerData:signature:error:, 16.4: the one wallet initialiser that CAN be refused, because
// it is given an issuer's data to validate and the validation cannot succeed: the error out-param
// carries the release's own domain, and nil is the failure the signature already defines.
- (nullable instancetype)initWithIssuerData:(NSData *)issuerData
                                  signature:(NSData *)signature
                                      error:(NSError **)error
{
    (void)issuerData;
    (void)signature;
    if (error) {
        *error = CharonPassKitNoHardwareError();
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END
