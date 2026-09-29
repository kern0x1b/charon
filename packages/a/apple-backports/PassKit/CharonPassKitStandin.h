// PKPaymentAuthorizationController and PKPaymentAuthorizationViewController, as the PORT declares
// them, for the builds that cannot see Apple's: the host probe and the contract check. No framework
// is imported, so what is compiled is this port's code and not this Mac's PassKit -- whose
// PKPaymentAuthorizationController exists, so a second @implementation of the name is a duplicate
// symbol and the measurement would be of Apple's class.
//
// The two types the members are spelled with are here too, because the release's headers do not
// declare them either: PKMerchantCapability is the header's own option set and NSArray is what the
// two -canMakePaymentsUsingNetworks: methods take. Without them the class methods do not compile, and
// a port whose members cannot be compiled is not carried.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, PKMerchantCapability) {
    PKMerchantCapability3DS = 1 << 0,
    PKMerchantCapabilityCredit = 1 << 1,
    PKMerchantCapabilityDebit = 1 << 2,
};

@interface PKPaymentAuthorizationController : NSObject
+ (BOOL)canMakePayments;
+ (BOOL)canMakePaymentsUsingNetworks:(NSArray *)networks;
+ (BOOL)canMakePaymentsUsingNetworks:(NSArray *)networks capabilities:(PKMerchantCapability)capabilities;
@end

// The view controller, a UIViewController subclass as the SDK declares it, 8.0.
@interface PKPaymentAuthorizationViewController : UIViewController
+ (BOOL)canMakePayments;
+ (BOOL)canMakePaymentsUsingNetworks:(NSArray *)networks;
+ (BOOL)canMakePaymentsUsingNetworks:(NSArray *)networks capabilities:(PKMerchantCapability)capabilities;
@end
