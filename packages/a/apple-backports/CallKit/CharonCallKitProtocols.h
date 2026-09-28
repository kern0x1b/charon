// CharonCallKitProtocols.h — the CallKit protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(10.0))
@protocol CXCallObserverDelegate <NSObject>
- (void)callObserver:(CXCallObserver * _Nonnull)callObserver callChanged:(CXCall * _Nonnull)call;
@end

API_AVAILABLE(ios(10.0))
@protocol CXProviderDelegate <NSObject>
- (void)providerDidReset:(CXProvider * _Nonnull)provider;
- (void)providerDidBegin:(CXProvider * _Nonnull)provider;
- (BOOL)provider:(CXProvider * _Nonnull)provider executeTransaction:(CXTransaction * _Nonnull)transaction;
- (void)provider:(CXProvider * _Nonnull)provider performStartCallAction:(CXStartCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performAnswerCallAction:(CXAnswerCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performEndCallAction:(CXEndCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performSetHeldCallAction:(CXSetHeldCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performSetMutedCallAction:(CXSetMutedCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performSetGroupCallAction:(CXSetGroupCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performPlayDTMFCallAction:(CXPlayDTMFCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider performSetTranslatingCallAction:(CXSetTranslatingCallAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider timedOutPerformingAction:(CXAction * _Nonnull)action;
- (void)provider:(CXProvider * _Nonnull)provider didActivateAudioSession:(AVAudioSession * _Nonnull)audioSession;
- (void)provider:(CXProvider * _Nonnull)provider didDeactivateAudioSession:(AVAudioSession * _Nonnull)audioSession;
@end
