#import <Foundation/Foundation.h>

// The iOS 8.0 band's MediaPlayer string constants, 1 of them, one object per release band.
//
// THE BAND IS THE TOOL S ANSWER, NOT THE CORPUS S. dyld.first_releases walked the release ladder symbol by
// symbol and this is the first rung that exports each of these; its answer is kept under $CHARON_HOME/cache
// as first-release-<hash>.tsv, and the whole table is quoted in the commit that introduced it. It disagreed
// with the corpus THREE times and the corpus lost all three: MPNowPlayingInfoCollectionIdentifier and the
// five MPNowPlayingInfoProperty* of that group are 10.0.1 and not 9.3, MPNowPlayingInfoPropertyAssetURL is
// 10.2 and not 10.3, and MPNowPlayingInfoPropertyCurrentPlaybackDate is 12.0 and not 11.1. One object
// carrying two of those would have mixed two releases' symbols, which is what release-split refuses.
//
// The value of every one was READ, never derived. Twelve of the eighteen hold their own symbol s name, which
// is a coincidence and not a rule: in the 9.0 band ten of thirteen were dotted public.* strings and one held
// the SINGULAR form of its name. A mutant per constant is what proves the comparison is live.
//
// iOS 6.1.3 exports NONE of the 36 MediaPlayer constants, read from that release s own armv7 cache, so the
// port carries all of them. They are plain data - a caller compares or passes a string.
//
// They are declared HERE, with the plain extern, and MediaPlayer.h is deliberately NOT imported: with -I on
// the port s own tree that import resolves to the PORT s shim rather than the SDK s.
//
// A constant is READ, never CALLED. Nothing here touches MPMediaLibrary, MPMediaQuery or a library.

extern NSString *const MPNowPlayingInfoPropertyDefaultPlaybackRate;

NSString *const MPNowPlayingInfoPropertyDefaultPlaybackRate = @"MPNowPlayingInfoPropertyDefaultPlaybackRate";

// MPMediaPlaylistPropertySeedItems, the second constant in this 8.0 object, and the one that key's
// accessor -seedItems is a convenience over (MPMediaPlaylist80.m).
//
// THE VALUE WAS READ, NOT DERIVED, and the reading is what this comment exists to record. The port's
// convention for these keys has been "the value is the property's own name", and that convention is FALSE
// for two keys in the tree beside it: MediaPlayerConstants.md:8-12 records that
// MPMediaPlaylistPropertyAuthorDisplayName is "externalVendorDisplayName" and
// MPMediaPlaylistPropertyDescriptionText is "descriptionInfo" - neither is the name of the constant nor of
// the property. A value spelled from this key's name would have been a guess dressed as a fact.
//
// Read from Apple's own framework, and the reader is shown live by printing those two known values in the
// same run (tests/backports/host/mediaplayeritem/seedkey.m, which links MediaPlayer and prints three values
// and a negative control):
//
//   MPMediaPlaylistPropertySeedItems          seedItems
//   MPMediaPlaylistPropertyAuthorDisplayName  externalVendorDisplayName
//   MPMediaPlaylistPropertyDescriptionText    descriptionInfo
//   MPMediaPlaylistPropertyAKeyNoFrameworkHas (nil)
//
// So for THIS key the convention happens to hold, and that is a fact about this key rather than a rule -
// which is the reason it had to be read at all. One key of the three holds its own name; the other two do
// not.
//
// It shadows nothing, and that was checked rather than assumed. MPMediaPlaylistPropertySeedItems is declared
// in MPMediaPlaylist.h with NO MP_API annotation, while the two 9.3 keys carry MP_API(ios(9.3)). An
// unannotated extern is unversioned, so the name is not something a later release introduced and this copy
// is not standing in for a 6.1.3 symbol that exists. 6.1.3 exports none of MediaPlayer's 36 constants, so
// the port carries it - as it carries the one above.

extern NSString *const MPMediaPlaylistPropertySeedItems;

NSString *const MPMediaPlaylistPropertySeedItems = @"seedItems";
