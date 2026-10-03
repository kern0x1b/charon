// UIListSeparatorConfiguration145.m - the list separator configuration of iOS 14.5.
//
// ONE OBJECT, ONE RELEASE: every row here is 14.5.  It is its own .m because it is a class this object
// DEFINES; release-split.lua reads band points only, so a 14.5 method in a 14.0 or 15.0 file would pass it
// and only a reader would catch it.
//
// The declarations are the build SDK's own: the 16.4 SDK this package compiles against carries
// UIListSeparatorConfiguration.h, and it is byte for byte the 26.2 one after the comments and the
// availability macros are stripped.  Nothing is redeclared here.
//
// EVERY DEFAULT BELOW IS MEASURED, not read out of a header, and the header states none of them.  The
// oracle is the host's own UIKit under Mac Catalyst 27.0 (build 26A428), read by the probes in
// .agent-work/runs/b2/ and held to the port by the case in
// tests/backports/host/uikit2/listseparator_test.m; the numbers are in
// facts/UIKit/UIListSeparatorConfiguration145.md, M1.
//
// WHAT PRODUCES ONE: a UICollectionView list.  The port's own list cells draw their separators
// (UICollectionViewListCell.m, which takes charon_semantic_color(CharonSemanticColorSeparator)), so this
// class is the configuration those cells would be handed and what an application sets on a list's
// `separatorConfiguration`.  That is the whole of what it does here - it stores what it was given and
// answers it back - and the row says so rather than claiming the appearance model the host carries.

#import <UIKit/UIKit.h>
#import "CharonLists.h"

// Measured on the host (facts/UIKit/UIListSeparatorConfiguration145.md, M1): the colour of a separator on a
// list and the colour of that separator while several rows are selected are the SAME colour on a light
// interface - both resolve to 0 0 0 0.098, which is also what [UIColor separatorColor] resolves to there.
// The multiple-selection colour is a DYNAMIC colour on the host (a UIDynamicProviderColor, a block over the
// trait collection), so the port makes it a dynamic colour too, over the same role, rather than freezing
// one value that would be wrong in the other appearance.
//
// The two colour NAMES the host uses are 13.0 dynamic catalog entries with no name on 6.1.3 or 4.3, so the
// port reuses what this library already has for that role - charon_semantic_color, whose
// CharonSemanticColorSeparator row is the release's own separator colour measured against iOS and not
// against the Catalyst host.  That is reuse rather than a second copy, and the case compares the ROLE, not
// the name and not the four components, because neither the name nor the components are shared between the
// two releases.
static UIColor *charon_separator_colour(void)
{
    return charon_semantic_color(CharonSemanticColorSeparator);
}

static UIColor *charon_multiple_selection_separator_colour(void)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return charon_separator_colour();
    }];
}

@implementation UIListSeparatorConfiguration {
@private
    UICollectionLayoutListAppearance _listAppearance;
    UIListSeparatorVisibility _topVisibility;
    UIListSeparatorVisibility _bottomVisibility;
    NSDirectionalEdgeInsets _topInsets;
    NSDirectionalEdgeInsets _bottomInsets;
    UIColor *_color;
    UIColor *_multipleSelectionColor;
}

+ (BOOL)supportsSecureCoding
{
    // Measured: the class answers +supportsSecureCoding YES and a configuration archives through a
    // secure-coding archiver and reads back with every value - 4263 bytes for a plain one.
    return YES;
}

// The designated initialiser, and every value in it is measured:
//
//   the two visibilities are UIListSeparatorVisibilityAutomatic, which is 0;
//   both insets are UIListSeparatorAutomaticInsets, which is 0 top, CGFLOAT_MAX leading, 0 bottom,
//   CGFLOAT_MAX trailing - the release's own constant, already implemented (registry/UIKit/
//   uikit-constants.json), and NOT a zero: an automatic inset is what tells the list to compute it;
//   the colour is the separator colour and the multiple-selection colour is that same role as a dynamic
//   colour.
//
// Measured over ALL FIVE UICollectionLayoutListAppearance values - plain, grouped, inset grouped, sidebar
// and sidebar plain - and they are the same for every one of them, which is why the appearance is stored
// and nothing is switched on it.  The host does raise for an appearance it does not know
// ("UICollectionView internal inconsistency: unknown list appearance style"), and the port does not
// reproduce that refusal: it has no list-appearance model to be inconsistent with, and a refusal the port
// could only fake would be a refusal nobody measured.
- (instancetype)initWithListAppearance:(UICollectionLayoutListAppearance)listAppearance
{
    if ((self = [super init])) {
        _listAppearance = listAppearance;
        _topVisibility = UIListSeparatorVisibilityAutomatic;
        _bottomVisibility = UIListSeparatorVisibilityAutomatic;
        _topInsets = UIListSeparatorAutomaticInsets;
        _bottomInsets = UIListSeparatorAutomaticInsets;
        _color = charon_separator_colour();
        _multipleSelectionColor = charon_multiple_selection_separator_colour();
    }
    return self;
}

// -init and +new are NS_UNAVAILABLE in the SDK's header: a separator configuration without an appearance
// has no defaults to apply.  The port cannot remove NSObject's two, and MEASURED, the host's answer rather
// than refusing - and what they answer is NOT the initialiser's shape.  Measured:
//
//   +new: topVis=0 bottomVis=0 color=(nil) msc=(nil)
//     +new topInsets = 0 0 0 0
//     +new bottomInsets = 0 0 0 0
//   -init: topVis=0 bottomVis=0 color=(nil)
//     -init topInsets = 0 0 0 0
//
// Every value is the zero of its type - the two visibilities' zero happens to be Automatic - and in
// particular the insets are ZERO where the initialiser gives the automatic ones, and both colours are nil.
// The port answers exactly that.  The difference between the two paths is in the code and not in this
// comment: -initWithListAppearance: above writes every field, and -init below writes none of them, so
// [super init] is the whole of it and an object built this way reads back every zero.
- (instancetype)init
{
    return [super init];
}

+ (instancetype)new
{
    // [[self alloc] init], not [self init]: inside a class method `self` is the class object and sending
    // -init to a class raises "cannot init a class object".
    return [[self alloc] init];
}

- (UIListSeparatorVisibility)topSeparatorVisibility { return _topVisibility; }
- (void)setTopSeparatorVisibility:(UIListSeparatorVisibility)visibility { _topVisibility = visibility; }
- (UIListSeparatorVisibility)bottomSeparatorVisibility { return _bottomVisibility; }
- (void)setBottomSeparatorVisibility:(UIListSeparatorVisibility)visibility { _bottomVisibility = visibility; }
- (NSDirectionalEdgeInsets)topSeparatorInsets { return _topInsets; }
- (void)setTopSeparatorInsets:(NSDirectionalEdgeInsets)insets { _topInsets = insets; }
- (NSDirectionalEdgeInsets)bottomSeparatorInsets { return _bottomInsets; }
- (void)setBottomSeparatorInsets:(NSDirectionalEdgeInsets)insets { _bottomInsets = insets; }
- (UIColor *)color { return _color; }
- (void)setColor:(UIColor *)color { _color = color; }
- (UIColor *)multipleSelectionColor { return _multipleSelectionColor; }
- (void)setMultipleSelectionColor:(UIColor *)color { _multipleSelectionColor = color; }

- (id)copyWithZone:(NSZone *)zone
{
    // Measured: the host's copy is a DIFFERENT object (not self), holds every written value, and holds the
    // same colour INSTANCE the receiver does.  Built through the designated initialiser so the defaults come
    // from one place, then every property is written from the receiver.
    UIListSeparatorConfiguration *copy = [[UIListSeparatorConfiguration allocWithZone:zone] initWithListAppearance:_listAppearance];
    copy.topSeparatorVisibility = _topVisibility;
    copy.bottomSeparatorVisibility = _bottomVisibility;
    copy.topSeparatorInsets = _topInsets;
    copy.bottomSeparatorInsets = _bottomInsets;
    copy.color = _color;
    copy.multipleSelectionColor = _multipleSelectionColor;
    return copy;
}

// -isEqual: and -hash are NOT defined here, and that is a measurement rather than an omission.  The
// header declares neither, so neither is a row - and what the host answers is not a value equality either:
// two fresh configurations from the same appearance ARE equal, and two configurations both written alike
// are NOT ("two written alike isEqual=0").  So the host's isEqual: is comparing something this port has no
// measurement for, and defining a value equality here would be inventing an answer the release does not
// give.  NSObject's identity semantics stand, and the case asks the port and the host the same two
// questions rather than asking them to agree.

// The keys are the host's own, read out of the host's archive plist (facts/UIKit/
// UIListSeparatorConfiguration145.md, M1c): topSepVisibility, bottomSepVisibility, topSepInsets, insets -
// which is the BOTTOM separator's insets, the top one having its own key - color and multiSelectColor.
//
// What the host's archive does NOT carry, measured, is the list appearance: the plist has no key for it.
// So neither does this, and that is not an omission either - an archive read back here gets the six values
// above and the appearance it was built with is gone, which is what the host's own archive does.
//
// `visualEffect` is in the host's plist and is a 15.0 property whose row is `absent` on this port, so it
// is not written: an archive that carried a key nothing here can answer would claim API this library has no
// row for.
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_topVisibility forKey:@"topSepVisibility"];
    [coder encodeInteger:_bottomVisibility forKey:@"bottomSepVisibility"];
    [coder encodeObject:[NSValue valueWithBytes:&_topInsets objCType:@encode(NSDirectionalEdgeInsets)]
                forKey:@"topSepInsets"];
    [coder encodeObject:[NSValue valueWithBytes:&_bottomInsets objCType:@encode(NSDirectionalEdgeInsets)]
                forKey:@"insets"];
    [coder encodeObject:_color forKey:@"color"];
    [coder encodeObject:_multipleSelectionColor forKey:@"multiSelectColor"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    // The decoded object gets the same defaults the designated initialiser would give and then every value
    // the archive holds, so a configuration read back has the six measured values whatever the archive
    // said, and the appearance stays at the zero - which is what the host's own archive gives, since it
    // carries none.
    if ((self = [self initWithListAppearance:(UICollectionLayoutListAppearance)0])) {
        _topVisibility = (UIListSeparatorVisibility)[coder decodeIntegerForKey:@"topSepVisibility"];
        _bottomVisibility = (UIListSeparatorVisibility)[coder decodeIntegerForKey:@"bottomSepVisibility"];
        NSValue *top = [coder decodeObjectOfClass:[NSValue class] forKey:@"topSepInsets"];
        if (top)
            [top getValue:&_topInsets];
        NSValue *bottom = [coder decodeObjectOfClass:[NSValue class] forKey:@"insets"];
        if (bottom)
            [bottom getValue:&_bottomInsets];
        UIColor *color = [coder decodeObjectOfClass:[UIColor class] forKey:@"color"];
        if (color)
            _color = color;
        UIColor *multiple = [coder decodeObjectOfClass:[UIColor class] forKey:@"multiSelectColor"];
        if (multiple)
            _multipleSelectionColor = multiple;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<UIListSeparatorConfiguration %p visibility: {top: %ld, bottom: %ld}, bottom insets: {l: %g, t: %g}>",
                                      self, (long)_topVisibility, (long)_bottomVisibility,
                                      (double)_bottomInsets.leading, (double)_bottomInsets.top];
}

@end