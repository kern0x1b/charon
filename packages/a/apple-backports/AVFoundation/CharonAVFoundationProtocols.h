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
