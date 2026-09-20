#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CharonGroupDirection) {
    CharonGroupDirectionHorizontal,
    CharonGroupDirectionVertical,
    CharonGroupDirectionCustom
};

typedef NS_ENUM(NSInteger, CharonDimensionKind) {
    CharonDimensionKindFractionalWidth,
    CharonDimensionKindFractionalHeight,
    CharonDimensionKindAbsolute,
    CharonDimensionKindEstimated
};

static inline void charon_layout_say_once(NSString *key, NSString *text)
{
    static NSMutableSet *said;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        said = [[NSMutableSet alloc] init];
    });
    @synchronized (said) {
        if ([said containsObject:key])
            return;
        [said addObject:key];
    }
    NSLog(@"%@", text);
}

@interface NSCollectionLayoutItem (CharonLayout)
- (instancetype)initCharonWithSize:(NSCollectionLayoutSize *)size supplementaryItems:(NSArray *)supplementaryItems;
- (NSString *)charon_bodyDescription;
- (NSString *)charon_kindName;
@end

@interface NSCollectionLayoutSupplementaryItem (CharonLayout)
- (instancetype)initCharonWithSize:(NSCollectionLayoutSize *)size elementKind:(NSString *)elementKind containerAnchor:(NSCollectionLayoutAnchor *)containerAnchor
                        itemAnchor:(NSCollectionLayoutAnchor *)itemAnchor;
@end

@interface NSCollectionLayoutBoundarySupplementaryItem (CharonLayout)
- (instancetype)initCharonWithSize:(NSCollectionLayoutSize *)size elementKind:(NSString *)elementKind alignment:(NSRectAlignment)alignment offset:(CGPoint)offset;
@end

@interface NSCollectionLayoutDecorationItem (CharonLayout)
- (instancetype)initCharonWithElementKind:(NSString *)elementKind;
@end

@interface NSCollectionLayoutGroup (CharonLayout)
- (instancetype)initCharonWithSize:(NSCollectionLayoutSize *)size direction:(CharonGroupDirection)direction subitems:(NSArray *)subitems
                             count:(NSInteger)count provider:(NSCollectionLayoutGroupCustomItemProvider)provider;
- (CharonGroupDirection)charon_direction;
- (NSInteger)charon_repeatCount;
- (NSCollectionLayoutGroupCustomItemProvider)charon_itemProvider;
@end

@interface NSCollectionLayoutSection (CharonLayout)
- (NSCollectionLayoutGroup *)charon_group;
- (NSInteger)charon_contentInsetsReference;
- (void)charon_setContentInsetsReference:(NSInteger)reference;
- (NSInteger)charon_supplementaryContentInsetsReference;
@end

@interface UICollectionViewCompositionalLayoutConfiguration (CharonLayout)
- (NSInteger)charon_contentInsetsReference;
- (void)charon_setContentInsetsReference:(NSInteger)reference;
@end

@interface NSCollectionLayoutAnchor (CharonLayout)
- (CGPoint)charon_anchorPoint;
@end

@interface NSCollectionLayoutSize (CharonLayout)
- (instancetype)initCharonWithWidth:(NSCollectionLayoutDimension *)width height:(NSCollectionLayoutDimension *)height;
@end

@interface NSCollectionLayoutSpacing (CharonLayout)
- (instancetype)initCharonWithSpacing:(CGFloat)spacing flexible:(BOOL)flexible;
@end

@interface NSCollectionLayoutDimension (CharonLayout)
- (instancetype)initCharonWithKind:(CharonDimensionKind)kind value:(CGFloat)value;
@end
