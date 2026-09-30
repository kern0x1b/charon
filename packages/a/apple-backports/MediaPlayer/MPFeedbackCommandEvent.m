// MPFeedbackCommandEvent, the 7.1 command event, and the one property its header declares.
//
// Carried, and for the same reason as its siblings: measured with tools/mach32_methods.py against the
// 6.1.3 cache, no class whose name holds 'CommandEvent' exists in any of its 236 classes and none of its
// 41 categories, with a nonsense selector absent as the control. A class the release does not have is new
// code and cannot shadow anything, so there is nothing native for it to be. `absent` is for a member
// whose answer needs hardware the device lacks, and none of this family needs any.
//
// THIS ONE IS NOT AN OPTIONAL EXTRA. The port already carries four public events whose public shape
// names this class as their ancestor - MPRatingCommandEvent, MPSkipIntervalCommandEvent,
// MPChangePlaybackRateCommandEvent and MPChangePlaybackPositionCommandEvent - and the corpus filed this
// row `absent` on the ground that "the class arrived in iOS 7.1". The release carrying nothing is true
// and is not the question. The question is what a caller writes:
//
//   [event isKindOfClass:[MPFeedbackCommandEvent class]]
//
// which answers NO for every event this port builds, where on the release that class exists and the
// event is one of its instances. The port's own header declares all four as MPRemoteCommandEvent, so
// the chain a caller walks has a link missing that Apple's own chain has. Carrying the class closes it.
//
// New code over the base MPRemoteCommandCenter71.m already carries. The header line it implements:
//
//   @property (nonatomic, readonly, getter = isNegative) BOOL negative;
//
// at MP_API(ios(7.1)). The getter= attribute means the SELECTOR is -isNegative and the property name is
// not a selector on any platform, so the port declares -isNegative and nothing named negative; the
// registry row is MPFeedbackCommandEvent.isNegative for the same reason MPMediaItem.isCompilation is
// (facts/MediaPlayer/MPMediaItem.md:61) - a property whose header writes a getter= is registered under
// the getter.
//
// Readwrite in the port where the header has it readonly, like every other event the port carries: an
// event the port builds has to be able to carry the feedback it is an event *about*, and a new class
// shadows nothing.

#import <Foundation/Foundation.h>
#if defined(CHARON_MEDIAPLAYER_STANDIN)
#import "MPMediaItemStandin.h"
#else
#import <MediaPlayer/MediaPlayer.h>
#endif

#if defined(CHARON_MEDIAPLAYER_STANDIN)
@interface MPFeedbackCommandEvent : MPRemoteCommandEvent
@property (nonatomic, assign, readwrite, getter = isNegative) BOOL negative;
@end
#else
// The SDK declares this class with its property readonly; the port's events have to be built carrying
// theirs, so it is made writable here, in an extension, and not declared a second time.
@interface MPFeedbackCommandEvent ()
@property (nonatomic, assign, readwrite, getter = isNegative) BOOL negative;
@end
#endif

@implementation MPFeedbackCommandEvent
@synthesize negative = _negative;

// The header's readonly accessor, written out rather than left to the synthesiser, so what a caller
// reads is the port's own code: removing the @synthesize is not a change of behaviour, because ARC then
// synthesises exactly the same accessor. NO is what an event that set nothing answers, and it is the
// value of BOOL's zero.
- (BOOL)isNegative {
    return _negative;
}

@end