// CharonLocalAuthenticationProtocols.h — the LocalAuthentication protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
#import <LocalAuthentication/LocalAuthentication.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@class LAEnvironment;
@class LAEnvironmentState;
API_AVAILABLE(ios(18.0))
@protocol LAEnvironmentObserver <NSObject>
@optional
- (void)environment:(LAEnvironment * _Nonnull)environment stateDidChangeFromOldState:(LAEnvironmentState * _Nonnull)oldState;
@end
