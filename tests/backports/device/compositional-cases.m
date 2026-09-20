#import "compositional-cases.h"

static CompositionalKit K;

@interface CompositionalCell : UICollectionViewCell
@end

@implementation CompositionalCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes
{
    return attributes;
}
@end

@interface CompositionalSupplement : UICollectionReusableView
@end

@implementation CompositionalSupplement
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes
{
    return attributes;
}
@end

@interface CompositionalSource : NSObject <UICollectionViewDataSource>
@property (nonatomic, strong) NSArray *counts;
@end

@implementation CompositionalSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)view
{
    return (NSInteger)self.counts.count;
}
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section
{
    return [self.counts[(NSUInteger)section] integerValue];
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [view dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:indexPath];
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)view viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    return [view dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"s" forIndexPath:indexPath];
}
@end

CompositionalKit compositional_kit(NSString *prefix)
{
    Class (^named)(NSString *) = ^Class(NSString *name) { return NSClassFromString([prefix stringByAppendingString:name]); };
    CompositionalKit kit = {named(@"NSCollectionLayoutDimension"), named(@"NSCollectionLayoutSize"), named(@"NSCollectionLayoutSpacing"), named(@"NSCollectionLayoutEdgeSpacing"),
                            named(@"NSCollectionLayoutAnchor"), named(@"NSCollectionLayoutItem"), named(@"NSCollectionLayoutGroup"), named(@"NSCollectionLayoutGroupCustomItem"),
                            named(@"NSCollectionLayoutSupplementaryItem"), named(@"NSCollectionLayoutBoundarySupplementaryItem"), named(@"NSCollectionLayoutDecorationItem"),
                            named(@"NSCollectionLayoutSection"), named(@"UICollectionViewCompositionalLayoutConfiguration"), named(@"UICollectionViewCompositionalLayout")};
    return kit;
}

static NSCollectionLayoutDimension *FW(double value) { return [(id)K.dimension fractionalWidthDimension:value]; }
static NSCollectionLayoutDimension *FH(double value) { return [(id)K.dimension fractionalHeightDimension:value]; }
static NSCollectionLayoutDimension *AB(double value) { return [(id)K.dimension absoluteDimension:value]; }
static NSCollectionLayoutDimension *ES(double value) { return [(id)K.dimension estimatedDimension:value]; }
static NSCollectionLayoutSize *SZ(NSCollectionLayoutDimension *width, NSCollectionLayoutDimension *height) { return [(id)K.size sizeWithWidthDimension:width heightDimension:height]; }
static NSCollectionLayoutItem *IT(NSCollectionLayoutDimension *width, NSCollectionLayoutDimension *height) { return [(id)K.item itemWithLayoutSize:SZ(width, height)]; }
static NSCollectionLayoutSpacing *FIXED(double value) { return [(id)K.spacing fixedSpacing:value]; }
static NSCollectionLayoutSpacing *FLEX(double value) { return [(id)K.spacing flexibleSpacing:value]; }
static NSCollectionLayoutEdgeSpacing *EDGES(NSCollectionLayoutSpacing *l, NSCollectionLayoutSpacing *t, NSCollectionLayoutSpacing *r, NSCollectionLayoutSpacing *b)
{
    return [(id)K.edgeSpacing spacingForLeading:l top:t trailing:r bottom:b];
}
static NSCollectionLayoutGroup *HG(NSCollectionLayoutDimension *w, NSCollectionLayoutDimension *h, NSArray *items)
{
    return [(id)K.group horizontalGroupWithLayoutSize:SZ(w, h) subitems:items];
}
static NSCollectionLayoutGroup *VG(NSCollectionLayoutDimension *w, NSCollectionLayoutDimension *h, NSArray *items)
{
    return [(id)K.group verticalGroupWithLayoutSize:SZ(w, h) subitems:items];
}
static NSCollectionLayoutSection *SEC(NSCollectionLayoutGroup *group) { return [(id)K.section sectionWithGroup:group]; }
static NSCollectionLayoutBoundarySupplementaryItem *BND(NSString *kind, NSCollectionLayoutDimension *w, NSCollectionLayoutDimension *h, NSRectAlignment alignment, double ox, double oy,
                                                        BOOL extends, BOOL pin)
{
    NSCollectionLayoutBoundarySupplementaryItem *item = [(id)K.boundary boundarySupplementaryItemWithLayoutSize:SZ(w, h) elementKind:kind alignment:alignment absoluteOffset:CGPointMake(ox, oy)];
    item.extendsBoundary = extends;
    item.pinToVisibleBounds = pin;
    return item;
}
static NSCollectionLayoutSupplementaryItem *SUP(NSString *kind, NSCollectionLayoutDimension *w, NSCollectionLayoutDimension *h, NSCollectionLayoutAnchor *container, NSCollectionLayoutAnchor *item)
{
    return item ? [(id)K.supplementary supplementaryItemWithLayoutSize:SZ(w, h) elementKind:kind containerAnchor:container itemAnchor:item]
                : [(id)K.supplementary supplementaryItemWithLayoutSize:SZ(w, h) elementKind:kind containerAnchor:container];
}
static NSCollectionLayoutAnchor *ANCHOR(NSDirectionalRectEdge edges) { return [(id)K.anchor layoutAnchorWithEdges:edges]; }
static NSCollectionLayoutAnchor *ANCHOR_ABS(NSDirectionalRectEdge edges, double x, double y) { return [(id)K.anchor layoutAnchorWithEdges:edges absoluteOffset:CGPointMake(x, y)]; }
static NSCollectionLayoutAnchor *ANCHOR_FRAC(NSDirectionalRectEdge edges, double x, double y) { return [(id)K.anchor layoutAnchorWithEdges:edges fractionalOffset:CGPointMake(x, y)]; }
static UICollectionViewCompositionalLayoutConfiguration *CFG(UICollectionViewScrollDirection direction, double spacing, NSArray *items)
{
    UICollectionViewCompositionalLayoutConfiguration *configuration = [[(id)K.configuration alloc] init];
    configuration.scrollDirection = direction;
    configuration.interSectionSpacing = spacing;
    if (items)
        configuration.boundarySupplementaryItems = items;
    return configuration;
}
static UICollectionViewLayout *LAYOUT(NSCollectionLayoutSection *section, UICollectionViewCompositionalLayoutConfiguration *configuration)
{
    return configuration ? [[(id)K.layout alloc] initWithSection:section configuration:configuration] : [[(id)K.layout alloc] initWithSection:section];
}
static NSDirectionalEdgeInsets EI(double t, double l, double b, double r) { return NSDirectionalEdgeInsetsMake(t, l, b, r); }

@implementation CompositionalCase
@end

static CompositionalCase *make(UICollectionViewLayout *layout, NSArray *counts, NSArray *kinds, NSArray *decorations, CGSize size)
{
    CompositionalCase *built = [[CompositionalCase alloc] init];
    built.layout = layout;
    built.counts = counts;
    built.kinds = kinds;
    built.decorations = decorations;
    built.size = size;
    return built;
}

static const UICollectionViewScrollDirection VERTICAL = UICollectionViewScrollDirectionVertical, HORIZONTAL = UICollectionViewScrollDirectionHorizontal;
static const CGSize PHONE = {320, 480};

typedef CompositionalCase *(^CompositionalBuilder)(void);

static NSString *spacing_name(int mode)
{
    return mode == 0 ? @"no spacing" : mode == 1 ? @"fixed 10" : mode == 2 ? @"flexible 10" : @"flexible 1";
}

static NSCollectionLayoutSpacing *spacing_for(int mode)
{
    return mode == 0 ? nil : mode == 1 ? FIXED(10) : mode == 2 ? FLEX(10) : FLEX(1);
}

static NSArray *builders(NSMutableArray *names)
{
    NSMutableArray *list = [NSMutableArray array];
    void (^add)(NSString *, CompositionalBuilder) = ^(NSString *name, CompositionalBuilder builder) {
        [names addObject:name];
        [list addObject:[builder copy]];
    };
    for (int mode = 0; mode < 4; mode++) {
        for (NSNumber *fraction in @[@0.3, @0.25, @0.5, @(1.0 / 3), @0.4, @0.9]) {
            add([NSString stringWithFormat:@"row of %g, %@", fraction.doubleValue, spacing_name(mode)], ^{
                NSCollectionLayoutGroup *group = HG(FW(1), AB(10), @[IT(FW(fraction.doubleValue), AB(10))]);
                group.interItemSpacing = spacing_for(mode);
                return make(LAYOUT(SEC(group), nil), @[@8], @[], @[], PHONE);
            });
        }
    }
    for (NSNumber *width in @[@301, @300, @280]) {
        add([NSString stringWithFormat:@"thirds in %@ points", width], ^{
            return make(LAYOUT(SEC(HG(FW(1), AB(20), @[IT(FW(1.0 / 3), FH(1))])), nil), @[@7], @[], @[], CGSizeMake(width.doubleValue, 480));
        });
    }
    add(@"mixed fractional and absolute", ^{
        NSCollectionLayoutGroup *group = HG(FW(1), AB(20), @[IT(FW(0.5), FH(1)), IT(AB(50), FH(1))]);
        group.interItemSpacing = FIXED(10);
        return make(LAYOUT(SEC(group), nil), @[@6], @[], @[], PHONE);
    });
    add(@"two fractional items in a row", ^{
        return make(LAYOUT(SEC(HG(FW(1), AB(20), @[IT(FW(0.5), FH(1)), IT(FW(0.25), FH(1))])), nil), @[@8], @[], @[], PHONE);
    });
    add(@"absolute items with flexible spacing", ^{
        NSCollectionLayoutGroup *group = HG(FW(1), AB(20), @[IT(AB(100), FH(1))]);
        group.interItemSpacing = FLEX(4);
        return make(LAYOUT(SEC(group), nil), @[@8], @[], @[], PHONE);
    });
    add(@"item taller and shorter than its row", ^{
        NSCollectionLayoutGroup *group = HG(FW(1), AB(20), @[IT(FW(0.5), AB(100)), IT(FW(0.5), FW(0.25))]);
        group.interItemSpacing = FIXED(10);
        return make(LAYOUT(SEC(group), nil), @[@4], @[], @[], PHONE);
    });
    add(@"group height a fraction of the width", ^{
        return make(LAYOUT(SEC(HG(FW(1), FW(0.2), @[IT(FW(0.5), FH(1))])), nil), @[@4], @[], @[], PHONE);
    });
    add(@"group height half the container", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), FH(0.5), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(10, 20, 30, 40);
        return make(LAYOUT(section, nil), @[@4], @[], @[], PHONE);
    });
    add(@"vertical group with fractional heights", ^{
        NSCollectionLayoutGroup *group = VG(FW(1), AB(100), @[IT(FW(1), FH(0.25))]);
        return make(LAYOUT(SEC(group), nil), @[@9], @[], @[], PHONE);
    });
    add(@"vertical group with fixed spacing", ^{
        NSCollectionLayoutGroup *group = VG(FW(1), AB(100), @[IT(FW(1), FH(0.25))]);
        group.interItemSpacing = FIXED(10);
        return make(LAYOUT(SEC(group), nil), @[@9], @[], @[], PHONE);
    });
    add(@"half sized vertical group", ^{
        NSCollectionLayoutGroup *group = VG(FW(0.5), FH(0.5), @[IT(FW(1), FH(0.3))]);
        group.interItemSpacing = FIXED(10);
        return make(LAYOUT(SEC(group), nil), @[@9], @[], @[], PHONE);
    });
    for (int mode = 0; mode < 3; mode++) {
        NSString *label = spacing_name(mode == 0 ? 0 : mode == 1 ? 1 : 2);
        add([NSString stringWithFormat:@"partly filled last group, %@", label], ^{
            NSCollectionLayoutGroup *group = VG(FW(1), AB(100), @[IT(FW(1), AB(30))]);
            group.interItemSpacing = spacing_for(mode == 0 ? 0 : mode == 1 ? 1 : 2);
            return make(LAYOUT(SEC(group), nil), @[@5], @[], @[], PHONE);
        });
        add([NSString stringWithFormat:@"partly filled horizontal scroll, %@", label], ^{
            NSCollectionLayoutGroup *group = HG(AB(100), FH(1), @[IT(AB(30), FH(1))]);
            group.interItemSpacing = spacing_for(mode == 0 ? 0 : mode == 1 ? 1 : 2);
            return make(LAYOUT(SEC(group), CFG(HORIZONTAL, 0, nil)), @[@5, @3], @[], @[], PHONE);
        });
    }
    add(@"repeated item", ^{
        NSCollectionLayoutGroup *group = [(id)K.group horizontalGroupWithLayoutSize:SZ(FW(1), AB(20)) subitem:IT(AB(30), FH(1)) count:3];
        group.interItemSpacing = FIXED(10);
        return make(LAYOUT(SEC(group), nil), @[@7], @[], @[], PHONE);
    });
    add(@"repeated item vertically", ^{
        NSCollectionLayoutGroup *group = [(id)K.group verticalGroupWithLayoutSize:SZ(FW(0.5), AB(90)) subitem:IT(FW(1), FH(0.1)) count:3];
        return make(LAYOUT(SEC(group), nil), @[@7], @[], @[], PHONE);
    });
    add(@"section insets and group spacing", ^{
        NSCollectionLayoutGroup *group = HG(FW(1), AB(50), @[IT(FW(1.0 / 3), FH(1))]);
        group.interItemSpacing = FIXED(10);
        NSCollectionLayoutSection *section = SEC(group);
        section.interGroupSpacing = 4;
        section.contentInsets = EI(5, 6, 7, 8);
        return make(LAYOUT(section, nil), @[@7], @[], @[], PHONE);
    });
    add(@"group and item insets", ^{
        NSCollectionLayoutItem *item = IT(FW(0.5), FH(1));
        item.contentInsets = EI(5, 6, 7, 8);
        NSCollectionLayoutGroup *group = HG(FW(1), AB(100), @[item]);
        group.contentInsets = EI(1, 2, 3, 4);
        return make(LAYOUT(SEC(group), nil), @[@4], @[], @[], PHONE);
    });
    add(@"item edge spacing fixed", ^{
        NSCollectionLayoutItem *item = IT(FW(0.5), FH(1));
        item.edgeSpacing = EDGES(FIXED(4), FIXED(5), FIXED(6), FIXED(7));
        return make(LAYOUT(SEC(HG(FW(1), AB(100), @[item])), nil), @[@4], @[], @[], PHONE);
    });
    add(@"item edge spacing flexible", ^{
        NSCollectionLayoutItem *item = IT(FW(0.5), FH(1));
        item.edgeSpacing = EDGES(FLEX(4), nil, FLEX(6), FLEX(7));
        return make(LAYOUT(SEC(HG(FW(1), AB(100), @[item])), nil), @[@4], @[], @[], PHONE);
    });
    add(@"item edge spacing flexible at the start", ^{
        NSCollectionLayoutItem *item = IT(FW(0.4), FH(0.5));
        item.edgeSpacing = EDGES(FLEX(0), FLEX(0), nil, nil);
        return make(LAYOUT(SEC(HG(FW(1), AB(100), @[item])), nil), @[@4], @[], @[], PHONE);
    });
    add(@"group edge spacing and group spacing", ^{
        NSCollectionLayoutGroup *group = HG(FW(1), AB(30), @[IT(FW(0.5), FH(1))]);
        group.edgeSpacing = EDGES(FIXED(4), FIXED(5), FIXED(6), FIXED(7));
        NSCollectionLayoutSection *section = SEC(group);
        section.interGroupSpacing = 8;
        return make(LAYOUT(section, nil), @[@5], @[], @[], PHONE);
    });
    add(@"narrow group", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(0.6), AB(30), @[IT(FW(0.5), FH(1))]));
        section.interGroupSpacing = 8;
        return make(LAYOUT(section, nil), @[@5], @[], @[], PHONE);
    });
    add(@"three sections", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(30), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        return make(LAYOUT(section, CFG(VERTICAL, 12, nil)), @[@3, @0, @4], @[], @[], PHONE);
    });
    add(@"scrolling sideways", ^{
        NSCollectionLayoutSection *section = SEC(VG(AB(100), FH(1), @[IT(FW(1), FH(0.25))]));
        section.interGroupSpacing = 5;
        section.contentInsets = EI(3, 4, 5, 6);
        return make(LAYOUT(section, CFG(HORIZONTAL, 12, nil)), @[@6, @5], @[], @[], PHONE);
    });
    add(@"scrolling sideways with a group of half the width", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(0.5), FH(1), @[IT(FW(1), FH(0.25))]));
        section.contentInsets = EI(3, 4, 5, 6);
        return make(LAYOUT(section, CFG(HORIZONTAL, 0, nil)), @[@5], @[], @[], PHONE);
    });
    add(@"nested groups", ^{
        NSCollectionLayoutGroup *inner = VG(FW(0.5), FH(1), @[IT(FW(1), FH(0.5))]);
        inner.interItemSpacing = FIXED(4);
        NSCollectionLayoutGroup *group = HG(FW(1), AB(100), @[IT(FW(0.5), FH(1)), inner]);
        group.interItemSpacing = FIXED(6);
        return make(LAYOUT(SEC(group), nil), @[@9], @[], @[], PHONE);
    });
    add(@"nested group repeated", ^{
        NSCollectionLayoutGroup *inner = VG(FW(0.5), FH(1), @[IT(FW(1), FH(0.5))]);
        return make(LAYOUT(SEC(HG(FW(1), AB(100), @[inner])), nil), @[@9], @[], @[], PHONE);
    });
    add(@"estimated sizes", ^{
        return make(LAYOUT(SEC(HG(FW(1), ES(44), @[IT(FW(0.5), ES(30))])), nil), @[@4], @[], @[], PHONE);
    });
    add(@"estimated group height", ^{
        return make(LAYOUT(SEC(HG(FW(1), ES(44), @[IT(FW(0.5), FH(1))])), nil), @[@4], @[], @[], PHONE);
    });
    add(@"estimated width", ^{
        return make(LAYOUT(SEC(HG(FW(1), AB(44), @[IT(ES(100), FH(1))])), nil), @[@5], @[], @[], PHONE);
    });
    add(@"estimated heights in a vertical group", ^{
        return make(LAYOUT(SEC(VG(FW(1), AB(100), @[IT(FW(1), ES(30))])), nil), @[@5], @[], @[], PHONE);
    });
    add(@"custom group", ^{
        NSCollectionLayoutGroup *group = [(id)K.group customGroupWithLayoutSize:SZ(FW(1), AB(80)) itemProvider:^NSArray *(id environment) {
            return @[[(id)K.customItem customItemWithFrame:CGRectMake(1, 2, 30, 40)], [(id)K.customItem customItemWithFrame:CGRectMake(50, 10, 60, 30) zIndex:4],
                     [(id)K.customItem customItemWithFrame:CGRectMake(-5, -5, 400, 20)]];
        }];
        NSCollectionLayoutSection *section = SEC(group);
        section.contentInsets = EI(3, 4, 5, 6);
        return make(LAYOUT(section, nil), @[@4, @2], @[], @[], PHONE);
    });
    add(@"section provider", ^{
        UICollectionViewLayout *layout = [[(id)K.layout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger index, id environment) {
            NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5) , FH(1))]));
            section.contentInsets = index == 1 ? EI(0, 0, 0, 0) : EI(3, 4, 5, 6);
            return section;
        }];
        return make(layout, @[@3, @4, @2], @[], @[], PHONE);
    });
    add(@"section provider by container size", ^{
        UICollectionViewLayout *layout = [[(id)K.layout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger index, id<NSCollectionLayoutEnvironment> environment) {
            CGFloat width = environment.container.effectiveContentSize.width;
            return SEC(HG(FW(1), AB(30), @[IT(width > 250 ? FW(0.25) : FW(0.5), FH(1))]));
        }];
        return make(layout, @[@5, @3], @[], @[], CGSizeMake(200, 300));
    });
    NSRectAlignment alignments[] = {NSRectAlignmentTop, NSRectAlignmentBottom, NSRectAlignmentLeading, NSRectAlignmentTrailing, NSRectAlignmentTopLeading, NSRectAlignmentTopTrailing,
                                    NSRectAlignmentBottomLeading, NSRectAlignmentBottomTrailing};
    for (int index = 0; index < 8; index++) {
        NSRectAlignment alignment = alignments[index];
        for (int direction = 0; direction < 2; direction++) {
            for (int follow = 0; follow < 2; follow++) {
                add([NSString stringWithFormat:@"boundary item alignment %ld, %@, %@", (long)alignment, direction ? @"sideways" : @"down", follow ? @"following insets" : @"whole width"], ^{
                    NSCollectionLayoutGroup *group = direction ? HG(AB(100), FH(1), @[IT(FW(0.5), FH(1))]) : HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]);
                    NSCollectionLayoutSection *section = SEC(group);
                    section.contentInsets = EI(3, 4, 5, 6);
                    section.supplementariesFollowContentInsets = follow;
                    section.boundarySupplementaryItems = @[BND(@"h", AB(60), AB(30), alignment, 0, 0, YES, NO)];
                    return make(LAYOUT(section, CFG(direction ? HORIZONTAL : VERTICAL, 0, nil)), @[@3, @2], @[@"h"], @[], PHONE);
                });
            }
        }
        add([NSString stringWithFormat:@"boundary item alignment %ld with an offset, extending or not", (long)alignment], ^{
            NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
            section.contentInsets = EI(3, 4, 5, 6);
            section.boundarySupplementaryItems = @[BND(@"h", AB(60), AB(30), alignment, 5, 7, YES, NO)];
            NSCollectionLayoutSection *plain = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
            plain.contentInsets = EI(3, 4, 5, 6);
            plain.boundarySupplementaryItems = @[BND(@"h", AB(60), AB(30), alignment, -5, -7, NO, NO)];
            return make(LAYOUT(index % 2 ? plain : section, nil), @[@3, @2], @[@"h"], @[], PHONE);
        });
    }
    for (int index = 0; index < 8; index++) {
        NSRectAlignment alignment = alignments[index];
        for (int extends = 0; extends < 2; extends++) {
            for (int direction = 0; direction < 2; direction++) {
                add([NSString stringWithFormat:@"boundary item taller than its section, alignment %ld, %@, %@", (long)alignment, extends ? @"extending" : @"inside", direction ? @"sideways" : @"down"], ^{
                    NSCollectionLayoutGroup *group = direction ? HG(AB(100), FH(1), @[IT(FW(1), FH(0.5))]) : HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]);
                    NSCollectionLayoutSection *section = SEC(group);
                    section.boundarySupplementaryItems = @[BND(@"h", AB(33), AB(200), alignment, 0, 0, extends, NO)];
                    return make(LAYOUT(section, CFG(direction ? HORIZONTAL : VERTICAL, 0, nil)), @[@4], @[@"h"], @[], PHONE);
                });
            }
        }
    }
    add(@"boundary header and footer of fractional sizes", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"h", FW(1), FH(0.1), NSRectAlignmentTop, 0, 0, YES, NO), BND(@"f", FW(0.5), ES(20), NSRectAlignmentBottom, 0, 0, YES, NO)];
        return make(LAYOUT(section, nil), @[@3, @2], @[@"h", @"f"], @[], PHONE);
    });
    add(@"several boundary items on one side", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, NO), BND(@"t", FW(1), AB(10), NSRectAlignmentTop, 0, 0, YES, NO),
                                               BND(@"f", FW(1), AB(7), NSRectAlignmentBottom, 0, 0, YES, NO), BND(@"g", FW(1), AB(5), NSRectAlignmentBottom, 0, 0, YES, NO)];
        return make(LAYOUT(section, nil), @[@3, @2], @[@"h", @"t", @"f", @"g"], @[], PHONE);
    });
    add(@"boundary items of the layout", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"l", FW(1), AB(10), NSRectAlignmentTop, 0, 0, YES, NO)];
        return make(LAYOUT(section, CFG(VERTICAL, 0, @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, NO), BND(@"f", FW(1), AB(20), NSRectAlignmentBottom, 0, 0, YES, NO)])),
                    @[@3, @2], @[@"l", @"h", @"f"], @[], PHONE);
    });
    add(@"boundary items of the layout on the sides", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        return make(LAYOUT(section, CFG(VERTICAL, 0, @[BND(@"h", AB(30), FH(1), NSRectAlignmentLeading, 0, 0, YES, NO), BND(@"f", AB(20), FH(1), NSRectAlignmentTrailing, 0, 0, YES, NO)])),
                    @[@3, @2], @[@"h", @"f"], @[], PHONE);
    });
    add(@"boundary items of the layout, sideways", ^{
        NSCollectionLayoutSection *section = SEC(HG(AB(100), FH(1), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        return make(LAYOUT(section, CFG(HORIZONTAL, 0, @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, NO), BND(@"f", AB(20), FH(1), NSRectAlignmentTrailing, 0, 0, YES, NO)])),
                    @[@3, @2], @[@"h", @"f"], @[], PHONE);
    });
    add(@"boundary items of empty sections", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"l", FW(1), AB(10), NSRectAlignmentTop, 0, 0, YES, NO)];
        return make(LAYOUT(section, CFG(VERTICAL, 0, @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, NO)])), @[@0, @2, @0], @[@"l", @"h"], @[], PHONE);
    });
    add(@"pinned headers at the top", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, YES)];
        CompositionalCase *built = make(LAYOUT(section, nil), @[@3, @12], @[@"h"], @[], CGSizeMake(320, 100));
        built.offset = CGPointMake(0, 130);
        return built;
    });
    add(@"pinned headers at the section end", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, YES), BND(@"f", FW(1), AB(20), NSRectAlignmentBottom, 0, 0, YES, YES)];
        CompositionalCase *built = make(LAYOUT(section, nil), @[@3, @12], @[@"h", @"f"], @[], CGSizeMake(320, 100));
        built.offset = CGPointMake(0, 100);
        return built;
    });
    add(@"pinned headers sideways", ^{
        NSCollectionLayoutSection *section = SEC(HG(AB(100), FH(1), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.boundarySupplementaryItems = @[BND(@"h", AB(60), FH(1), NSRectAlignmentLeading, 0, 0, YES, YES)];
        CompositionalCase *built = make(LAYOUT(section, CFG(HORIZONTAL, 0, nil)), @[@8, @4], @[@"h"], @[], CGSizeMake(200, 300));
        built.offset = CGPointMake(120, 0);
        return built;
    });
    add(@"badge on an item", ^{
        NSCollectionLayoutSupplementaryItem *badge = SUP(@"badge", AB(20), AB(10), ANCHOR(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing), nil);
        NSCollectionLayoutItem *item = [(id)K.item itemWithLayoutSize:SZ(FW(0.5), FH(1)) supplementaryItems:@[badge]];
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(60), @[item]));
        section.contentInsets = EI(20, 20, 20, 20);
        return make(LAYOUT(section, nil), @[@3], @[@"badge"], @[], PHONE);
    });
    NSDirectionalRectEdge edgeSets[] = {NSDirectionalRectEdgeTop, NSDirectionalRectEdgeLeading, NSDirectionalRectEdgeBottom, NSDirectionalRectEdgeTrailing,
                                        NSDirectionalRectEdgeTop | NSDirectionalRectEdgeLeading, NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeTrailing, NSDirectionalRectEdgeTop | NSDirectionalRectEdgeBottom, 0};
    for (int index = 0; index < 8; index++) {
        NSDirectionalRectEdge edges = edgeSets[index];
        add([NSString stringWithFormat:@"badge anchored to edges %lu, on the item and on the group", (unsigned long)edges], ^{
            NSCollectionLayoutSupplementaryItem *badge = SUP(@"badge", AB(40), AB(20), ANCHOR(edges), nil);
            NSCollectionLayoutSupplementaryItem *other = SUP(@"other", AB(40), AB(20), ANCHOR(edges), ANCHOR(NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeLeading));
            NSCollectionLayoutItem *item = [(id)K.item itemWithLayoutSize:SZ(FW(1), FH(1)) supplementaryItems:@[badge]];
            NSCollectionLayoutGroup *group = HG(FW(1), AB(200), @[item]);
            group.supplementaryItems = @[other];
            NSCollectionLayoutSection *section = SEC(group);
            section.contentInsets = EI(50, 50, 50, 50);
            return make(LAYOUT(section, nil), @[@1], @[@"badge", @"other"], @[], PHONE);
        });
    }
    add(@"badges with offsets, anchors of the item and fractional sizes", ^{
        NSCollectionLayoutSupplementaryItem *one = SUP(@"one", AB(40), AB(20), ANCHOR_ABS(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing, 7, 9), nil);
        NSCollectionLayoutSupplementaryItem *two = SUP(@"two", AB(40), AB(20), ANCHOR_FRAC(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing, 0.5, 0.25), nil);
        NSCollectionLayoutSupplementaryItem *three = SUP(@"three", AB(40), AB(20), ANCHOR(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing), ANCHOR_FRAC(NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeLeading, 0.5, 0.25));
        NSCollectionLayoutSupplementaryItem *four = SUP(@"four", AB(40), AB(20), ANCHOR(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing), ANCHOR_ABS(NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeLeading, 3, 4));
        NSCollectionLayoutSupplementaryItem *five = SUP(@"five", FW(0.5), FH(0.25), ANCHOR(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing), nil);
        NSCollectionLayoutSupplementaryItem *six = SUP(@"six", ES(33), ES(17), ANCHOR(NSDirectionalRectEdgeBottom), nil);
        six.zIndex = 5;
        NSCollectionLayoutItem *item = [(id)K.item itemWithLayoutSize:SZ(FW(1), FH(1)) supplementaryItems:@[one, two, three, four, five, six]];
        item.contentInsets = EI(2, 3, 4, 5);
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(200), @[item]));
        section.contentInsets = EI(50, 50, 50, 50);
        return make(LAYOUT(section, nil), @[@1], @[@"one", @"two", @"three", @"four", @"five", @"six"], @[], PHONE);
    });
    add(@"group supplementary items on nested groups", ^{
        NSCollectionLayoutGroup *inner = VG(FW(0.5), FH(1), @[IT(FW(1), FH(0.5))]);
        inner.supplementaryItems = @[SUP(@"g", FW(1), AB(4), ANCHOR(NSDirectionalRectEdgeBottom), nil)];
        NSCollectionLayoutGroup *group = HG(FW(1), AB(100), @[IT(FW(0.5), FH(1)), inner]);
        return make(LAYOUT(SEC(group), nil), @[@6], @[@"g"], @[], PHONE);
    });
    add(@"group supplementary items", ^{
        NSCollectionLayoutGroup *group = HG(FW(1), AB(60), @[IT(FW(0.5), FH(1))]);
        group.supplementaryItems = @[SUP(@"g", FW(1), AB(4), ANCHOR(NSDirectionalRectEdgeBottom), nil), SUP(@"g2", FW(1), AB(5), ANCHOR(NSDirectionalRectEdgeTop), nil)];
        return make(LAYOUT(SEC(group), nil), @[@5, @3], @[@"g", @"g2"], @[], PHONE);
    });
    add(@"two badges on an item", ^{
        NSCollectionLayoutSupplementaryItem *one = SUP(@"badge", AB(10), AB(10), ANCHOR(NSDirectionalRectEdgeTop | NSDirectionalRectEdgeLeading), nil);
        NSCollectionLayoutSupplementaryItem *two = SUP(@"badge2", AB(10), AB(10), ANCHOR(NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeLeading), nil);
        NSCollectionLayoutItem *item = [(id)K.item itemWithLayoutSize:SZ(FW(0.5), FH(1)) supplementaryItems:@[one, two]];
        return make(LAYOUT(SEC(HG(FW(1), AB(60), @[item])), nil), @[@2], @[@"badge", @"badge2"], @[], PHONE);
    });
    add(@"background decoration", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.interGroupSpacing = 4;
        NSCollectionLayoutDecorationItem *decoration = [(id)K.decoration backgroundDecorationItemWithElementKind:@"bg"];
        decoration.contentInsets = EI(1, 2, 3, 4);
        decoration.zIndex = -3;
        section.decorationItems = @[decoration];
        section.boundarySupplementaryItems = @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, NO)];
        return make(LAYOUT(section, nil), @[@3, @0, @2], @[@"h"], @[@"bg"], PHONE);
    });
    add(@"background decoration sideways", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        section.contentInsets = EI(3, 4, 5, 6);
        section.decorationItems = @[[(id)K.decoration backgroundDecorationItemWithElementKind:@"bg"]];
        section.boundarySupplementaryItems = @[BND(@"h", FW(1), AB(30), NSRectAlignmentTop, 0, 0, YES, NO)];
        return make(LAYOUT(section, CFG(HORIZONTAL, 0, nil)), @[@3, @2], @[@"h"], @[@"bg"], PHONE);
    });
    add(@"decoration in one section only", ^{
        UICollectionViewLayout *layout = [[(id)K.layout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger index, id environment) {
            NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
            if (index == 0)
                section.decorationItems = @[[(id)K.decoration backgroundDecorationItemWithElementKind:@"bg"]];
            return section;
        }];
        return make(layout, @[@3, @2], @[], @[@"bg"], PHONE);
    });
    add(@"orthogonal scrolling is laid out as a plain section", ^{
        NSCollectionLayoutSection *section = SEC(HG(AB(100), AB(50), @[IT(FW(1), FH(1))]));
        section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorNone;
        return make(LAYOUT(section, nil), @[@5, @2], @[], @[], PHONE);
    });
    for (int reference = 0; reference <= 4; reference++) {
        for (int level = 0; level < 2; level++) {
            for (int direction = 0; direction < 2; direction++) {
                add([NSString stringWithFormat:@"content insets reference %d on the %@, %@", reference, level ? @"section" : @"layout", direction ? @"sideways" : @"down"], ^{
                    NSCollectionLayoutSection *section = SEC(direction ? HG(AB(100), FH(1), @[IT(FW(0.5), FH(1))]) : HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
                    section.boundarySupplementaryItems = @[BND(@"h", direction ? AB(20) : FW(1), direction ? FH(1) : AB(20), direction ? NSRectAlignmentLeading : NSRectAlignmentTop, 0, 0, YES, NO)];
                    UICollectionViewCompositionalLayoutConfiguration *configuration = CFG(direction ? HORIZONTAL : VERTICAL, 0, nil);
                    if (level)
                        section.contentInsetsReference = (UIContentInsetsReference)reference;
                    else
                        configuration.contentInsetsReference = (UIContentInsetsReference)reference;
                    CompositionalCase *built = make(LAYOUT(section, configuration), @[@3, @2], @[@"h"], @[], PHONE);
                    built.margins = UIEdgeInsetsMake(10, 20, 30, 40);
                    return built;
                });
            }
        }
    }
    add(@"content insets reference of the layout and its boundary items", ^{
        NSCollectionLayoutSection *section = SEC(HG(FW(1), AB(40), @[IT(FW(0.5), FH(1))]));
        UICollectionViewCompositionalLayoutConfiguration *configuration = CFG(VERTICAL, 0, @[BND(@"h", FW(1), AB(20), NSRectAlignmentTop, 0, 0, YES, NO)]);
        configuration.contentInsetsReference = UIContentInsetsReferenceLayoutMargins;
        CompositionalCase *built = make(LAYOUT(section, configuration), @[@3], @[@"h"], @[], PHONE);
        built.margins = UIEdgeInsetsMake(10, 20, 30, 40);
        return built;
    });
    return list;
}

static NSArray *charon_builders;
static NSArray *charon_names;

static void ensure(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *names = [NSMutableArray array];
        charon_builders = builders(names);
        charon_names = names;
    });
}

NSUInteger compositional_case_count(void)
{
    ensure();
    return charon_builders.count;
}

NSString *compositional_case_name(NSUInteger index)
{
    ensure();
    return charon_names[index];
}

static NSString *number(double value)
{
    return [NSString stringWithFormat:@"%g", value];
}

static NSString *rect_text(CGRect rect)
{
    return [NSString stringWithFormat:@"%@ %@ %@ %@", number(rect.origin.x), number(rect.origin.y), number(rect.size.width), number(rect.size.height)];
}

static NSString *key_of(UICollectionViewLayoutAttributes *attributes)
{
    NSInteger item = attributes.indexPath.item;
    return [NSString stringWithFormat:@"%ld %@ %ld.%@", (long)attributes.representedElementCategory, attributes.representedElementKind ?: @"-", (long)attributes.indexPath.section,
                                      item == NSIntegerMax ? @"MAX" : [NSString stringWithFormat:@"%ld", (long)item]];
}

NSString *compositional_dump(CompositionalCase *built, UIWindow *window)
{
    UICollectionViewLayout *layout = built.layout;
    UICollectionView *view = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, built.size.width, built.size.height) collectionViewLayout:layout];
    CompositionalSource *source = [[CompositionalSource alloc] init];
    source.counts = built.counts;
    view.dataSource = source;
    [view registerClass:[CompositionalCell class] forCellWithReuseIdentifier:@"c"];
    for (NSString *kind in built.kinds)
        [view registerClass:[CompositionalSupplement class] forSupplementaryViewOfKind:kind withReuseIdentifier:@"s"];
    for (NSString *kind in built.decorations)
        [layout registerClass:[CompositionalSupplement class] forDecorationViewOfKind:kind];
    view.layoutMargins = built.margins;
    [window.rootViewController.view addSubview:view];
    [view layoutIfNeeded];
    if (!CGPointEqualToPoint(built.offset, CGPointZero)) {
        view.contentOffset = built.offset;
        [view layoutIfNeeded];
    }
    NSMutableString *out = [NSMutableString string];
    CGSize content = layout.collectionViewContentSize;
    [out appendFormat:@"content %@ %@ offset %@ %@\n", number(content.width), number(content.height), number(view.bounds.origin.x), number(view.bounds.origin.y)];
    NSMutableArray *lines = [NSMutableArray array];
    BOOL scrolled = !CGPointEqualToPoint(built.offset, CGPointZero);
    for (UICollectionViewLayoutAttributes *attributes in [layout layoutAttributesForElementsInRect:CGRectMake(-10000, -10000, 20000, 20000)]) {
        if (scrolled && !CGRectIntersectsRect(attributes.frame, view.bounds))
            continue;
        [lines addObject:[NSString stringWithFormat:@"%@ %@ z%ld", key_of(attributes), rect_text(attributes.frame), (long)attributes.zIndex]];
    }
    [lines sortUsingSelector:@selector(compare:)];
    for (NSString *line in lines)
        [out appendFormat:@"%@\n", line];
    CGRect bounds = view.bounds;
    CGPoint at = bounds.origin;
    CGRect rects[] = {CGRectMake(at.x, at.y, bounds.size.width, 50), CGRectMake(at.x, at.y + bounds.size.height / 2, bounds.size.width, 30), CGRectMake(at.x + bounds.size.width, at.y, 50, bounds.size.height),
                      scrolled ? CGRectMake(at.x + 5, at.y + 5, 40, 40) : CGRectMake(-20, -20, 40, 40), bounds, CGRectMake(at.x, at.y + 33, bounds.size.width, 0.5)};
    for (size_t index = 0; index < sizeof rects / sizeof rects[0]; index++) {
        NSMutableArray *keys = [NSMutableArray array];
        for (UICollectionViewLayoutAttributes *attributes in [layout layoutAttributesForElementsInRect:rects[index]])
            [keys addObject:key_of(attributes)];
        [keys sortUsingSelector:@selector(compare:)];
        [out appendFormat:@"rect %@: %@\n", rect_text(rects[index]), [keys componentsJoinedByString:@", "]];
    }
    NSMutableArray *singles = [NSMutableArray array];
    for (NSInteger section = 0; section < (NSInteger)built.counts.count; section++) {
        NSInteger count = [built.counts[(NSUInteger)section] integerValue];
        for (NSInteger item = 0; item < MIN(count, 3); item++) {
            UICollectionViewLayoutAttributes *attributes = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
            [singles addObject:attributes ? rect_text(attributes.frame) : @"nil"];
        }
    }
    [out appendFormat:@"single %@\n", [singles componentsJoinedByString:@", "]];
    [view removeFromSuperview];
    return out;
}

NSString *compositional_case_dump(CompositionalKit kit, NSUInteger index, UIWindow *window)
{
    ensure();
    K = kit;
    CompositionalBuilder builder = charon_builders[index];
    return compositional_dump(builder(), window);
}
