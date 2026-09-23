#import <MediaPlayer/MediaPlayer.h>

// Split from MPRemoteCommandCenter71.m by introduced release, per band()'s own rule: this file
// holds the classes the registry declares "introduced": "8.0" -
// MPChangePlaybackPositionCommandEvent, MPChangeRepeatModeCommand and MPChangeShuffleModeCommand.
// See MPRemoteCommandCenter71.m for the bridge and the classes that fire for real; nothing here
// is ever messaged by this port's own event bridge, since iOS 6's UIEventTypeRemoteControl has no
// repeat-mode, shuffle-mode or scrubbing subtype - these are real, addressable command/event
// objects with real storage, not fabricated ones.

@interface MPChangePlaybackPositionCommandEvent ()
@property (nonatomic, readwrite) NSTimeInterval positionTime;
@end

@implementation MPChangePlaybackPositionCommandEvent
@synthesize positionTime = _positionTime;
@end

@implementation MPChangeShuffleModeCommand
@synthesize currentShuffleType = _currentShuffleType;
@end

@implementation MPChangeRepeatModeCommand
@synthesize currentRepeatType = _currentRepeatType;
@end
