# The coordinated-playback reasons, the playback-coordinator notifications, the player rate-change keys

19 constants, all of them iOS 15.0, in `packages/a/apple-backports/AVFoundation/CoordinatedPlaybackReasons15.m`.
None of them names a camera, a microphone or a media library: they are the strings one participant
hands another when a coordinated playback session suspends, the two notifications those participants
post, and the keys and reasons a player reports when its rate changes.

## How the values were read

The same measurement as [MetadataKeySpaces.md](MetadataKeySpaces.md), and the same differential: one
`dlsym` of the exported symbol in the host's own AVFoundation per name, printed as text and as
bytes, then the table read out of two builds - Apple's framework alone, and the port's file beside it
in one binary with the names renamed - and diffed. All 19 answered; the port's table is
byte-identical to the host's.

Worth naming because it is the sort of thing a header reading gets wrong by copying the *symbol* for
the *string*: **every one of these values is the symbol's own name.** `AVPlayerRateDidChangeReasonKey`
answers the eleven characters `AVPlayerRateDidChangeReasonKey`; so do the six reason constants and
the two `AVPlayerWaiting...` reasons. That is what the host answered for all 19 of them, and
it is a real answer rather than a placeholder: a participant compares the string it is handed against
these, and the port hands out the same bytes the framework does, so a comparison against the port's
constant and a comparison against Apple's agree.

The two notification names are the same shape, and are what `NSNotificationCenter` observers register
for. A program that observes `AVPlaybackCoordinatorSuspensionReasonsDidChangeNotification` on the
port and one that observes it on a modern device are therefore posting and observing the same name,
which is what makes a cross-release session possible at all.

## The values

| constant | value the host answered | bytes |
| --- | --- | --- |
| `AVCoordinatedPlaybackSuspensionReasonAudioSessionInterrupted` | "AVCoordinatedPlaybackSuspensionReasonAudioSessionInterrupted" | 60 |
| `AVCoordinatedPlaybackSuspensionReasonCoordinatedPlaybackNotPossible` | "AVCoordinatedPlaybackSuspensionReasonCoordinatedPlaybackNotPossible" | 67 |
| `AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial` | "AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial" | 56 |
| `AVCoordinatedPlaybackSuspensionReasonStallRecovery` | "AVCoordinatedPlaybackSuspensionReasonStallRecovery" | 50 |
| `AVCoordinatedPlaybackSuspensionReasonUserActionRequired` | "AVCoordinatedPlaybackSuspensionReasonUserActionRequired" | 55 |
| `AVCoordinatedPlaybackSuspensionReasonUserIsChangingCurrentTime` | "AVCoordinatedPlaybackSuspensionReasonUserIsChangingCurrentTime" | 62 |
| `AVMetadataIdentifierQuickTimeMetadataIsMontage` | "mdta/com.apple.quicktime.is-montage" | 35 |
| `AVMetadataQuickTimeMetadataKeyIsMontage` | "com.apple.quicktime.is-montage" | 30 |
| `AVPlaybackCoordinatorOtherParticipantsDidChangeNotification` | "AVPlaybackCoordinatorOtherParticipantsDidChangeNotification" | 59 |
| `AVPlaybackCoordinatorSuspensionReasonsDidChangeNotification` | "AVPlaybackCoordinatorSuspensionReasonsDidChangeNotification" | 59 |
| `AVPlayerRateDidChangeNotification` | "AVPlayerRateDidChangeNotification" | 33 |
| `AVPlayerRateDidChangeOriginatingParticipantKey` | "AVPlayerRateDidChangeOriginatingParticipantKey" | 46 |
| `AVPlayerRateDidChangeReasonAppBackgrounded` | "AVPlayerRateDidChangeReasonAppBackgrounded" | 42 |
| `AVPlayerRateDidChangeReasonAudioSessionInterrupted` | "AVPlayerRateDidChangeReasonAudioSessionInterrupted" | 50 |
| `AVPlayerRateDidChangeReasonKey` | "AVPlayerRateDidChangeReasonKey" | 30 |
| `AVPlayerRateDidChangeReasonSetRateCalled` | "AVPlayerRateDidChangeReasonSetRateCalled" | 40 |
| `AVPlayerRateDidChangeReasonSetRateFailed` | "AVPlayerRateDidChangeReasonSetRateFailed" | 40 |
| `AVPlayerWaitingDuringInterstitialEventReason` | "AVPlayerWaitingDuringInterstitialEventReason" | 44 |
| `AVPlayerWaitingForCoordinatedPlaybackReason` | "AVPlayerWaitingForCoordinatedPlaybackReason" | 43 |

## Reuse, and what was searched for first

The tree already carried `AVPlaybackCoordinatorOtherParticipantsDidChangeNotification`'s neighbours
from other families and the `AVAssetDownloadedAssetEvictionPriority*` pattern in
`AVFoundationConstants110.m`, which is the same shape of file. The only AVFoundation coordinated
playback work in the tree before this was `AVAudioSession+CategoryModeOptions.m` and
`AVCaptureSession+ApplicationAudioSession7.m`, which cover the audio-session reasons these suspension
reasons name; nothing here duplicates them, and the relationship is recorded in
[AVFoundationOwed.md](AVFoundationOwed.md), which also carries the rows of this family that are still
owed - the classes `AVPlaybackCoordinator`, `AVDelegatingPlaybackCoordinator` and their command
objects, which are objects with behaviour and not names, and so need an oracle of their own.
