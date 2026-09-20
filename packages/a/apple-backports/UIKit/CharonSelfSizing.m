#import "CharonCompositionalLayout.h"
#import <objc/runtime.h>

static void charon_wrap_labels(UIView *view, NSMutableArray *labels)
{
    if ([view isKindOfClass:[UILabel class]])
        [labels addObject:view];
    for (UIView *sub in view.subviews)
        charon_wrap_labels(sub, labels);
}

static CGSize charon_constrained_fit(UIView *content, CGSize proposed, BOOL estimatedWidth, BOOL estimatedHeight)
{
    BOOL translates = content.translatesAutoresizingMaskIntoConstraints;
    CGRect frame = content.frame;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray *pins = [NSMutableArray array];
    if (!estimatedWidth)
        [pins addObject:[NSLayoutConstraint constraintWithItem:content attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
                                                       constant:proposed.width]];
    if (!estimatedHeight)
        [pins addObject:[NSLayoutConstraint constraintWithItem:content attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
                                                       constant:proposed.height]];
    [content addConstraints:pins];
    CGSize size = [content systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    if (!estimatedWidth)
        size.width = proposed.width;
    if (!estimatedHeight)
        size.height = proposed.height;
    content.frame = CGRectMake(0, 0, size.width, size.height);
    [content setNeedsLayout];
    [content layoutIfNeeded];
    NSMutableArray *labels = [NSMutableArray array];
    charon_wrap_labels(content, labels);
    BOOL wrapped = NO;
    for (UILabel *label in labels) {
        CGFloat width = label.bounds.size.width;
        if (label.numberOfLines != 1 && fabs(label.preferredMaxLayoutWidth - width) > 0.01) {
            label.preferredMaxLayoutWidth = width;
            wrapped = YES;
        }
    }
    if (wrapped) {
        size = [content systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (!estimatedWidth)
            size.width = proposed.width;
        if (!estimatedHeight)
            size.height = proposed.height;
    }
    [content removeConstraints:pins];
    content.translatesAutoresizingMaskIntoConstraints = translates;
    content.frame = frame;
    return size;
}

static BOOL charon_overrides_preferred(UICollectionReusableView *view)
{
    SEL selector = @selector(preferredLayoutAttributesFittingAttributes:);
    IMP mine = class_getMethodImplementation([view class], selector);
    return mine != class_getMethodImplementation([UICollectionReusableView class], selector) && mine != class_getMethodImplementation([UICollectionViewCell class], selector);
}

CGSize charon_fit_size(UICollectionReusableView *view, NSIndexPath *indexPath, NSString *kind, CGSize proposed, BOOL estimatedWidth, BOOL estimatedHeight, CGFloat scale)
{
    UIView *content = [view respondsToSelector:@selector(contentView)] ? [(UICollectionViewCell *)view contentView] : view;
    CGSize size;
    if (charon_overrides_preferred(view)) {
        UICollectionViewLayoutAttributes *attributes = kind ? [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:kind withIndexPath:indexPath]
                                                            : [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attributes.frame = CGRectMake(0, 0, proposed.width, proposed.height);
        size = [view preferredLayoutAttributesFittingAttributes:attributes].size;
    } else if (content.constraints.count > 0) {
        size = charon_constrained_fit(content, proposed, estimatedWidth, estimatedHeight);
    } else {
        CGRect frame = view.frame;
        view.frame = CGRectMake(0, 0, proposed.width, proposed.height);
        [view layoutIfNeeded];
        size = [view sizeThatFits:proposed];
        view.frame = frame;
    }
    if (!(size.width > 0) || !(size.height > 0) || !isfinite(size.width) || !isfinite(size.height))
        return proposed;
    if (scale > 0) {
        size.width = ceil(size.width * scale - 0.001) / scale;
        size.height = ceil(size.height * scale - 0.001) / scale;
    }
    return CGSizeMake(estimatedWidth ? size.width : proposed.width, estimatedHeight ? size.height : proposed.height);
}

@implementation UICollectionView (CharonSelfSizing)

- (void)charon_layoutSubviews
{
    [self charon_layoutSubviews];
    for (int pass = 0; pass < 4; pass++) {
        UICollectionViewLayout *layout = self.collectionViewLayout;
        if (![layout respondsToSelector:@selector(charon_settleMeasurements)] || ![layout charon_settleMeasurements])
            break;
        [self charon_layoutSubviews];
    }
}

+ (void)load
{
    SEL original = @selector(layoutSubviews), replacement = @selector(charon_layoutSubviews);
    Method own = class_getInstanceMethod([UICollectionView class], replacement);
    IMP replaced = method_getImplementation(own);
    const char *types = method_getTypeEncoding(own);
    Method inherited = class_getInstanceMethod([UICollectionView class], original);
    if (!inherited)
        return;
    if (class_addMethod([UICollectionView class], original, replaced, types))
        class_replaceMethod([UICollectionView class], replacement, method_getImplementation(inherited), types);
    else
        method_exchangeImplementations(inherited, own);
}

@end
