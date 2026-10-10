// CharonPassKitProtocols.h - the PassKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <PassKit/PassKit.h> for that body, and
#import <PassKit/PassKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol PKAddPaymentPassViewControllerDelegate;

@protocol PKAddSecureElementPassViewControllerDelegate;

@protocol PKIdentityDocumentDescriptor;

@protocol PKIssuerProvisioningExtensionAuthorizationProviding;

@class PKPayLaterView;
API_AVAILABLE(ios(17.0))
@protocol PKPayLaterViewDelegate <NSObject>
- (void)payLaterViewDidUpdateHeight:(PKPayLaterView * _Nonnull)view;
@end

@protocol PKPaymentAuthorizationControllerDelegate;

@protocol PKPaymentAuthorizationViewControllerDelegate;

@protocol PKShareSecureElementPassViewControllerDelegate;

@protocol PKVehicleConnectionDelegate;
