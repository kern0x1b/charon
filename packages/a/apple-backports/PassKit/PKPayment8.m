// PKPaymentRequest and PKPaymentSummaryItem, the two classes of the 8.0 payment request that hold
// THE CALLER'S OWN DATA, carried as classes because the release has neither of them.
//
// WHY THESE TWO AND NOT THE OTHER THREE OF 8.0. apple.objc.inventory against the armv7 dyld shared
// cache of 6.1.3 finds 64 classes beginning PK and none of them begins PKPayment (control in the same
// run: 590 class rows beginning NS and one beginning PKA, PKAddPassesViewController), and
// tools/cache-index/first-rung.py answers 8.0 for PKPayment, PKPaymentPass, PKPaymentRequest,
// PKPaymentSummaryItem and PKPaymentToken. So all five arrived after the release. What separates
// them is what a member can answer, and this file is the line:
//
//   A VALUE THE CALLER PUT IN. Every member of these two is a property the application sets and
//   reads back: a line item's label and decimal amount, a request's merchant identifier, country
//   code, currency, networks, capability bits, address-field bits and the summary items themselves.
//   None of it is produced by the Secure Element or by Apple's service, so all of it is real here and
//   is answered by keeping what it was given.
//
//   A VALUE ONLY A COMPLETED TRANSACTION PRODUCES. PKPayment, PKPaymentToken and PKPaymentPass are
//   the other three: the credential the Secure Element encrypts to the merchant, the pass it came
//   from, and the result object the authorization delegate is handed. Every member of them reads
//   that one value, a port class of those names would answer nil where the header promises an
//   object, and a nil handed to a merchant backend is worse than no class. Those three stay `absent`
//   in the registry, and PKPass14.m already says why it does not answer -paymentPass the same way.
//
// ONE OBJECT PER RELEASE, and this is the 8.0 one. The 8.0 members only: PKPaymentSummaryItem's -type
// and +summaryItemWithLabel:amount:type: are 9.0, and PKPaymentRequest's -shippingType is 8.3 and
// its two PKContact members are 9.0, so none of them is here - an object carrying API of two
// releases is what tools/release-split.lua refuses, and it can only see the two class symbols, so
// the split is this file's job and not the tool's. The ledger in registry/PassKit/ios8.json carries
// a row for each of the two classes and none for their members, which is what check_registry's
// entry_of expects: a class row answers for the members of a class the port defines wholly.
//
// What a caller gets is the object, not a payment: the request reads back exactly what was set on it,
// and presenting it is what cannot happen - -[PKPaymentAuthorizationViewController initWithRequest:]
// needs a PKPaymentPass, which the release has not got and this port declines to invent.
#import <Foundation/Foundation.h>
#if defined(CHARON_PASSKIT_STANDIN)
#import "CharonPassKitStandin.h"
#else
#import <PassKit/PassKit.h>
#endif

@implementation PKPaymentSummaryItem {
    NSString *_label;
    NSDecimalNumber *_amount;
}

// +summaryItemWithLabel:amount:, 8.0: the header's own factory, and the whole of what a line item
// holds. Both properties are `copy`, so the object keeps a copy of what it was handed and not the
// caller's mutable string, which is what the declaration says.
+ (instancetype)summaryItemWithLabel:(NSString *)label amount:(NSDecimalNumber *)amount
{
    PKPaymentSummaryItem *item = [[self alloc] init];
    item.label = label;
    item.amount = amount;
    return item;
}

// "Tax", "Gift Card": the caller's own string, kept. Nothing shortens or localizes it, because the
// caller has already localized it - the header calls it "a short localized description of the item".
- (NSString *)label
{
    return _label;
}

- (void)setLabel:(NSString *)label
{
    _label = [label copy];
}

// The amount, in the currency of the enclosing request, negatives permitted (a redeemed coupon).
// NSDecimalNumber is the release's own since 1.0, so the decimal arithmetic behind it is Apple's and
// not this port's; nothing here rounds, scales or compares it.
- (NSDecimalNumber *)amount
{
    return _amount;
}

- (void)setAmount:(NSDecimalNumber *)amount
{
    _amount = [amount copy];
}

@end

@implementation PKPaymentRequest {
    NSString *_merchantIdentifier;
    NSString *_countryCode;
    NSArray *_supportedNetworks;
    PKMerchantCapability _merchantCapabilities;
    NSArray *_paymentSummaryItems;
    NSString *_currencyCode;
    PKAddressField _requiredBillingAddressFields;
    PKAddressField _requiredShippingAddressFields;
    NSArray *_shippingMethods;
    NSData *_applicationData;
}

// Every accessor below is the caller's own value read back, and each is spelled as the SDK 16.4's own
// PKPaymentRequest.h spells it (measured against the headers of
// iphoneos-sdk/16.4/*/iPhoneOS16.4.sdk/System/Library/Frameworks/PassKit.framework/Headers): the four
// strings and the data `copy`, the two arrays `copy`, the two bitfields and the capability `assign`.
//
// The two PKAddressField properties are the 8.0 spellings the header deprecated at 11.0 in favour of
// the requiredBilling/ShippingContactFields NSSet. They are carried because they ARE the 8.0 API and
// their own header says the default is PKAddressFieldNone, which is 0 - so an ivar that starts at
// zero already carries Apple's own default and no initializer has to invent one.
- (NSString *)merchantIdentifier
{
    return _merchantIdentifier;
}

- (void)setMerchantIdentifier:(NSString *)merchantIdentifier
{
    _merchantIdentifier = [merchantIdentifier copy];
}

- (NSString *)countryCode
{
    return _countryCode;
}

- (void)setCountryCode:(NSString *)countryCode
{
    _countryCode = [countryCode copy];
}

// The merchant's networks, as the NSArray of PKPaymentNetwork strings it gave (PKPaymentNetwork is
// the header's own NSString typedef, so the array holds strings and no object this port lacks).
- (NSArray *)supportedNetworks
{
    return _supportedNetworks;
}

- (void)setSupportedNetworks:(NSArray *)supportedNetworks
{
    _supportedNetworks = [supportedNetworks copy];
}

- (PKMerchantCapability)merchantCapabilities
{
    return _merchantCapabilities;
}

- (void)setMerchantCapabilities:(PKMerchantCapability)merchantCapabilities
{
    _merchantCapabilities = merchantCapabilities;
}

// The line items, which are PKPaymentSummaryItem objects of this same object file. The last one is
// the total, which the header requires and the port does not second-guess.
- (NSArray *)paymentSummaryItems
{
    return _paymentSummaryItems;
}

- (void)setPaymentSummaryItems:(NSArray *)paymentSummaryItems
{
    _paymentSummaryItems = [paymentSummaryItems copy];
}

- (NSString *)currencyCode
{
    return _currencyCode;
}

- (void)setCurrencyCode:(NSString *)currencyCode
{
    _currencyCode = [currencyCode copy];
}

- (PKAddressField)requiredBillingAddressFields
{
    return _requiredBillingAddressFields;
}

- (void)setRequiredBillingAddressFields:(PKAddressField)requiredBillingAddressFields
{
    _requiredBillingAddressFields = requiredBillingAddressFields;
}

- (PKAddressField)requiredShippingAddressFields
{
    return _requiredShippingAddressFields;
}

- (void)setRequiredShippingAddressFields:(PKAddressField)requiredShippingAddressFields
{
    _requiredShippingAddressFields = requiredShippingAddressFields;
}

// The shipping methods the merchant offers. PKShippingMethod is a class this port does not carry and
// does not pretend to: the array is kept exactly as given, and a caller that has none passes an empty
// one, which is the honest state of a device whose request is never presented.
- (NSArray *)shippingMethods
{
    return _shippingMethods;
}

- (void)setShippingMethods:(NSArray *)shippingMethods
{
    _shippingMethods = [shippingMethods copy];
}

// The merchant's own bytes, which the header says are signed into the resulting PKPaymentToken. The
// bytes are kept; nothing signs them, because signing them is the Secure Element's operation and it
// is what makes the resulting token absent from this port.
- (NSData *)applicationData
{
    return _applicationData;
}

- (void)setApplicationData:(NSData *)applicationData
{
    _applicationData = [applicationData copy];
}

@end