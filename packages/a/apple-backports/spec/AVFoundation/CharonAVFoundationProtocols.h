// CharonAVFoundationProtocols.h - the AVFoundation protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <AVFoundation/AVFoundation.h> for that body, and
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
#import "CharonAVMetrics18.h"

@protocol AVAssetDownloadDelegate;

@protocol AVAssetReaderCaptionValidationHandling;

@protocol AVAssetResourceLoaderDelegate;

@protocol AVAssetWriterDelegate;

@protocol AVCaptureDataOutputSynchronizerDelegate;

@protocol AVCaptureDepthDataOutputDelegate;

@protocol AVCaptureFileOutputRecordingDelegate;

@protocol AVCapturePhotoCaptureDelegate;

@protocol AVCapturePhotoFileDataRepresentationCustomizer;

typedef enum AVCapturePhotoOutputCaptureReadiness AVCapturePhotoOutputCaptureReadiness;
@class AVCapturePhotoOutputReadinessCoordinator;
API_AVAILABLE(ios(17.0))
@protocol AVCapturePhotoOutputReadinessCoordinatorDelegate <NSObject>
@optional
- (void)readinessCoordinator:(AVCapturePhotoOutputReadinessCoordinator * _Nonnull)coordinator captureReadinessDidChange:(AVCapturePhotoOutputCaptureReadiness)captureReadiness;
@end

API_AVAILABLE(ios(18.0))
@protocol AVCaptureSessionControlsDelegate <NSObject>
- (void)sessionControlsDidBecomeActive:(AVCaptureSession * _Nonnull)session;
- (void)sessionControlsWillEnterFullscreenAppearance:(AVCaptureSession * _Nonnull)session;
- (void)sessionControlsWillExitFullscreenAppearance:(AVCaptureSession * _Nonnull)session;
- (void)sessionControlsDidBecomeInactive:(AVCaptureSession * _Nonnull)session;
@end

API_AVAILABLE(ios(26.0))
@protocol AVCaptureSessionDeferredStartDelegate <NSObject>
- (void)sessionWillRunDeferredStart:(AVCaptureSession * _Nonnull)session;
- (void)sessionDidRunDeferredStart:(AVCaptureSession * _Nonnull)session;
@end

@class AVCaptureTimecode;
@class AVCaptureTimecodeGenerator;
typedef enum AVCaptureTimecodeGeneratorSynchronizationStatus AVCaptureTimecodeGeneratorSynchronizationStatus;
@class AVCaptureTimecodeSource;
API_AVAILABLE(ios(26.0))
@protocol AVCaptureTimecodeGeneratorDelegate <NSObject>
- (void)timecodeGenerator:(AVCaptureTimecodeGenerator * _Nonnull)generator didReceiveUpdate:(AVCaptureTimecode)timecode fromSource:(AVCaptureTimecodeSource * _Nonnull)source;
- (void)timecodeGenerator:(AVCaptureTimecodeGenerator * _Nonnull)generator transitionedToSynchronizationStatus:(AVCaptureTimecodeGeneratorSynchronizationStatus)synchronizationStatus forSource:(AVCaptureTimecodeSource * _Nonnull)source;
- (void)timecodeGenerator:(AVCaptureTimecodeGenerator * _Nonnull)generator didUpdateAvailableSources:(NSArray<AVCaptureTimecodeSource *> * _Nonnull)availableSources;
@end

@protocol AVContentKeyRecipient;

@protocol AVContentKeySessionDelegate;

@class AVExternalSyncDevice;
API_AVAILABLE(ios(26.0))
@protocol AVExternalSyncDeviceDelegate <NSObject>
@optional
- (void)externalSyncDeviceStatusDidChange:(AVExternalSyncDevice * _Nonnull)device;
- (void)externalSyncDevice:(AVExternalSyncDevice * _Nonnull)device failedWithError:(NSError * _Nullable)error;
@end

@protocol AVFragmentMinding;

@protocol AVMetricEventStreamPublisher;

@protocol AVMetricEventStreamSubscriber;

@protocol AVPlaybackCoordinatorPlaybackControlDelegate;

@protocol AVPlayerItemLegibleOutputPushDelegate;

@protocol AVPlayerItemMetadataOutputPushDelegate;

@class AVPlayerItemRenderedLegibleOutput;
@class AVRenderedCaptionImage;
API_AVAILABLE(ios(18.0))
@protocol AVPlayerItemRenderedLegibleOutputPushDelegate <AVPlayerItemOutputPushDelegate>
@optional
- (void)renderedLegibleOutput:(AVPlayerItemRenderedLegibleOutput * _Nonnull)output didOutputRenderedCaptionImages:(NSArray<AVRenderedCaptionImage *> * _Nonnull)captionImages forItemTime:(CMTime)itemTime;
@end

@protocol AVPlayerPlaybackCoordinatorDelegate;

@protocol AVQueuedSampleBufferRendering;

@protocol AVVideoCompositing;

@protocol AVVideoCompositionInstruction;
