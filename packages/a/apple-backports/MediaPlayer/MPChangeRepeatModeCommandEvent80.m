// MPChangeRepeatModeCommandEvent, the 8.0 command event, and the two properties its header declares.
//
// Carried, and for the same reason as its 9.0 and 7.1 event siblings: measured with
// tools/mach32_methods.py against the 6.1.3 cache, no class whose name holds 'CommandEvent' exists in any
// of its 236 classes and none of its 41 categories, with a nonsense selector absent as the control; and
// every one of the 236 was read and none of them declares -repeatType or -preservesRepeatMode. Those two
// names are not the same question as the class: the release's whole-cache selector list
// (~/.charon/dyld/6.1.3/selectors_armv7.txt, 113981 distinct names) has one line for 'repeatType' and none
// for 'preservesRepeatMode', so 'repeatType' belongs to some other framework's class - the trap
// facts/MediaPlayer/MPMediaItem.md:105 records for albumTrackNumber, where a name in the per-cache list is
// necessary and not sufficient and the per-class read is what decides a member. A class the release does
// not have is new code and cannot shadow anything, so there is nothing native for it to be. `absent` is
// for a member whose answer needs hardware the device lacks, and none of this family needs any.
//
// The port already CARRIES the command that produces it - MPChangeRepeatModeCommand, introduced 8.0, in
// ios71remotecommand.json - and iOS 6's UIEventTypeRemoteControl has no repeat-mode subtype, so that
// command has never had an event to deliver. This is that event: without it the port's own command is an
// addressable object with no answer, which is what the corpus filed this row as. The port's bridge
// builds every command event lazily by class, so carrying the event is what makes the command reach a
// handler when one is set.
//
// New code over the base MPRemoteCommandCenter71.m already carries. The header lines it implements,
// quoted:
//
//   @property (nonatomic, readonly) MPRepeatType repeatType;
//   @property (nonatomic, readonly) BOOL preservesRepeatMode;
//
// at MP_API(ios(8.0)). Neither carries a getter=, so the property names are the selectors, and the
// registry row is MPChangeRepeatModeCommandEvent.repeatType beside the accessor.
//
// Readwrite in the port where the header has them readonly: an event the port builds has to be able to
// carry the mode it is an event *about*, and a new class shadows nothing.

#import <Foundation/Foundation.h>
#if defined(CHARON_MEDIAPLAYER_STANDIN)
#import "MPMediaItemStandin.h"
#else
#import <MediaPlayer/MediaPlayer.h>
#endif

#if defined(CHARON_MEDIAPLAYER_STANDIN)
@interface MPChangeRepeatModeCommandEvent : MPRemoteCommandEvent
@property (nonatomic, assign, readwrite) MPRepeatType repeatType;
@property (nonatomic, assign, readwrite) BOOL preservesRepeatMode;
@end
#else
// The SDK declares this class with its properties readonly; the port's events have to be built carrying
// theirs, so they are made writable here, in an extension, and not declared a second time.
@interface MPChangeRepeatModeCommandEvent ()
@property (nonatomic, assign, readwrite) MPRepeatType repeatType;
@property (nonatomic, assign, readwrite) BOOL preservesRepeatMode;
@end
#endif

@implementation MPChangeRepeatModeCommandEvent
@synthesize repeatType = _repeatType;
@synthesize preservesRepeatMode = _preservesRepeatMode;

// The header's readonly accessors, written out rather than left to the synthesiser, so what a caller
// reads is the port's own code and a mutation of it is a change of behaviour. NO is what an event that
// set nothing answers, and it is also the declared zero of BOOL. MPRepeatType has no "unknown" case -
// MPRemoteControlTypes.h:17 gives MPRepeatTypeOff, MPRepeatTypeOne, MPRepeatTypeAll - so an event that
// set nothing answers MPRepeatTypeOff, which is what "the user asked for no repeat" means, and a caller
// can tell "nothing was set" from "off was asked for" only by the event it was given.
- (MPRepeatType)repeatType {
    return _repeatType;
}

- (BOOL)preservesRepeatMode {
    return _preservesRepeatMode;
}

@end