#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIView *charon_item_view(id item)
{
    return [item isKindOfClass:[UILayoutGuide class]] ? [(UILayoutGuide *)item owningView] : item;
}

static UIView *charon_container(NSLayoutConstraint *constraint)
{
    for (UIView *view = charon_item_view(constraint.firstItem); view; view = view.superview) {
        if ([view.constraints indexOfObjectIdenticalTo:constraint] != NSNotFound)
            return view;
    }
    return nil;
}

static UIView *charon_common_ancestor(UIView *first, UIView *second)
{
    if (!second)
        return first;
    for (UIView *candidate = first; candidate; candidate = candidate.superview) {
        if ([second isDescendantOfView:candidate])
            return candidate;
    }
    return nil;
}

@interface NSObject (CharonGuideBacking)
- (UILayoutGuide *)charon_guide;
@end

static UILayoutGuide *charon_guide(id item)
{
    return [item respondsToSelector:@selector(charon_guide)] ? [item charon_guide] : nil;
}

static BOOL charon_ownerless(id item)
{
    UILayoutGuide *guide = [item isKindOfClass:[UILayoutGuide class]] ? item : charon_guide(item);
    return guide && !guide.owningView;
}

static UIView *charon_holder(UIView *ancestor)
{
    UILayoutGuide *guide = charon_guide(ancestor);
    return guide ? guide.owningView : ancestor;
}

@implementation NSLayoutConstraint (CharonActivation)

+ (void)activateConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *constraint in constraints)
        [constraint setActive:YES];
}

+ (void)deactivateConstraints:(NSArray *)constraints
{
    for (NSLayoutConstraint *constraint in constraints)
        [constraint setActive:NO];
}

- (BOOL)isActive
{
    return charon_container(self) != nil;
}

- (void)setActive:(BOOL)active
{
    UIView *container = charon_container(self);
    if (!active) {
        [container removeConstraint:self];
        return;
    }
    if (container || charon_ownerless(self.firstItem) || charon_ownerless(self.secondItem))
        return;
    UIView *ancestor = charon_common_ancestor(charon_item_view(self.firstItem), charon_item_view(self.secondItem));
    if (!ancestor)
        [NSException raise:NSGenericException format:@"Unable to activate constraint with items %@ and %@ because they have no common ancestor.  Does the constraint reference items in different view hierarchies?  That's illegal.", self.firstItem, self.secondItem];
    [charon_holder(ancestor) addConstraint:self];
}

@end

@interface UILayoutGuide (CharonBacking)
- (UIView *)charon_view;
@end

@interface CharonConstraintGuideItems : NSObject
@end

@implementation CharonConstraintGuideItems

+ (void)load
{
    SEL selector = @selector(constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:);
    Method method = class_getClassMethod([NSLayoutConstraint class], selector);
    NSLayoutConstraint *(*original)(id, SEL, id, NSLayoutAttribute, NSLayoutRelation, id, NSLayoutAttribute, CGFloat, CGFloat) = (NSLayoutConstraint *(*)(id, SEL, id, NSLayoutAttribute, NSLayoutRelation, id, NSLayoutAttribute, CGFloat, CGFloat))method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^NSLayoutConstraint *(Class self, id first, NSLayoutAttribute firstAttribute, NSLayoutRelation relation, id second, NSLayoutAttribute secondAttribute, CGFloat multiplier, CGFloat constant) {
        if ([first isKindOfClass:[UILayoutGuide class]])
            first = [(UILayoutGuide *)first charon_view];
        if ([second isKindOfClass:[UILayoutGuide class]])
            second = [(UILayoutGuide *)second charon_view];
        return original(self, selector, first, firstAttribute, relation, second, secondAttribute, multiplier, constant);
    });
    class_replaceMethod(object_getClass([NSLayoutConstraint class]), selector, replacement, method_getTypeEncoding(method));
}

@end
