#import "CharonTraitStyle.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

typedef UIColor *(^CharonColorProvider)(UITraitCollection *traits);

static const char charon_provider_key;

static UIColor *charon_resolve(UIColor *color, UITraitCollection *traits)
{
    CharonColorProvider provider = objc_getAssociatedObject(color, &charon_provider_key);
    if (!provider)
        return color;
    UIColor *resolved = provider(traits);
    return resolved ? charon_resolve(resolved, traits) : nil;
}

static UIColor *charon_dynamic(CharonColorProvider provider)
{
    UIColor *base = charon_resolve(provider([UITraitCollection currentTraitCollection]), [UITraitCollection currentTraitCollection]);
    UIColor *carrier = [[UIColor alloc] initWithCGColor:base ? base.CGColor : [UIColor clearColor].CGColor];
    objc_setAssociatedObject(carrier, &charon_provider_key, [provider copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return carrier;
}

typedef struct {
    double light[4], dark[4], lightHigh[4], darkHigh[4], darkElevated[4];
} CharonColorRow;

#define C(r, g, b, a) {r / 255.0, g / 255.0, b / 255.0, a}
#define SAME {-1, 0, 0, 0}

static const CharonColorRow charon_rows[] = {
    [0] = {C(0, 0, 0, 1), C(255, 255, 255, 1), SAME, SAME, SAME},
    [1] = {C(60, 60, 67, 0.6), C(235, 235, 245, 0.6), SAME, SAME, SAME},
    [2] = {C(60, 60, 67, 0.3), C(235, 235, 245, 0.3), SAME, SAME, SAME},
    [3] = {C(60, 60, 67, 0.18), C(235, 235, 245, 0.16), SAME, SAME, SAME},
    [4] = {C(0, 122, 255, 1), C(9, 132, 255, 1), SAME, SAME, SAME},
    [5] = {C(60, 60, 67, 0.3), C(235, 235, 245, 0.3), SAME, SAME, SAME},
    [6] = {C(60, 60, 67, 0.29), C(84, 84, 88, 0.6), SAME, SAME, SAME},
    [7] = {C(198, 198, 200, 1), C(56, 56, 58, 1), SAME, SAME, SAME},
    [8] = {C(255, 255, 255, 1), C(0, 0, 0, 1), SAME, SAME, C(28, 28, 30, 1)},
    [9] = {C(242, 242, 247, 1), C(28, 28, 30, 1), SAME, SAME, C(44, 44, 46, 1)},
    [10] = {C(255, 255, 255, 1), C(44, 44, 46, 1), SAME, SAME, C(58, 58, 60, 1)},
    [11] = {C(242, 242, 247, 1), C(0, 0, 0, 1), SAME, SAME, C(28, 28, 30, 1)},
    [12] = {C(255, 255, 255, 1), C(28, 28, 30, 1), SAME, SAME, C(44, 44, 46, 1)},
    [13] = {C(242, 242, 247, 1), C(44, 44, 46, 1), SAME, SAME, C(58, 58, 60, 1)},
    [14] = {C(120, 120, 128, 0.2), C(120, 120, 128, 0.36), C(120, 120, 128, 0.28), C(120, 120, 128, 0.44), SAME},
    [15] = {C(120, 120, 128, 0.16), C(120, 120, 128, 0.32), C(120, 120, 128, 0.24), C(120, 120, 128, 0.4), SAME},
    [16] = {C(118, 118, 128, 0.12), C(118, 118, 128, 0.24), C(118, 118, 128, 0.2), C(118, 118, 128, 0.32), SAME},
    [17] = {C(116, 116, 128, 0.08), C(118, 118, 128, 0.18), C(116, 116, 128, 0.16), C(118, 118, 128, 0.26), SAME},
    [18] = {C(174, 174, 178, 1), C(99, 99, 102, 1), C(142, 142, 147, 1), C(124, 124, 128, 1), SAME},
    [19] = {C(199, 199, 204, 1), C(72, 72, 74, 1), C(174, 174, 178, 1), C(84, 84, 86, 1), SAME},
    [20] = {C(209, 209, 214, 1), C(58, 58, 60, 1), C(188, 188, 192, 1), C(68, 68, 70, 1), SAME},
    [21] = {C(229, 229, 234, 1), C(44, 44, 46, 1), C(216, 216, 220, 1), C(54, 54, 56, 1), SAME},
    [22] = {C(242, 242, 247, 1), C(28, 28, 30, 1), C(235, 235, 240, 1), C(36, 36, 38, 1), SAME},
    [23] = {C(162, 132, 94, 1), C(172, 142, 104, 1), SAME, SAME, SAME},
    [24] = {C(88, 86, 214, 1), C(94, 92, 230, 1), SAME, SAME, SAME},
    [25] = {C(50, 173, 230, 1), C(100, 210, 255, 1), C(0, 113, 164, 1), C(112, 215, 255, 1), SAME},
    [26] = {C(0, 199, 190, 1), C(99, 230, 226, 1), C(12, 129, 123, 1), C(99, 230, 226, 1), SAME},
};

static UIColor *charon_row_color(const double *values)
{
    return [UIColor colorWithRed:(CGFloat)values[0] green:(CGFloat)values[1] blue:(CGFloat)values[2] alpha:(CGFloat)values[3]];
}

static UIColor *charon_system_color(NSUInteger row)
{
    static UIColor *cache[sizeof(charon_rows) / sizeof(charon_rows[0])];
    static dispatch_once_t once;
    static NSObject *lock;
    dispatch_once(&once, ^{
        lock = [[NSObject alloc] init];
    });
    @synchronized (lock) {
        if (!cache[row]) {
            cache[row] = charon_dynamic(^UIColor *(UITraitCollection *traits) {
                const CharonColorRow *entry = &charon_rows[row];
                BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
                BOOL high = traits.accessibilityContrast == UIAccessibilityContrastHigh;
                const double *values = dark ? entry->dark : entry->light;
                if (high && (dark ? entry->darkHigh[0] : entry->lightHigh[0]) >= 0)
                    values = dark ? entry->darkHigh : entry->lightHigh;
                if (dark && traits.userInterfaceLevel == UIUserInterfaceLevelElevated && entry->darkElevated[0] >= 0)
                    values = entry->darkElevated;
                return charon_row_color(values);
            });
        }
        return cache[row];
    }
}

@implementation UIColor (CharonDynamicColor)

+ (UIColor *)colorWithDynamicProvider:(UIColor * (^)(UITraitCollection *))dynamicProvider
{
    return charon_dynamic(dynamicProvider);
}

- (UIColor *)initWithDynamicProvider:(UIColor * (^)(UITraitCollection *))dynamicProvider
{
    return charon_dynamic(dynamicProvider);
}

- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traitCollection
{
    return charon_resolve(self, traitCollection);
}

+ (UIColor *)labelColor { return charon_system_color(0); }
+ (UIColor *)secondaryLabelColor { return charon_system_color(1); }
+ (UIColor *)tertiaryLabelColor { return charon_system_color(2); }
+ (UIColor *)quaternaryLabelColor { return charon_system_color(3); }
+ (UIColor *)linkColor { return charon_system_color(4); }
+ (UIColor *)placeholderTextColor { return charon_system_color(5); }
+ (UIColor *)separatorColor { return charon_system_color(6); }
+ (UIColor *)opaqueSeparatorColor { return charon_system_color(7); }
+ (UIColor *)systemBackgroundColor { return charon_system_color(8); }
+ (UIColor *)secondarySystemBackgroundColor { return charon_system_color(9); }
+ (UIColor *)tertiarySystemBackgroundColor { return charon_system_color(10); }
+ (UIColor *)systemGroupedBackgroundColor { return charon_system_color(11); }
+ (UIColor *)secondarySystemGroupedBackgroundColor { return charon_system_color(12); }
+ (UIColor *)tertiarySystemGroupedBackgroundColor { return charon_system_color(13); }
+ (UIColor *)systemFillColor { return charon_system_color(14); }
+ (UIColor *)secondarySystemFillColor { return charon_system_color(15); }
+ (UIColor *)tertiarySystemFillColor { return charon_system_color(16); }
+ (UIColor *)quaternarySystemFillColor { return charon_system_color(17); }
+ (UIColor *)systemGray2Color { return charon_system_color(18); }
+ (UIColor *)systemGray3Color { return charon_system_color(19); }
+ (UIColor *)systemGray4Color { return charon_system_color(20); }
+ (UIColor *)systemGray5Color { return charon_system_color(21); }
+ (UIColor *)systemGray6Color { return charon_system_color(22); }
+ (UIColor *)systemBrownColor { return charon_system_color(23); }
+ (UIColor *)systemIndigoColor { return charon_system_color(24); }
+ (UIColor *)systemCyanColor { return charon_system_color(25); }
+ (UIColor *)systemMintColor { return charon_system_color(26); }

@end
