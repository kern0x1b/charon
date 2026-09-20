#import "CharonBarAppearance.h"

static const void *CharonStandardKey = &CharonStandardKey;
static const void *CharonActiveKey = &CharonActiveKey;
static const void *CharonAppliedKey = &CharonAppliedKey;
static const void *CharonPendingKey = &CharonPendingKey;

@interface UITabBar (CharonAppearances)
- (void)charon_standardChanged;
- (void)charon_applyAppearances;
@end

@implementation UITabBar (CharonAppearances)

- (UITabBarAppearance *)standardAppearance
{
    return charon_appearance_get(self, CharonStandardKey, [UITabBarAppearance class], @selector(charon_standardChanged));
}

- (void)setStandardAppearance:(UITabBarAppearance *)standardAppearance
{
    charon_appearance_set(self, CharonStandardKey, standardAppearance, @selector(charon_standardChanged));
    charon_flag_set(self, CharonActiveKey, standardAppearance != nil);
    [self charon_applyAppearances];
}

- (void)charon_standardChanged
{
    charon_flag_set(self, CharonActiveKey, YES);
    charon_schedule(self, @selector(charon_applyAppearances), CharonPendingKey);
}

- (void)charon_applyAppearances
{
    UITabBarAppearance *standard = charon_flag_get(self, CharonActiveKey) ? charon_appearance_peek(self, CharonStandardKey) : nil;
    if (!standard && !charon_flag_get(self, CharonAppliedKey))
        return;
    charon_apply_tab_bar(self, standard);
    charon_flag_set(self, CharonAppliedKey, standard != nil);
}

@end
