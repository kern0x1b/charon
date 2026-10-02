// CharonCarPlayTemplate.h - the port's own Charon seams on the CarPlay classes of the 12.0 objects, for
// the later releases whose members reach them.
//
// A CarPlay class is one class with one @implementation, in the object of the release the class arrived
// in, and an object may hold API of exactly one release (modules/apple/backports.lua's releases_in, read
// by tools/release-split.lua). So CarPlayTemplates150.m, CarPlayListTemplate184.m and CarPlayGrid260.m
// each carry one later release's members of a class whose @implementation is CarPlayTemplatesView12.m,
// and a category cannot add an ivar. The storage is therefore the class's own and these accessors are how
// the later objects reach it - the same shape CarPlayNavigationSession154.m already uses for
// _turnCardColor through -charon_pauseWithReason:description:turnCardColor:, and the same one
// CharonCarPlayLane.h uses for CPLane's 18.0 half.
//
// They live in a header rather than being declared twice because a category that declares a method it
// does not implement warns, and the tree's own convention for exactly this is a Charon<Framework>.h per
// package. Every name here is Charon-prefixed, so none of it is API and none of it appears in any
// library's exports.
#ifndef CHARON_CARPLAY_TEMPLATE_H
#define CHARON_CARPLAY_TEMPLATE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import "CharonCarPlay260.h"

/// CPListSection's 15.0 initialiser, reached from CarPlayTemplates150.m.
///
/// CPListSection.h:82-97 declares header, headerSubtitle, headerImage, headerButton and sectionIndexTitle,
/// and the 12.0 initialiser CPListSection.h:34 already fills header and sectionIndexTitle. These three
/// are the ones left, because the header declares headerSubtitle and headerButton readonly while
/// headerImage is readwrite, so a category of ours cannot set the two read-only ones. The string copies,
/// which is what the header's own `copy` would do anyway; the image is `copy` and the button `strong` on
/// the header's own terms, and a nil in clears.
@interface CPListSection (CharonSectionHeader)

- (void)charon_setHeaderSubtitle:(NSString *)headerSubtitle;
- (void)charon_setHeaderImage:(UIImage *)headerImage;
- (void)charon_setHeaderButton:(CPButton *)headerButton;

@end

/// CPAlertAction's 16.0 colour, reached from CarPlayAlertAction160.m.
///
/// CPAlertAction.h:60 declares color `copy, readonly, nullable`, so a category of ours cannot set it and
/// the 16.0 colour overload needs this. It copies, which is the header's own `copy`.
@interface CPAlertAction (CharonAlertActionColor)

- (void)charon_setColor:(UIColor *)color;

@end

/// CPGridButton's 26.0 members' storage, reached from CarPlayGrid260.m.
///
/// CPGridButton.h:71 declares messageConfiguration `readonly, nullable`, so a category of ours cannot set
/// it and the 26.0 designated initialiser needs this. The configuration is held as given - the header
/// gives it no copy attribute - and the variants copy, per the header's own `copy` on titleVariants.
@interface CPGridButton (CharonGridButton26)

- (CPMessageGridItemConfiguration *)charon_messageConfiguration;
- (void)charon_setMessageConfiguration:(CPMessageGridItemConfiguration *)messageConfiguration;
- (void)charon_setTitleVariants:(NSArray<NSString *> *)titleVariants;

@end

@interface CPListTemplate (CharonListTemplateState)

/// The 18.4 member's storage, reached from CarPlayListTemplate184.m.
///
/// CPListTemplate.h:226 declares showsSpinnerWhileEmpty `assign`, and it is read by the class's own 12.0
/// drawing code - the empty state is where the spinner is - which is why it is an accessor on the class
/// and not a value the 18.4 object holds for itself.
- (BOOL)charon_showsSpinnerWhileEmpty;
- (void)charon_setShowsSpinnerWhileEmpty:(BOOL)showsSpinnerWhileEmpty;

/// The 26.0 members' storage, reached from CarPlayGrid260.m.
///
/// CPListTemplate.h:265 declares headerGridButtons `nullable, copy`, so the setter copies on the way in
/// and a nil in stays nil, which is what `nullable` means.
- (NSArray<CPGridButton *> *)charon_headerGridButtons;
- (void)charon_setHeaderGridButtons:(NSArray<CPGridButton *> *)headerGridButtons;

@end

#endif