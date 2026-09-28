// CharonAVKitProtocols.h — the AVKit protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(8.0))
@protocol AVPlayerViewControllerDelegate <NSObject>
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController willBeginFullScreenPresentationWithAnimationCoordinator:(id<UIViewControllerTransitionCoordinator>  _Nonnull)coordinator;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController willEndFullScreenPresentationWithAnimationCoordinator:(id<UIViewControllerTransitionCoordinator>  _Nonnull)coordinator;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController restoreUserInterfaceForFullScreenExitWithCompletionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
- (BOOL)playerViewControllerShouldDismiss:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewControllerWillBeginDismissalTransition:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewControllerDidEndDismissalTransition:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewControllerWillStartPictureInPicture:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewControllerDidStartPictureInPicture:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController failedToStartPictureInPictureWithError:(NSError * _Nonnull)error;
- (void)playerViewControllerWillStopPictureInPicture:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewControllerDidStopPictureInPicture:(AVPlayerViewController * _Nonnull)playerViewController;
- (BOOL)playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController willPresentInterstitialTimeRange:(AVInterstitialTimeRange * _Nonnull)interstitial;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController didPresentInterstitialTimeRange:(AVInterstitialTimeRange * _Nonnull)interstitial;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController willResumePlaybackAfterUserNavigatedFromTime:(CMTime)oldTime toTime:(CMTime)targetTime;
- (CMTime)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController timeToSeekAfterUserNavigatedFromTime:(CMTime)oldTime toTime:(CMTime)targetTime;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController didSelectMediaSelectionOption:(AVMediaSelectionOption * _Nullable)mediaSelectionOption inMediaSelectionGroup:(AVMediaSelectionGroup * _Nonnull)mediaSelectionGroup;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController didSelectExternalSubtitleOptionLanguage:(NSString * _Nonnull)language;
- (void)skipToNextItemForPlayerViewController:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)skipToPreviousItemForPlayerViewController:(AVPlayerViewController * _Nonnull)playerViewController;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController skipToNextChannel:(void (^ _Nonnull)(BOOL))completion;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController skipToPreviousChannel:(void (^ _Nonnull)(BOOL))completion;
- (UIViewController * _Nonnull)nextChannelInterstitialViewControllerForPlayerViewController:(AVPlayerViewController * _Nonnull)playerViewController;
- (UIViewController * _Nonnull)previousChannelInterstitialViewControllerForPlayerViewController:(AVPlayerViewController * _Nonnull)playerViewController;
- (BOOL)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController shouldPresentContentProposal:(AVContentProposal * _Nonnull)proposal;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController didAcceptContentProposal:(AVContentProposal * _Nonnull)proposal;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController didRejectContentProposal:(AVContentProposal * _Nonnull)proposal;
- (void)playerViewController:(AVPlayerViewController * _Nonnull)playerViewController willTransitionToVisibilityOfTransportBar:(BOOL)visible withAnimationCoordinator:(id<AVPlayerViewControllerAnimationCoordinator>  _Nonnull)coordinator;
@end
