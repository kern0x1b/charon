// CharonAuthenticationServicesProtocols.h - the AuthenticationServices protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <AuthenticationServices/AuthenticationServices.h> for that body, and
#import <AuthenticationServices/AuthenticationServices.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol ASAccountAuthenticationModificationControllerDelegate;

@protocol ASAccountAuthenticationModificationControllerPresentationContextProviding;

@protocol ASAuthorizationControllerDelegate;

@protocol ASAuthorizationControllerPresentationContextProviding;

@protocol ASAuthorizationCredential;

@protocol ASAuthorizationProvider;

@protocol ASAuthorizationProviderExtensionAuthorizationRequestHandler;

@protocol ASAuthorizationPublicKeyCredentialAssertion;

@protocol ASAuthorizationPublicKeyCredentialAssertionRequest;

@protocol ASAuthorizationPublicKeyCredentialDescriptor;

@protocol ASAuthorizationPublicKeyCredentialRegistration;

@protocol ASAuthorizationPublicKeyCredentialRegistrationRequest;

@class ASPublicKeyCredentialClientData;
API_AVAILABLE(ios(17.4))
@protocol ASAuthorizationWebBrowserPlatformPublicKeyCredentialAssertionRequest <NSObject>
@property (nonatomic, readonly) NS_REFINED_FOR_SWIFT ASPublicKeyCredentialClientData *clientData;
@property (nonatomic, readwrite, assign, unsafe_unretained) BOOL shouldShowHybridTransport;
@end

typedef enum ASAuthorizationPlatformPublicKeyCredentialRegistrationRequestStyle ASAuthorizationPlatformPublicKeyCredentialRegistrationRequestStyle;
@class ASPublicKeyCredentialClientData;
API_AVAILABLE(ios(17.4))
@protocol ASAuthorizationWebBrowserPlatformPublicKeyCredentialProvider <NSObject>
- (ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest * _Nonnull)createCredentialRegistrationRequestWithClientData:(ASPublicKeyCredentialClientData * _Nonnull)clientData name:(NSString * _Nonnull)name userID:(NSData * _Nonnull)userID;
- (ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest * _Nonnull)createCredentialRegistrationRequestWithClientData:(ASPublicKeyCredentialClientData * _Nonnull)clientData name:(NSString * _Nonnull)name userID:(NSData * _Nonnull)userID requestStyle:(ASAuthorizationPlatformPublicKeyCredentialRegistrationRequestStyle)requestStyle;
- (ASAuthorizationPlatformPublicKeyCredentialAssertionRequest * _Nonnull)createCredentialAssertionRequestWithClientData:(ASPublicKeyCredentialClientData * _Nonnull)clientData;
@end

@class ASPublicKeyCredentialClientData;
API_AVAILABLE(ios(17.4))
@protocol ASAuthorizationWebBrowserPlatformPublicKeyCredentialRegistrationRequest <NSObject>
@property (nonatomic, readonly) NS_REFINED_FOR_SWIFT ASPublicKeyCredentialClientData *clientData;
@property (nonatomic, readwrite, copy) NSArray<ASAuthorizationPlatformPublicKeyCredentialDescriptor *> * _Nullable excludedCredentials;
@property (nonatomic, readwrite, assign, unsafe_unretained) BOOL shouldShowHybridTransport;
@end

@class ASPublicKeyCredentialClientData;
API_AVAILABLE(ios(17.4))
@protocol ASAuthorizationWebBrowserSecurityKeyPublicKeyCredentialAssertionRequest <NSObject>
@property (nonatomic, readonly) NS_REFINED_FOR_SWIFT ASPublicKeyCredentialClientData *clientData;
@end

@class ASPublicKeyCredentialClientData;
API_AVAILABLE(ios(17.4))
@protocol ASAuthorizationWebBrowserSecurityKeyPublicKeyCredentialProvider <NSObject>
- (ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest * _Nonnull)createCredentialRegistrationRequestWithClientData:(ASPublicKeyCredentialClientData * _Nonnull)clientData displayName:(NSString * _Nonnull)displayName name:(NSString * _Nonnull)name userID:(NSData * _Nonnull)userID;
- (ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest * _Nonnull)createCredentialAssertionRequestWithClientData:(ASPublicKeyCredentialClientData * _Nonnull)clientData;
@end

@class ASPublicKeyCredentialClientData;
API_AVAILABLE(ios(17.4))
@protocol ASAuthorizationWebBrowserSecurityKeyPublicKeyCredentialRegistrationRequest <NSObject>
@property (nonatomic, readonly) NS_REFINED_FOR_SWIFT ASPublicKeyCredentialClientData *clientData;
@end

API_AVAILABLE(ios(17.0))
@protocol ASCredentialIdentity <NSObject>
@property (nonatomic, readonly, strong) ASCredentialServiceIdentifier * _Nonnull serviceIdentifier;
@property (nonatomic, readonly, copy) NSString * _Nonnull user;
@property (nonatomic, readonly, copy) NSString * _Nullable recordIdentifier;
@property (nonatomic, readwrite, assign, unsafe_unretained) NSInteger rank;
@end

typedef enum ASCredentialRequestType ASCredentialRequestType;
API_AVAILABLE(ios(17.0))
@protocol ASCredentialRequest <NSObject, NSSecureCoding, NSCopying>
@property (nonatomic, readonly) ASCredentialRequestType type;
@property (nonatomic, readonly) id<ASCredentialIdentity> _Nonnull credentialIdentity;
@end

@protocol ASPublicKeyCredential;

@protocol ASWebAuthenticationPresentationContextProviding;
