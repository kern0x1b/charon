// CharonAVKitProtocols.h — the AVKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
#import <AVKit/AVKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol AVPlayerViewControllerDelegate;
// The PiP delegate is declared by the SDK this package compiles against, so its body comes from that
// import and only the name is repeated here - which is what the row of AVPictureInPictureControllerDelegate
// needs: the protocol row is `implemented`, the object defines __OBJC_PROTOCOL_$_... because
// CharonAVPlayerPictureInPictureRelay adopts it, and a generated source naming it has to find the
// declaration in this header or in a header of this folder it imports.
@protocol AVPictureInPictureControllerDelegate;
