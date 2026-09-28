// CharonSceneKitProtocols.h — the SceneKit protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(8.0))
@protocol SCNAnimatable <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol SCNSceneRenderer <NSObject>
@end

API_AVAILABLE(ios(9.0))
@protocol SCNSceneRendererDelegate <NSObject>
- (void)renderer:(id<SCNSceneRenderer>  _Nonnull)renderer updateAtTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>  _Nonnull)renderer didApplyAnimationsAtTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>  _Nonnull)renderer didSimulatePhysicsAtTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>  _Nonnull)renderer didApplyConstraintsAtTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>  _Nonnull)renderer willRenderScene:(SCNScene * _Nonnull)scene atTime:(NSTimeInterval)time;
- (void)renderer:(id<SCNSceneRenderer>  _Nonnull)renderer didRenderScene:(SCNScene * _Nonnull)scene atTime:(NSTimeInterval)time;
@end
