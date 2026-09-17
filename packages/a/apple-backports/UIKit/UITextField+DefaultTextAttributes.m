#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char charon_default_attributes_key;

@implementation UITextField (CharonDefaultTextAttributes)

- (NSDictionary *)defaultTextAttributes
{
    NSMutableDictionary *attributes = [objc_getAssociatedObject(self, &charon_default_attributes_key) mutableCopy];
    if (!attributes)
        attributes = [NSMutableDictionary dictionary];
    [attributes removeObjectForKey:NSFontAttributeName];
    [attributes removeObjectForKey:NSForegroundColorAttributeName];
    [attributes removeObjectForKey:NSParagraphStyleAttributeName];
    UIFont *font = self.font;
    if (font)
        [attributes setObject:font forKey:NSFontAttributeName];
    UIColor *color = self.textColor;
    if (color)
        [attributes setObject:color forKey:NSForegroundColorAttributeName];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = self.textAlignment;
    [attributes setObject:paragraph forKey:NSParagraphStyleAttributeName];
    return attributes;
}

- (void)setDefaultTextAttributes:(NSDictionary *)defaultTextAttributes
{
    objc_setAssociatedObject(self, &charon_default_attributes_key, [defaultTextAttributes copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIFont *font = [defaultTextAttributes objectForKey:NSFontAttributeName];
    if (font)
        self.font = font;
    UIColor *color = [defaultTextAttributes objectForKey:NSForegroundColorAttributeName];
    if (color)
        self.textColor = color;
    NSParagraphStyle *paragraph = [defaultTextAttributes objectForKey:NSParagraphStyleAttributeName];
    if (paragraph)
        self.textAlignment = paragraph.alignment;
    NSString *text = self.text;
    if (text.length)
        self.attributedText = [[NSAttributedString alloc] initWithString:text attributes:[self defaultTextAttributes]];
}

@end
