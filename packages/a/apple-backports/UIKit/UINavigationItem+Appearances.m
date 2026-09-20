#import "CharonBarAppearance.h"

static const void *CharonStandardKey = &CharonStandardKey;
static const void *CharonCompactKey = &CharonCompactKey;
static const void *CharonScrollEdgeKey = &CharonScrollEdgeKey;

@implementation UINavigationItem (CharonAppearances)

- (UINavigationBarAppearance *)standardAppearance
{
    return charon_appearance_peek(self, CharonStandardKey);
}

- (void)setStandardAppearance:(UINavigationBarAppearance *)standardAppearance
{
    charon_appearance_store(self, CharonStandardKey, [standardAppearance copy]);
    if (standardAppearance)
        charon_note_stored_appearance(@"UINavigationItem.standardAppearance");
}

- (UINavigationBarAppearance *)compactAppearance
{
    return charon_appearance_peek(self, CharonCompactKey);
}

- (void)setCompactAppearance:(UINavigationBarAppearance *)compactAppearance
{
    charon_appearance_store(self, CharonCompactKey, [compactAppearance copy]);
    if (compactAppearance)
        charon_note_stored_appearance(@"UINavigationItem.compactAppearance");
}

- (UINavigationBarAppearance *)scrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonScrollEdgeKey);
}

- (void)setScrollEdgeAppearance:(UINavigationBarAppearance *)scrollEdgeAppearance
{
    charon_appearance_store(self, CharonScrollEdgeKey, [scrollEdgeAppearance copy]);
    if (scrollEdgeAppearance)
        charon_note_stored_appearance(@"UINavigationItem.scrollEdgeAppearance");
}

@end
