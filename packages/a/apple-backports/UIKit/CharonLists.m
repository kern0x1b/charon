#import "CharonLists.h"

UIColor *charon_semantic_color(CharonSemanticColor which)
{
    static const SEL selectors[] = {NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL};
    (void)selectors;
    switch (which) {
    case CharonSemanticColorLabel:
        return [UIColor respondsToSelector:@selector(labelColor)] ? [UIColor labelColor] : [UIColor blackColor];
    case CharonSemanticColorSecondaryLabel:
        return [UIColor respondsToSelector:@selector(secondaryLabelColor)] ? [UIColor secondaryLabelColor] : [UIColor colorWithRed:60.0 / 255 green:60.0 / 255 blue:67.0 / 255 alpha:0.6];
    case CharonSemanticColorTertiaryLabel:
        return [UIColor respondsToSelector:@selector(tertiaryLabelColor)] ? [UIColor tertiaryLabelColor] : [UIColor colorWithRed:60.0 / 255 green:60.0 / 255 blue:67.0 / 255 alpha:0.3];
    case CharonSemanticColorQuaternaryLabel:
        return [UIColor respondsToSelector:@selector(quaternaryLabelColor)] ? [UIColor quaternaryLabelColor] : [UIColor colorWithRed:60.0 / 255 green:60.0 / 255 blue:67.0 / 255 alpha:0.18];
    case CharonSemanticColorSystemBackground:
        return [UIColor respondsToSelector:@selector(systemBackgroundColor)] ? [UIColor systemBackgroundColor] : [UIColor whiteColor];
    case CharonSemanticColorSecondarySystemGroupedBackground:
        return [UIColor respondsToSelector:@selector(secondarySystemGroupedBackgroundColor)] ? [UIColor secondarySystemGroupedBackgroundColor] : [UIColor whiteColor];
    case CharonSemanticColorSystemGray4:
        return [UIColor respondsToSelector:@selector(systemGray4Color)] ? [UIColor systemGray4Color] : [UIColor colorWithRed:209.0 / 255 green:209.0 / 255 blue:214.0 / 255 alpha:1];
    case CharonSemanticColorQuaternarySystemFill:
        return [UIColor respondsToSelector:@selector(quaternarySystemFillColor)] ? [UIColor quaternarySystemFillColor] : [UIColor colorWithRed:116.0 / 255 green:116.0 / 255 blue:128.0 / 255 alpha:0.08];
    case CharonSemanticColorSeparator:
        return [UIColor respondsToSelector:@selector(separatorColor)] ? [UIColor separatorColor] : [UIColor colorWithRed:60.0 / 255 green:60.0 / 255 blue:67.0 / 255 alpha:0.29];
    }
    return nil;
}

NSString *charon_elided_text(NSString *text)
{
    if (!text.length)
        return @"''";
    NSUInteger length = text.length;
    if (length < 3)
        return [NSString stringWithFormat:@"'%@'", text];
    return [NSString stringWithFormat:@"'%@...%@' (length = %lu)", [text substringToIndex:1], [text substringFromIndex:length - 1], (unsigned long)length];
}

CGFloat charon_screen_scale(void)
{
    CGFloat scale = [UIScreen mainScreen].scale;
    return scale > 0 ? scale : 1;
}

CGFloat charon_pixel_ceil(CGFloat value, CGFloat scale)
{
    return ceil(value * scale - 0.0001) / scale;
}

CGFloat charon_pixel_round(CGFloat value, CGFloat scale)
{
    return round(value * scale) / scale;
}

UIFont *charon_medium_font(CGFloat pointSize)
{
    if (NSClassFromString(@"UIFontDescriptor")) {
        UIFontDescriptor *descriptor = [[UIFont preferredFontForTextStyle:UIFontTextStyleBody].fontDescriptor
            fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(UIFontWeightMedium)}}];
        UIFont *font = [UIFont fontWithDescriptor:descriptor size:pointSize];
        if (font)
            return font;
    }
    return [UIFont systemFontOfSize:pointSize weight:UIFontWeightMedium];
}
