#import "CharonLists.h"

#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

const CGFloat UICellAccessoryStandardDimension = -CGFLOAT_MAX;

static NSUInteger (^charon_default_position(void))(NSArray *)
{
    static NSUInteger (^block)(NSArray *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        block = [^NSUInteger(NSArray *accessories) {
            return accessories.count;
        } copy];
    });
    return block;
}

UICellAccessoryPosition UICellAccessoryPositionBeforeAccessoryOfClass(Class accessoryClass)
{
    return [^NSUInteger(NSArray *accessories) {
        for (NSUInteger index = 0; index < accessories.count; index++)
            if ([accessories[index] isKindOfClass:accessoryClass])
                return index;
        return (NSUInteger)0;
    } copy];
}

UICellAccessoryPosition UICellAccessoryPositionAfterAccessoryOfClass(Class accessoryClass)
{
    return [^NSUInteger(NSArray *accessories) {
        for (NSUInteger index = accessories.count; index > 0; index--)
            if ([accessories[index - 1] isKindOfClass:accessoryClass])
                return index;
        return accessories.count;
    } copy];
}

@interface CharonAccessoryView : UIControl
@property (nonatomic) NSInteger kind;
@property (nonatomic, copy) void (^charon_handler)(void);
@property (nonatomic, strong) UIColor *fill;
@property (nonatomic) BOOL expanded;
@property (nonatomic) BOOL marked;
@end

@implementation CharonAccessoryView {
    NSInteger _kind;
    void (^_handler)(void);
    UIColor *_fill;
    BOOL _expanded;
    BOOL _marked;
}

- (NSInteger)kind
{
    return _kind;
}

- (void)setKind:(NSInteger)kind
{
    _kind = kind;
}

- (void (^)(void))charon_handler
{
    return _handler;
}

- (void)setCharon_handler:(void (^)(void))charon_handler
{
    _handler = [charon_handler copy];
    [self removeTarget:self action:@selector(charon_fire) forControlEvents:UIControlEventTouchUpInside];
    if (_handler)
        [self addTarget:self action:@selector(charon_fire) forControlEvents:UIControlEventTouchUpInside];
}

- (void)charon_fire
{
    if (_handler)
        _handler();
}

- (UIColor *)fill
{
    return _fill;
}

- (void)setFill:(UIColor *)fill
{
    _fill = fill;
    [self setNeedsDisplay];
}

- (BOOL)expanded
{
    return _expanded;
}

- (void)setExpanded:(BOOL)expanded
{
    _expanded = expanded;
    [self setNeedsDisplay];
}

- (BOOL)marked
{
    return _marked;
}

- (void)setMarked:(BOOL)marked
{
    _marked = marked;
    [self setNeedsDisplay];
}

- (void)tintColorDidChange
{
    [super tintColorDidChange];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGRect bounds = self.bounds;
    UIColor *tint = self.tintColor ?: [UIColor blueColor];
    UIColor *gray = charon_semantic_color(CharonSemanticColorTertiaryLabel);
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    switch (_kind) {
    case 0: {
        path.lineWidth = 2.5;
        [path moveToPoint:CGPointMake(2.5, 9.5)];
        [path addLineToPoint:CGPointMake(7.5, 15)];
        [path addLineToPoint:CGPointMake(16.5, 2.5)];
        [tint setStroke];
        [path stroke];
        break;
    }
    case 1:
    case 6: {
        CGFloat inset = 4;
        path.lineWidth = 2;
        if (_expanded) {
            [path moveToPoint:CGPointMake(2, inset + 1)];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - inset - 1)];
            [path addLineToPoint:CGPointMake(CGRectGetMaxX(bounds) - 2, inset + 1)];
        } else {
            [path moveToPoint:CGPointMake(CGRectGetMidX(bounds) - 2.5, 1)];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds) + 2.5, CGRectGetMidY(bounds))];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds) - 2.5, CGRectGetMaxY(bounds) - 1)];
        }
        [(_kind == 1 ? gray : tint) setStroke];
        [path stroke];
        break;
    }
    case 2:
    case 3:
    case 5: {
        CGRect circle = CGRectInset(bounds, 2, 2);
        UIBezierPath *disc = [UIBezierPath bezierPathWithOvalInRect:circle];
        if (_kind == 5 && !_marked) {
            disc.lineWidth = 1.5;
            [gray setStroke];
            [disc stroke];
            break;
        }
        [(_fill ?: _kind == 2 ? [UIColor redColor] : _kind == 3 ? [UIColor greenColor] : tint) setFill];
        [disc fill];
        path.lineWidth = 2;
        [[UIColor whiteColor] setStroke];
        if (_kind == 2) {
            [path moveToPoint:CGPointMake(CGRectGetMidX(bounds) - 5, CGRectGetMidY(bounds))];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds) + 5, CGRectGetMidY(bounds))];
        } else if (_kind == 3) {
            [path moveToPoint:CGPointMake(CGRectGetMidX(bounds) - 5, CGRectGetMidY(bounds))];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds) + 5, CGRectGetMidY(bounds))];
            [path moveToPoint:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds) - 5)];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds) + 5)];
        } else {
            [path moveToPoint:CGPointMake(CGRectGetMidX(bounds) - 5, CGRectGetMidY(bounds))];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds) - 1.5, CGRectGetMidY(bounds) + 4)];
            [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds) + 5, CGRectGetMidY(bounds) - 4)];
        }
        [path stroke];
        break;
    }
    case 4: {
        path.lineWidth = 2;
        for (CGFloat y = 3; y <= bounds.size.height - 3; y += 4.5) {
            [path moveToPoint:CGPointMake(3, y)];
            [path addLineToPoint:CGPointMake(bounds.size.width - 3, y)];
        }
        [gray setStroke];
        [path stroke];
        break;
    }
    }
}

@end

@implementation UICellAccessory {
@private
    UICellAccessoryDisplayedState _displayedState;
    BOOL _hidden;
    CGFloat _reservedLayoutWidth;
    UIColor *_tintColor;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _reservedLayoutWidth = [self charon_defaultReservedWidth];
        _displayedState = [self charon_defaultDisplayedState];
    }
    return self;
}

- (CGFloat)charon_defaultReservedWidth
{
    return UICellAccessoryStandardDimension;
}

- (UICellAccessoryDisplayedState)charon_defaultDisplayedState
{
    return UICellAccessoryDisplayedAlways;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _displayedState = (UICellAccessoryDisplayedState)[coder decodeIntegerForKey:@"displayedState"];
        _hidden = [coder decodeBoolForKey:@"hidden"];
        if ([coder containsValueForKey:@"reservedLayoutWidth"])
            _reservedLayoutWidth = (CGFloat)[coder decodeDoubleForKey:@"reservedLayoutWidth"];
        _tintColor = [coder decodeObjectOfClass:[UIColor class] forKey:@"tintColor"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_displayedState forKey:@"displayedState"];
    [coder encodeBool:_hidden forKey:@"hidden"];
    [coder encodeDouble:_reservedLayoutWidth forKey:@"reservedLayoutWidth"];
    [coder encodeObject:_tintColor forKey:@"tintColor"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessory *copy = [[[self class] allocWithZone:zone] init];
    copy->_displayedState = _displayedState;
    copy->_hidden = _hidden;
    copy->_reservedLayoutWidth = _reservedLayoutWidth;
    copy->_tintColor = _tintColor;
    return copy;
}

- (UICellAccessoryDisplayedState)displayedState
{
    return _displayedState;
}

- (void)setDisplayedState:(UICellAccessoryDisplayedState)displayedState
{
    _displayedState = displayedState;
}

- (BOOL)isHidden
{
    return _hidden;
}

- (void)setHidden:(BOOL)hidden
{
    _hidden = hidden;
}

- (CGFloat)reservedLayoutWidth
{
    return _reservedLayoutWidth;
}

- (void)setReservedLayoutWidth:(CGFloat)reservedLayoutWidth
{
    _reservedLayoutWidth = reservedLayoutWidth;
}

- (UIColor *)tintColor
{
    return _tintColor;
}

- (void)setTintColor:(UIColor *)tintColor
{
    _tintColor = tintColor;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isMemberOfClass:[self class]])
        return NO;
    UICellAccessory *other = object;
    return _displayedState == other->_displayedState && _hidden == other->_hidden && _reservedLayoutWidth == other->_reservedLayoutWidth && (_tintColor == other->_tintColor || [_tintColor isEqual:other->_tintColor]);
}

- (NSUInteger)hash
{
    return [NSStringFromClass([self class]) hash] ^ ((NSUInteger)_displayedState << 4) ^ (_hidden ? 8u : 0u) ^ (NSUInteger)_reservedLayoutWidth;
}

- (NSInteger)charon_order
{
    return 0;
}

- (BOOL)charon_isLeading
{
    return NO;
}

- (CGFloat)charon_naturalWidth
{
    return 24;
}

- (CGFloat)charon_width
{
    return _reservedLayoutWidth == UICellAccessoryStandardDimension ? [self charon_naturalWidth] : _reservedLayoutWidth > 0 ? _reservedLayoutWidth : [self charon_naturalWidth];
}

- (CharonAccessoryView *)charon_baseViewOfKind:(NSInteger)kind size:(CGSize)size
{
    CharonAccessoryView *view = [[CharonAccessoryView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    view.kind = kind;
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    if (_tintColor)
        view.tintColor = _tintColor;
    return view;
}

- (UIView *)charon_makeView
{
    return nil;
}

@end

@implementation UICellAccessoryDisclosureIndicator

- (CGFloat)charon_defaultReservedWidth
{
    return 0;
}

- (CGFloat)charon_naturalWidth
{
    return 14;
}

- (UIView *)charon_makeView
{
    return [self charon_baseViewOfKind:1 size:CGSizeMake(14, 14)];
}

- (NSInteger)charon_order
{
    return 3;
}

@end

@implementation UICellAccessoryCheckmark

- (UIView *)charon_makeView
{
    return [self charon_baseViewOfKind:0 size:CGSizeMake(19, 18)];
}

- (NSInteger)charon_order
{
    return 2;
}

@end

@implementation UICellAccessoryDelete {
@private
    UIColor *_backgroundColor;
    void (^_actionHandler)(void);
}

- (UICellAccessoryDisplayedState)charon_defaultDisplayedState
{
    return UICellAccessoryDisplayedWhenEditing;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        _backgroundColor = [coder decodeObjectOfClass:[UIColor class] forKey:@"backgroundColor"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_backgroundColor forKey:@"backgroundColor"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryDelete *copy = [super copyWithZone:zone];
    copy->_backgroundColor = _backgroundColor;
    copy->_actionHandler = [_actionHandler copy];
    return copy;
}

- (UIColor *)backgroundColor
{
    return _backgroundColor;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    _backgroundColor = backgroundColor;
}

- (void (^)(void))actionHandler
{
    return _actionHandler;
}

- (void)setActionHandler:(void (^)(void))actionHandler
{
    _actionHandler = [actionHandler copy];
}

- (BOOL)charon_isLeading
{
    return YES;
}

- (NSInteger)charon_order
{
    return 1;
}

- (BOOL)isEqual:(id)object
{
    return [super isEqual:object] && ((_backgroundColor == ((UICellAccessoryDelete *)object)->_backgroundColor) || [_backgroundColor isEqual:((UICellAccessoryDelete *)object)->_backgroundColor]) &&
           _actionHandler == ((UICellAccessoryDelete *)object)->_actionHandler;
}

- (UIView *)charon_makeView
{
    CharonAccessoryView *view = [self charon_baseViewOfKind:2 size:CGSizeMake(26, 26)];
    view.fill = _backgroundColor;
    view.charon_handler = _actionHandler;
    return view;
}

@end

@implementation UICellAccessoryInsert {
@private
    UIColor *_backgroundColor;
    void (^_actionHandler)(void);
}

- (UICellAccessoryDisplayedState)charon_defaultDisplayedState
{
    return UICellAccessoryDisplayedWhenEditing;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        _backgroundColor = [coder decodeObjectOfClass:[UIColor class] forKey:@"backgroundColor"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_backgroundColor forKey:@"backgroundColor"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryInsert *copy = [super copyWithZone:zone];
    copy->_backgroundColor = _backgroundColor;
    copy->_actionHandler = [_actionHandler copy];
    return copy;
}

- (UIColor *)backgroundColor
{
    return _backgroundColor;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    _backgroundColor = backgroundColor;
}

- (void (^)(void))actionHandler
{
    return _actionHandler;
}

- (void)setActionHandler:(void (^)(void))actionHandler
{
    _actionHandler = [actionHandler copy];
}

- (BOOL)charon_isLeading
{
    return YES;
}

- (NSInteger)charon_order
{
    return 1;
}

- (BOOL)isEqual:(id)object
{
    return [super isEqual:object] && ((_backgroundColor == ((UICellAccessoryInsert *)object)->_backgroundColor) || [_backgroundColor isEqual:((UICellAccessoryInsert *)object)->_backgroundColor]) &&
           _actionHandler == ((UICellAccessoryInsert *)object)->_actionHandler;
}

- (UIView *)charon_makeView
{
    CharonAccessoryView *view = [self charon_baseViewOfKind:3 size:CGSizeMake(26, 26)];
    view.fill = _backgroundColor;
    view.charon_handler = _actionHandler;
    return view;
}

@end

@implementation UICellAccessoryReorder {
@private
    BOOL _showsVerticalSeparator;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (UICellAccessoryDisplayedState)charon_defaultDisplayedState
{
    return UICellAccessoryDisplayedWhenEditing;
}

- (instancetype)init
{
    if ((self = [super init]))
        _showsVerticalSeparator = YES;
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        _showsVerticalSeparator = [coder containsValueForKey:@"showsVerticalSeparator"] ? [coder decodeBoolForKey:@"showsVerticalSeparator"] : YES;
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeBool:_showsVerticalSeparator forKey:@"showsVerticalSeparator"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryReorder *copy = [super copyWithZone:zone];
    copy->_showsVerticalSeparator = _showsVerticalSeparator;
    return copy;
}

- (BOOL)showsVerticalSeparator
{
    return _showsVerticalSeparator;
}

- (void)setShowsVerticalSeparator:(BOOL)showsVerticalSeparator
{
    _showsVerticalSeparator = showsVerticalSeparator;
}

- (BOOL)isEqual:(id)object
{
    return [super isEqual:object] && _showsVerticalSeparator == ((UICellAccessoryReorder *)object)->_showsVerticalSeparator;
}

- (UIView *)charon_makeView
{
    return [self charon_baseViewOfKind:4 size:CGSizeMake(27, 15)];
}

- (NSInteger)charon_order
{
    return 4;
}

@end

@implementation UICellAccessoryMultiselect {
@private
    UIColor *_backgroundColor;
}

- (UICellAccessoryDisplayedState)charon_defaultDisplayedState
{
    return UICellAccessoryDisplayedWhenEditing;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        _backgroundColor = [coder decodeObjectOfClass:[UIColor class] forKey:@"backgroundColor"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_backgroundColor forKey:@"backgroundColor"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryMultiselect *copy = [super copyWithZone:zone];
    copy->_backgroundColor = _backgroundColor;
    return copy;
}

- (UIColor *)backgroundColor
{
    return _backgroundColor;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    _backgroundColor = backgroundColor;
}

- (BOOL)charon_isLeading
{
    return YES;
}

- (NSInteger)charon_order
{
    return 1;
}

- (BOOL)isEqual:(id)object
{
    return [super isEqual:object] && ((_backgroundColor == ((UICellAccessoryMultiselect *)object)->_backgroundColor) || [_backgroundColor isEqual:((UICellAccessoryMultiselect *)object)->_backgroundColor]);
}

- (UIView *)charon_makeView
{
    CharonAccessoryView *view = [self charon_baseViewOfKind:5 size:CGSizeMake(26, 26)];
    view.fill = _backgroundColor;
    return view;
}

@end

@implementation UICellAccessoryOutlineDisclosure {
@private
    UICellAccessoryOutlineDisclosureStyle _style;
    void (^_actionHandler)(void);
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (CGFloat)charon_defaultReservedWidth
{
    return 0;
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryOutlineDisclosure *copy = [super copyWithZone:zone];
    copy->_style = _style;
    copy->_actionHandler = [_actionHandler copy];
    return copy;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        _style = (UICellAccessoryOutlineDisclosureStyle)[coder decodeIntegerForKey:@"style"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:_style forKey:@"style"];
}

- (UICellAccessoryOutlineDisclosureStyle)style
{
    return _style;
}

- (void)setStyle:(UICellAccessoryOutlineDisclosureStyle)style
{
    _style = style;
}

- (void (^)(void))actionHandler
{
    return _actionHandler;
}

- (void)setActionHandler:(void (^)(void))actionHandler
{
    _actionHandler = [actionHandler copy];
}

- (CGFloat)charon_naturalWidth
{
    return 14;
}

- (BOOL)charon_isLeading
{
    return YES;
}

- (NSInteger)charon_order
{
    return 2;
}

- (BOOL)isEqual:(id)object
{
    return [super isEqual:object] && _style == ((UICellAccessoryOutlineDisclosure *)object)->_style && _actionHandler == ((UICellAccessoryOutlineDisclosure *)object)->_actionHandler;
}

- (UIView *)charon_makeView
{
    CharonAccessoryView *view = [self charon_baseViewOfKind:6 size:CGSizeMake(14, 14)];
    view.charon_handler = _actionHandler;
    return view;
}

@end

@implementation UICellAccessoryLabel {
@private
    NSString *_text;
    UIFont *_font;
    BOOL _adjustsFontForContentSizeCategory;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (CGFloat)charon_defaultReservedWidth
{
    return 0;
}

- (instancetype)initWithText:(NSString *)text
{
    if (!text)
        [NSException raise:NSInternalInconsistencyException format:@"Invalid parameter not satisfying: text != nil"];
    if ((self = [super init])) {
        _text = [text copy];
        _font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _adjustsFontForContentSizeCategory = YES;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithText:@""];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *text = [coder decodeObjectOfClass:[NSString class] forKey:@"text"] ?: @"";
    if ((self = [self initWithText:text])) {
        UIFont *font = [coder decodeObjectOfClass:[UIFont class] forKey:@"font"];
        if (font)
            _font = font;
        _adjustsFontForContentSizeCategory = [coder containsValueForKey:@"adjustsFontForContentSizeCategory"] ? [coder decodeBoolForKey:@"adjustsFontForContentSizeCategory"] : YES;
        [self setDisplayedState:(UICellAccessoryDisplayedState)[coder decodeIntegerForKey:@"displayedState"]];
        [self setHidden:[coder decodeBoolForKey:@"hidden"]];
        if ([coder containsValueForKey:@"reservedLayoutWidth"])
            [self setReservedLayoutWidth:(CGFloat)[coder decodeDoubleForKey:@"reservedLayoutWidth"]];
        [self setTintColor:[coder decodeObjectOfClass:[UIColor class] forKey:@"tintColor"]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_text forKey:@"text"];
    [coder encodeObject:_font forKey:@"font"];
    [coder encodeBool:_adjustsFontForContentSizeCategory forKey:@"adjustsFontForContentSizeCategory"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryLabel *copy = [super copyWithZone:zone];
    copy->_text = _text;
    copy->_font = _font;
    copy->_adjustsFontForContentSizeCategory = _adjustsFontForContentSizeCategory;
    return copy;
}

- (NSString *)text
{
    return _text;
}

- (UIFont *)font
{
    return _font;
}

- (void)setFont:(UIFont *)font
{
    _font = font;
}

- (BOOL)adjustsFontForContentSizeCategory
{
    return _adjustsFontForContentSizeCategory;
}

- (void)setAdjustsFontForContentSizeCategory:(BOOL)adjustsFontForContentSizeCategory
{
    _adjustsFontForContentSizeCategory = adjustsFontForContentSizeCategory;
}

- (CGSize)charon_labelSize
{
    UILabel *label = [[UILabel alloc] init];
    label.font = _font;
    label.text = _text;
    CGSize size = [label sizeThatFits:CGSizeMake(10000, 10000)];
    CGFloat scale = charon_screen_scale();
    return CGSizeMake(charon_pixel_ceil(size.width, scale), charon_pixel_ceil(size.height, scale) + 0.5);
}

- (CGFloat)charon_naturalWidth
{
    return [self charon_labelSize].width;
}

- (BOOL)isEqual:(id)object
{
    UICellAccessoryLabel *other = object;
    return [super isEqual:object] && [_text isEqual:other->_text] && _font == other->_font && _adjustsFontForContentSizeCategory == other->_adjustsFontForContentSizeCategory;
}

- (UIView *)charon_makeView
{
    UILabel *label = [[UILabel alloc] init];
    label.font = _font;
    label.text = _text;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [self tintColor] ?: charon_semantic_color(CharonSemanticColorSecondaryLabel);
    label.frame = CGRectMake(0, 0, [self charon_labelSize].width, [self charon_labelSize].height);
    return label;
}

- (NSInteger)charon_order
{
    return 1;
}

@end

@implementation UICellAccessoryCustomView {
@private
    UIView *_customView;
    UICellAccessoryPlacement _placement;
    BOOL _maintainsFixedSize;
    UICellAccessoryPosition _position;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCustomView:(UIView *)customView placement:(UICellAccessoryPlacement)placement
{
    if ((self = [super init])) {
        _customView = customView;
        _placement = placement;
        _position = charon_default_position();
    }
    return self;
}

- (instancetype)init
{
    return [self initWithCustomView:[[UIView alloc] init] placement:UICellAccessoryPlacementTrailing];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    UIView *view = [coder decodeObjectOfClass:[UIView class] forKey:@"customView"] ?: [[UIView alloc] init];
    if ((self = [self initWithCustomView:view placement:(UICellAccessoryPlacement)[coder decodeIntegerForKey:@"placement"]])) {
        _maintainsFixedSize = [coder decodeBoolForKey:@"maintainsFixedSize"];
        [self setDisplayedState:(UICellAccessoryDisplayedState)[coder decodeIntegerForKey:@"displayedState"]];
        [self setHidden:[coder decodeBoolForKey:@"hidden"]];
        if ([coder containsValueForKey:@"reservedLayoutWidth"])
            [self setReservedLayoutWidth:(CGFloat)[coder decodeDoubleForKey:@"reservedLayoutWidth"]];
        [self setTintColor:[coder decodeObjectOfClass:[UIColor class] forKey:@"tintColor"]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_customView forKey:@"customView"];
    [coder encodeInteger:_placement forKey:@"placement"];
    [coder encodeBool:_maintainsFixedSize forKey:@"maintainsFixedSize"];
}

- (id)copyWithZone:(NSZone *)zone
{
    UICellAccessoryCustomView *copy = [super copyWithZone:zone];
    copy->_customView = _customView;
    copy->_placement = _placement;
    copy->_maintainsFixedSize = _maintainsFixedSize;
    copy->_position = [_position copy];
    return copy;
}

- (UIView *)customView
{
    return _customView;
}

- (UICellAccessoryPlacement)placement
{
    return _placement;
}

- (BOOL)maintainsFixedSize
{
    return _maintainsFixedSize;
}

- (void)setMaintainsFixedSize:(BOOL)maintainsFixedSize
{
    _maintainsFixedSize = maintainsFixedSize;
}

- (UICellAccessoryPosition)position
{
    return _position;
}

- (void)setPosition:(UICellAccessoryPosition)position
{
    UICellAccessoryPosition copied = [position copy];
    _position = copied ?: charon_default_position();
}

- (BOOL)charon_isLeading
{
    return _placement == UICellAccessoryPlacementLeading;
}

- (BOOL)charon_hasDefaultPosition
{
    return _position == charon_default_position();
}

- (NSInteger)charon_order
{
    return _placement == UICellAccessoryPlacementLeading ? 3 : 0;
}

- (BOOL)isEqual:(id)object
{
    UICellAccessoryCustomView *other = object;
    return [super isEqual:object] && _customView == other->_customView && _placement == other->_placement && _maintainsFixedSize == other->_maintainsFixedSize && _position == other->_position;
}

- (UIView *)charon_makeView
{
    return _customView;
}

@end
