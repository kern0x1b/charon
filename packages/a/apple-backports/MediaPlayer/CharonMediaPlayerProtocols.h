// CharonMediaPlayerProtocols.h — the MediaPlayer protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <MediaPlayer/MediaPlayer.h> for that body, and
#import <MediaPlayer/MediaPlayer.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol MPPlayableContentDataSource;

@protocol MPPlayableContentDelegate;

@protocol MPNowPlayingSessionDelegate;
