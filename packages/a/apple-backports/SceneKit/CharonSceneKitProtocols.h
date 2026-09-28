// CharonSceneKitProtocols.h — the SceneKit protocols the SDK this package compiles against does not declare,
// transcribed by tools/transcribe-protocols.py from the SDK that declares them: the base list, each
// member with its kind, return type and parameter types, @required and @optional as sections, and
// API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the release it arrived in.
// Facts only, and nothing written for a protocol or a member the generator refused by name below.
#import <SceneKit/SceneKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(8.0))
@protocol SCNAnimatable <NSObject>
@end

API_AVAILABLE(ios(9.0))
@protocol SCNSceneRendererDelegate <NSObject>
@end
