// The port's own construction of the AuthenticationServices classes whose -init and +new the release
// marks unavailable, and the coding key the base request uses.
//
// `ASAuthorizationRequest.h` marks both unavailable: an application is not meant to make a bare
// request, because nothing can service one without a provider. The port has to make these -- it is the
// thing that implements the class -- and calling `[[ASAuthorizationRequest alloc] init]` does not
// compile against those marks, so the construction is named, declared here, and defined in the file
// that implements the class. The header's unavailability still stands for every other caller, which is
// the point of it: `[ASAuthorizationRequest new]` in an application still does not compile.
//
// This is the same mechanism HomeKit's graph uses, for the same reason, and it is the shape every
// class in this family is written in.
#ifndef CHARON_AS_CONSTRUCTION_H
#define CHARON_AS_CONSTRUCTION_H

#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>

// The key -encodeWithCoder: and -initWithCoder: use for the provider. It is the port's own: the
// release's coder key is not in the public header, and a key two implementations choose differently is
// a key neither can read.
extern NSString *const ASCharonProviderCodingKey;

// The designated initialisers. A method may only assign `self` when it is in the init method family,
// and clang decides that from the attribute rather than from the spelling -- so a selector called
// `charon_init...` is not, and writing `self = [super init]` in one is rejected with "cannot assign to
// 'self' outside of a method in the init family". `objc_method_family(init)` is what makes a
// port's own name usable here.
#define CHARON_AS_CONSTRUCTION(cls, ...) \
    @interface cls (CharonASConstruction) \
    - (instancetype)charon_initWithProvider:(id<ASAuthorizationProvider>)provider __VA_ARGS__ \
    __attribute__((objc_method_family(init))); \
    @end

@interface ASAuthorizationRequest (CharonASConstruction)
- (instancetype)charon_initWithProvider:(id<ASAuthorizationProvider>)provider
    __attribute__((objc_method_family(init)));
@end

#endif
