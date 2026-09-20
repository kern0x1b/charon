#import <UIKit/UIKit.h>

#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"

@implementation UICollectionViewTransitionLayout {
@private
    UICollectionViewLayout *_currentLayout;
    UICollectionViewLayout *_nextLayout;
    CGFloat _transitionProgress;
}

- (instancetype)initWithCurrentLayout:(UICollectionViewLayout *)currentLayout nextLayout:(UICollectionViewLayout *)nextLayout
{
    if ((self = [super init])) {
        _currentLayout = currentLayout;
        _nextLayout = nextLayout;
    }
    return self;
}

- (UICollectionViewLayout *)currentLayout
{
    return _currentLayout;
}

- (UICollectionViewLayout *)nextLayout
{
    return _nextLayout;
}

- (CGFloat)transitionProgress
{
    return _transitionProgress;
}

- (void)setTransitionProgress:(CGFloat)transitionProgress
{
    _transitionProgress = transitionProgress;
}

- (void)updateValue:(CGFloat)value forAnimatedKey:(NSString *)key
{
}

- (CGFloat)valueForAnimatedKey:(NSString *)key
{
    return 0;
}

@end
