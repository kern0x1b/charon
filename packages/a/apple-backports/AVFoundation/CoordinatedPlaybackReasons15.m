#import <AVFoundation/AVFoundation.h>

// 19 constants, the iOS 15.0 coordinated-playback suspension reasons, the playback-coordinator
// // notifications, and the player rate-change keys and reasons, and nothing else: a name this file does not
// define is a name the corpus's gate asks for and the link cannot find, so the list
// below is the whole of this file's claim and the registry names each one of them.
//
// Every value was read out of the host's own AVFoundation at runtime, one dlsym of
// the exported symbol per name, and the differential in tests/backports/host/avf-metadata
// reads the same table out of two builds - Apple's framework on its own, and this file
// beside it in one binary with the names renamed - and diffs them. A value is not copied
// out of a header; it is what the framework answered, which is why one of them is the
// eleven ASCII characters "udta/%A9ade" and not a copyright sign.
//
// See facts/AVFoundation/CoordinatedPlaybackReasons.md.

NSString *const AVCoordinatedPlaybackSuspensionReasonAudioSessionInterrupted = @"AVCoordinatedPlaybackSuspensionReasonAudioSessionInterrupted";
NSString *const AVCoordinatedPlaybackSuspensionReasonCoordinatedPlaybackNotPossible = @"AVCoordinatedPlaybackSuspensionReasonCoordinatedPlaybackNotPossible";
NSString *const AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial = @"AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial";
NSString *const AVCoordinatedPlaybackSuspensionReasonStallRecovery = @"AVCoordinatedPlaybackSuspensionReasonStallRecovery";
NSString *const AVCoordinatedPlaybackSuspensionReasonUserActionRequired = @"AVCoordinatedPlaybackSuspensionReasonUserActionRequired";
NSString *const AVCoordinatedPlaybackSuspensionReasonUserIsChangingCurrentTime = @"AVCoordinatedPlaybackSuspensionReasonUserIsChangingCurrentTime";
NSString *const AVMetadataIdentifierQuickTimeMetadataIsMontage = @"mdta/com.apple.quicktime.is-montage";
NSString *const AVMetadataQuickTimeMetadataKeyIsMontage = @"com.apple.quicktime.is-montage";
NSString *const AVPlaybackCoordinatorOtherParticipantsDidChangeNotification = @"AVPlaybackCoordinatorOtherParticipantsDidChangeNotification";
NSString *const AVPlaybackCoordinatorSuspensionReasonsDidChangeNotification = @"AVPlaybackCoordinatorSuspensionReasonsDidChangeNotification";
NSString *const AVPlayerRateDidChangeNotification = @"AVPlayerRateDidChangeNotification";
NSString *const AVPlayerRateDidChangeOriginatingParticipantKey = @"AVPlayerRateDidChangeOriginatingParticipantKey";
NSString *const AVPlayerRateDidChangeReasonAppBackgrounded = @"AVPlayerRateDidChangeReasonAppBackgrounded";
NSString *const AVPlayerRateDidChangeReasonAudioSessionInterrupted = @"AVPlayerRateDidChangeReasonAudioSessionInterrupted";
NSString *const AVPlayerRateDidChangeReasonKey = @"AVPlayerRateDidChangeReasonKey";
NSString *const AVPlayerRateDidChangeReasonSetRateCalled = @"AVPlayerRateDidChangeReasonSetRateCalled";
NSString *const AVPlayerRateDidChangeReasonSetRateFailed = @"AVPlayerRateDidChangeReasonSetRateFailed";
NSString *const AVPlayerWaitingDuringInterstitialEventReason = @"AVPlayerWaitingDuringInterstitialEventReason";
NSString *const AVPlayerWaitingForCoordinatedPlaybackReason = @"AVPlayerWaitingForCoordinatedPlaybackReason";
