#import <CoreMedia/CoreMedia.h>
#import <CoreFoundation/CoreFoundation.h>

#if !__has_include(<CoreMedia/CMTag.h>)
#import "CharonCMTag26.h"
#endif

// Nothing here is an API symbol: every name is charon_-prefixed, so the object that compiles
// CharonCMTagSupport.m exports none of it and the band machinery keeps it in every band.

BOOL charon_tag_equal(CMTag left, CMTag right);
BOOL charon_tag_is_less(CMTag left, CMTag right);
BOOL charon_tag_carries(const CMTag *held, CMItemCount heldCount, const CMTag *wanted, CMItemCount wantedCount);

// The collection's storage and its sorted search, so that a collection's tags can be handed to another
// object without either of them calling the other's API. The class sits here rather than in
// CMTagCollection17.m for exactly that reason; the public C functions stay there.
