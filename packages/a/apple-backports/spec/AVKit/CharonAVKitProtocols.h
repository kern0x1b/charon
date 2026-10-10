// CharonAVKitProtocols.h - the AVKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <AVKit/AVKit.h> for that body, and
#import <AVKit/AVKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@class AVInputPickerInteraction;
API_AVAILABLE(ios(26.0))
@protocol AVInputPickerInteractionDelegate <NSObject>
@optional
- (void)inputPickerInteractionWillBeginPresenting:(AVInputPickerInteraction * _Nonnull)inputPickerInteraction;
- (void)inputPickerInteractionDidEndPresenting:(AVInputPickerInteraction * _Nonnull)inputPickerInteraction;
- (void)inputPickerInteractionWillBeginDismissing:(AVInputPickerInteraction * _Nonnull)inputPickerInteraction;
- (void)inputPickerInteractionDidEndDismissing:(AVInputPickerInteraction * _Nonnull)inputPickerInteraction;
@end

@protocol AVPictureInPictureControllerDelegate;

@protocol AVPictureInPictureSampleBufferPlaybackDelegate;

@protocol AVPlayerViewControllerDelegate;

@protocol AVRoutePickerViewDelegate;
