// The two 10.0 members of HMAccessory that say where the accessory is: the home it belongs to, and the
// camera profiles it publishes.
//
// One object per release: this file is of 10.0 alone, and both members are declared on the 8.0 class.
//
// **HMAccessory.home.** The 26.2 header, HMAccessory.h:37:
//   @property (nullable, nonatomic, readonly, weak) HMHome *home
//       API_AVAILABLE(ios(10.0), watchos(3.0), tvos(10.0), macCatalyst(14.0)) API_UNAVAILABLE(macos);
// nullable, weak, readonly, and of 10.0. The port's accessory already carries the identifier of the home
// it belongs to - charon_homeIdentifier, the same field the home graph's own entry points are given - so
// the answer is that home, materialised by the graph's own CharonHomeKitHome(identifier). There is no
// second way to reach a home in this library, and nothing is invented: an accessory with no home
// identifier answers nil, which is what nullable allows.
//
// **HMAccessory.cameraProfiles is not here, and the reason is a type, not a choice.** The header
// declares it in HMAccessory+Camera.h:28:
//   @property (nullable, nonatomic, readonly, copy) NSArray<HMCameraProfile *> *cameraProfiles
//       API_AVAILABLE(ios(10.0), ...) API_UNAVAILABLE(macos);
// The type names HMCameraProfile, which this port does not carry yet, so an accessor for it could not be
// written: the element type of the answer would not exist. It comes with its type. Until then the property
// is not answered, and a caller asking this port for camera profiles is answered by -respondsToSelector:,
// which is the honest answer for a member this library does not carry. It is not marked absent in the
// registry, because absent means the release does not export it and the release does: see
// facts/HomeKit/HMAccessory.md.

#import "CharonHomeKitInternal.h"

@implementation HMAccessory

// The header's own word for the home: nullable, so an accessory that belongs to no home answers nil, and
// the one that does is the home its own identifier names, built by the graph's entry point rather than
// a second construction of a home.
- (HMHome *)home
{
    NSString *homeIdentifier = self.charon_homeIdentifier;
    if (!homeIdentifier.length)
        return nil;
    return CharonHomeKitHome(homeIdentifier);
}

@end
