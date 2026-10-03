// CharonAVFoundationProtocols.h — the AVFoundation protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <AVFoundation/AVFoundation.h> for that body, and
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
#import "CharonAVMetrics18.h"

@protocol AVCaptureDataOutputSynchronizerDelegate;

// The queue the two 11.0 render classes share. The 16.4 SDK this package compiles against declares
// it (AVQueuedSampleBufferRendering.h, the 11.0 protocol the generated sources name), and this is the
// forward declaration that makes their @protocol(...) name resolve. The port supplies the protocol
// OBJECT itself, which is the part no release below 11.0 has.
@protocol AVQueuedSampleBufferRendering;

@protocol AVMetricEventStreamSubscriber;

// Below this one the tool's own output, character for character: `python3 tools/transcribe-protocols.py
// <sdk26> <sdk16> <worktree> <out> AVCaptureDataOutputSynchronizerDelegate:AVFoundation:11.0
// AVQueuedSampleBufferRendering:AVFoundation:11.0 AVMetricEventStreamSubscriber:AVFoundation:18.0
// AVCaptureSessionControlsDelegate:AVFoundation:18.0` writes exactly these lines, the three forward
// declarations and the import of CharonAVMetrics18.h above them, and nothing else (the comments are not
// the tool's, which is why a regeneration drops them). The protocol is iOS 18's and the 16.4 SDK this
// package compiles against declares it nowhere, so it is transcribed rather than forward-declared: the
// generated source names it with @protocol(...), and a name with no definition in the image is a symbol
// nothing binds.
API_AVAILABLE(ios(18.0))
@protocol AVCaptureSessionControlsDelegate <NSObject>
- (void)sessionControlsDidBecomeActive:(AVCaptureSession * _Nonnull)session;
- (void)sessionControlsWillEnterFullscreenAppearance:(AVCaptureSession * _Nonnull)session;
- (void)sessionControlsWillExitFullscreenAppearance:(AVCaptureSession * _Nonnull)session;
- (void)sessionControlsDidBecomeInactive:(AVCaptureSession * _Nonnull)session;
@end
