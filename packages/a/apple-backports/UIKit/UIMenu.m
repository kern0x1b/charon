#import "CharonMenus.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation UIMenu {
@private
    NSString *_identifier;
    UIMenuOptions _options;
    NSArray<UIMenuElement *> *_children;
}

@dynamic preferredElementSize, selectedElements;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (UIMenu *)menuWithTitle:(NSString *)title children:(NSArray<UIMenuElement *> *)children
{
    return [[self alloc] initCharonWithTitle:title image:nil identifier:nil options:0 children:children];
}

+ (UIMenu *)menuWithTitle:(NSString *)title image:(UIImage *)image identifier:(NSString *)identifier options:(UIMenuOptions)options
                 children:(NSArray<UIMenuElement *> *)children
{
    return [[self alloc] initCharonWithTitle:title image:image identifier:identifier options:options children:children];
}

- (instancetype)initCharonWithTitle:(NSString *)title image:(UIImage *)image identifier:(NSString *)identifier options:(UIMenuOptions)options
                            children:(NSArray<UIMenuElement *> *)children
{
    for (id child in children) {
        if (![child isKindOfClass:[UIMenuElement class]])
            [NSException raise:NSInvalidArgumentException format:@"-[%@ %@]: unrecognized selector sent to instance %p", [child class], @"_acceptMenuVisit:leafVisit:", child];
    }
    if ((self = [super initCharonWithTitle:title image:image])) {
        _identifier = identifier ? [identifier copy] : [@"com.apple.menu.dynamic." stringByAppendingString:[NSUUID UUID].UUIDString];
        _options = options;
        _children = children ? [children copy] : @[];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        NSString *identifier = [coder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
        _identifier = identifier ? [identifier copy] : [@"com.apple.menu.dynamic." stringByAppendingString:[NSUUID UUID].UUIDString];
        _options = (UIMenuOptions)[coder decodeIntegerForKey:@"options"];
        NSArray *children = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [UIMenuElement class], nil] forKey:@"children"];
        _children = children ? [children copy] : @[];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_identifier forKey:@"identifier"];
    [coder encodeInteger:(NSInteger)_options forKey:@"options"];
    [coder encodeObject:_children forKey:@"children"];
    [coder encodeInteger:-1 forKey:@"preferredElementSize"];
    [coder encodeInteger:-1 forKey:@"resolvedElementSize"];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSMutableArray *children = [NSMutableArray arrayWithCapacity:_children.count];
    for (UIMenuElement *child in _children)
        [children addObject:[child copy]];
    return [[[self class] allocWithZone:zone] initCharonWithTitle:self.title image:self.image identifier:_identifier options:_options children:children];
}

- (NSString *)identifier
{
    return _identifier;
}

- (UIMenuOptions)options
{
    return _options;
}

- (NSArray<UIMenuElement *> *)children
{
    return _children;
}

- (UIMenu *)menuByReplacingChildren:(NSArray<UIMenuElement *> *)newChildren
{
    return [[[self class] alloc] initCharonWithTitle:self.title image:self.image identifier:_identifier options:_options children:newChildren ?: _children];
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isKindOfClass:[UIMenu class]])
        return NO;
    NSString *other = [(UIMenu *)object identifier];
    return _identifier == other || [_identifier isEqual:other];
}

- (NSUInteger)hash
{
    return _identifier.hash;
}

- (NSString *)description
{
    NSMutableString *text = [NSMutableString stringWithFormat:@"<%@: %p", [self class], self];
    if (self.title.length)
        [text appendFormat:@"; title = %@", self.title];
    [text appendFormat:@"; identifier = %@", _identifier];
    if (self.image)
        [text appendFormat:@"; image = %@", charon_short_description(self.image)];
    if (_options) {
        NSMutableArray *names = [NSMutableArray array];
        if (_options & UIMenuOptionsDisplayInline)
            [names addObject:@"Inline"];
        if (_options & UIMenuOptionsDestructive)
            [names addObject:@"Destructive"];
        if (_options & 32)
            [names addObject:@"SingleSelection"];
        [text appendFormat:@"; options = (%@)", [names componentsJoinedByString:@"|"]];
    }
    [text appendFormat:@"; children = <NSArray: %p>>", _children];
    return text;
}

@end
