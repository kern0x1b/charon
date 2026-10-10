// CharonGameKitProtocols.h - the GameKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <GameKit/GameKit.h> for that body, and
#import <GameKit/GameKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol GKChallengeListener;

@class GKGameActivity;
API_AVAILABLE(ios(26.0))
@protocol GKGameActivityListener <NSObject>
@optional
- (void)player:(GKPlayer * _Nonnull)player wantsToPlayGameActivity:(GKGameActivity * _Nonnull)activity completionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
@end

@protocol GKGameSessionEventListener;

@protocol GKInviteEventListener;

@protocol GKLocalPlayerListener;

@protocol GKMatchDelegate;

@protocol GKMatchmakerViewControllerDelegate;

@protocol GKSavedGameListener;

@protocol GKTurnBasedEventListener;
