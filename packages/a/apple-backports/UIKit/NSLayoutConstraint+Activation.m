#import <UIKit/UIKit.h>

static UIView *charon_container(NSLayoutConstraint *constraint)
{
    for (UIView *view = constraint.firstItem; view; view = view.superview) {
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
    if (container)
        return;
    UIView *ancestor = charon_common_ancestor(self.firstItem, self.secondItem);
    if (!ancestor)
        [NSException raise:NSGenericException format:@"Unable to activate constraint with items %@ and %@ because they have no common ancestor.  Does the constraint reference items in different view hierarchies?  That's illegal.", self.firstItem, self.secondItem];
    [ancestor addConstraint:self];
}

@end
