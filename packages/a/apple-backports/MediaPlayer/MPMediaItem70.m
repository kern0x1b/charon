// MPMediaItem's two track and disc numbers, the members this release does not have at all.
//
// Measured, not assumed: read from 6.1.3's own MediaPlayer with tools/mach32_methods.py, albumTrackNumber
// and discNumber are in none of the 236 classes' own instance lists and in none of the 41 categories -
// not on MPMediaItem (75 own methods), not on MPMediaEntity (18), not on MPConcreteMediaItem (29), the
// private class a real item's receiver is. The registry's rows said only "it arrived in iOS 7", which is a
// statement about the release and cannot tell a member Apple still declares from one it withdrew. The
// cache cross-check that owes the reader nothing: the selector strings exist in the cache, so this is a
// genuine gap and not a broken reading.
//
// Both are conveniences over the item's own property dictionary under the identically named key, which
// the release does have: valueForProperty: is an own method of MPMediaEntity at 6.1.3. So a port-created
// item answers both from what it was given, and a real item - whose receiver is MPConcreteMediaItem -
// answers whatever the release gives it, because a subclass's own method wins over a category on its
// public ancestor and this category adds nothing the release has.
//
// Split by introduced release, per band()'s own rule: this file holds the two the 26.2 header declares
// MP_API(ios(7.0)). The 8.0, 9.2, 10.0 and 10.3 members live in MPMediaItem80.m and after.

#import <Foundation/Foundation.h>
#if defined(CHARON_MEDIAPLAYER_STANDIN)
// The host contract check compiles this file with the stand-in in place of the framework, so it measures
// this code and not the Mac's own MediaPlayer - which declares albumTrackNumber already, and a category
// compiled against that would be measuring the host and would look like a clobber.
#import "MPMediaItemStandin.h"
#else
#import <MediaPlayer/MediaPlayer.h>
#endif

@interface MPMediaItem (Charon70)
@property (nonatomic, readonly) NSUInteger albumTrackNumber;
@property (nonatomic, readonly) NSUInteger discNumber;
@end

@implementation MPMediaItem (Charon70)

- (NSUInteger)albumTrackNumber {
    return [[self valueForProperty:@"albumTrackNumber"] unsignedIntegerValue];
}

- (NSUInteger)discNumber {
    return [[self valueForProperty:@"discNumber"] unsignedIntegerValue];
}

@end
