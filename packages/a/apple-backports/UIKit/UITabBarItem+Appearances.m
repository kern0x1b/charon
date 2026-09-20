#import "CharonBarAppearance.h"

static const void *CharonStandardKey = &CharonStandardKey;

@implementation UITabBarItem (CharonAppearances)

- (UITabBarAppearance *)standardAppearance
{
    return charon_appearance_peek(self, CharonStandardKey);
}

- (void)setStandardAppearance:(UITabBarAppearance *)standardAppearance
{
    charon_appearance_store(self, CharonStandardKey, [standardAppearance copy]);
    if (standardAppearance)
        charon_note_stored_appearance(@"UITabBarItem.standardAppearance");
}

@end
