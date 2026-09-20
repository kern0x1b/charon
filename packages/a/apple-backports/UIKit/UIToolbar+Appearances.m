#import "CharonBarAppearance.h"

static const void *CharonStandardKey = &CharonStandardKey;
static const void *CharonCompactKey = &CharonCompactKey;
static const void *CharonActiveKey = &CharonActiveKey;
static const void *CharonAppliedKey = &CharonAppliedKey;
static const void *CharonPendingKey = &CharonPendingKey;

@interface UIToolbar (CharonAppearances)
- (void)charon_standardChanged;
- (void)charon_compactChanged;
- (void)charon_applyAppearances;
@end

@implementation UIToolbar (CharonAppearances)

- (UIToolbarAppearance *)standardAppearance
{
    return charon_appearance_get(self, CharonStandardKey, [UIToolbarAppearance class], @selector(charon_standardChanged));
}

- (void)setStandardAppearance:(UIToolbarAppearance *)standardAppearance
{
    charon_appearance_set(self, CharonStandardKey, standardAppearance, @selector(charon_standardChanged));
    charon_flag_set(self, CharonActiveKey, standardAppearance != nil);
    [self charon_applyAppearances];
}

- (UIToolbarAppearance *)compactAppearance
{
    return charon_appearance_peek(self, CharonCompactKey);
}

- (void)setCompactAppearance:(UIToolbarAppearance *)compactAppearance
{
    charon_appearance_set(self, CharonCompactKey, compactAppearance, @selector(charon_compactChanged));
    [self charon_applyAppearances];
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
    UIToolbarAppearance *standard = charon_flag_get(self, CharonActiveKey) ? charon_appearance_peek(self, CharonStandardKey) : nil;
    UIToolbarAppearance *compact = charon_appearance_peek(self, CharonCompactKey);
    if (!standard && !compact && !charon_flag_get(self, CharonAppliedKey))
        return;
    charon_apply_toolbar(self, standard, compact);
    charon_flag_set(self, CharonAppliedKey, standard || compact);
}

@end
