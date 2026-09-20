#import "CharonBarAppearance.h"

static const void *CharonStandardKey = &CharonStandardKey;
static const void *CharonCompactKey = &CharonCompactKey;
static const void *CharonScrollEdgeKey = &CharonScrollEdgeKey;
static const void *CharonActiveKey = &CharonActiveKey;
static const void *CharonAppliedKey = &CharonAppliedKey;
static const void *CharonPendingKey = &CharonPendingKey;

@interface UINavigationBar (CharonAppearances)
- (void)charon_standardChanged;
- (void)charon_compactChanged;
- (void)charon_applyAppearances;
@end

@implementation UINavigationBar (CharonAppearances)

- (UINavigationBarAppearance *)standardAppearance
{
    return charon_appearance_get(self, CharonStandardKey, [UINavigationBarAppearance class], @selector(charon_standardChanged));
}

- (void)setStandardAppearance:(UINavigationBarAppearance *)standardAppearance
{
    charon_appearance_set(self, CharonStandardKey, standardAppearance, @selector(charon_standardChanged));
    charon_flag_set(self, CharonActiveKey, standardAppearance != nil);
    [self charon_applyAppearances];
}

- (UINavigationBarAppearance *)compactAppearance
{
    return charon_appearance_peek(self, CharonCompactKey);
}

- (void)setCompactAppearance:(UINavigationBarAppearance *)compactAppearance
{
    charon_appearance_set(self, CharonCompactKey, compactAppearance, @selector(charon_compactChanged));
    [self charon_applyAppearances];
}

- (UINavigationBarAppearance *)scrollEdgeAppearance
{
    return charon_appearance_peek(self, CharonScrollEdgeKey);
}

- (void)setScrollEdgeAppearance:(UINavigationBarAppearance *)scrollEdgeAppearance
{
    charon_appearance_store(self, CharonScrollEdgeKey, [scrollEdgeAppearance copy]);
    if (scrollEdgeAppearance)
        charon_note_stored_appearance(@"UINavigationBar.scrollEdgeAppearance");
}

- (void)charon_standardChanged
{
    charon_flag_set(self, CharonActiveKey, YES);
    charon_schedule(self, @selector(charon_applyAppearances), CharonPendingKey);
}

- (void)charon_compactChanged
{
    charon_schedule(self, @selector(charon_applyAppearances), CharonPendingKey);
}

- (void)charon_applyAppearances
{
    UINavigationBarAppearance *standard = charon_flag_get(self, CharonActiveKey) ? charon_appearance_peek(self, CharonStandardKey) : nil;
    UINavigationBarAppearance *compact = charon_appearance_peek(self, CharonCompactKey);
    if (!standard && !compact && !charon_flag_get(self, CharonAppliedKey))
        return;
    charon_apply_navigation_bar(self, standard, compact);
    charon_flag_set(self, CharonAppliedKey, standard || compact);
}

@end
