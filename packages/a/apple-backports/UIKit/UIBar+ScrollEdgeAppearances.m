#import "CharonBarAppearance.h"

static const void *CharonScrollEdgeKey = &CharonScrollEdgeKey;
static const void *CharonCompactScrollEdgeKey = &CharonCompactScrollEdgeKey;

@implementation UINavigationBar (CharonScrollEdgeAppearances)

- (UINavigationBarAppearance *)compactScrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonCompactScrollEdgeKey);
}

- (void)setCompactScrollEdgeAppearance:(UINavigationBarAppearance *)compactScrollEdgeAppearance
{
    charon_appearance_store(self, CharonCompactScrollEdgeKey, [compactScrollEdgeAppearance copy]);
    if (compactScrollEdgeAppearance)
        charon_note_stored_appearance(@"UINavigationBar.compactScrollEdgeAppearance");
}

@end

@implementation UIToolbar (CharonScrollEdgeAppearances)

- (UIToolbarAppearance *)scrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonScrollEdgeKey);
}

- (void)setScrollEdgeAppearance:(UIToolbarAppearance *)scrollEdgeAppearance
{
    charon_appearance_store(self, CharonScrollEdgeKey, [scrollEdgeAppearance copy]);
    if (scrollEdgeAppearance)
        charon_note_stored_appearance(@"UIToolbar.scrollEdgeAppearance");
}

- (UIToolbarAppearance *)compactScrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonCompactScrollEdgeKey);
}

- (void)setCompactScrollEdgeAppearance:(UIToolbarAppearance *)compactScrollEdgeAppearance
{
    charon_appearance_store(self, CharonCompactScrollEdgeKey, [compactScrollEdgeAppearance copy]);
    if (compactScrollEdgeAppearance)
        charon_note_stored_appearance(@"UIToolbar.compactScrollEdgeAppearance");
}

@end

@implementation UITabBar (CharonScrollEdgeAppearances)

- (UITabBarAppearance *)scrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonScrollEdgeKey);
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance *)scrollEdgeAppearance
{
    charon_appearance_store(self, CharonScrollEdgeKey, [scrollEdgeAppearance copy]);
    if (scrollEdgeAppearance)
        charon_note_stored_appearance(@"UITabBar.scrollEdgeAppearance");
}

@end

@implementation UINavigationItem (CharonScrollEdgeAppearances)

- (UINavigationBarAppearance *)compactScrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonCompactScrollEdgeKey);
}

- (void)setCompactScrollEdgeAppearance:(UINavigationBarAppearance *)compactScrollEdgeAppearance
{
    charon_appearance_store(self, CharonCompactScrollEdgeKey, [compactScrollEdgeAppearance copy]);
    if (compactScrollEdgeAppearance)
        charon_note_stored_appearance(@"UINavigationItem.compactScrollEdgeAppearance");
}

@end

@implementation UITabBarItem (CharonScrollEdgeAppearances)

- (UITabBarAppearance *)scrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonScrollEdgeKey);
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance *)scrollEdgeAppearance
{
    charon_appearance_store(self, CharonScrollEdgeKey, [scrollEdgeAppearance copy]);
    if (scrollEdgeAppearance)
        charon_note_stored_appearance(@"UITabBarItem.scrollEdgeAppearance");
}

@end
