#import "CharonSwipeViews.h"

static const CGFloat CharonSwipeMinimumWidth = 74;
static const CGFloat CharonSwipePadding = 15;

CGFloat charon_swipe_width(NSString *title)
{
    CGFloat text = title.length ? ceilf([title sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15]}].width) : 0;
    return MAX(CharonSwipeMinimumWidth, text + 2 * CharonSwipePadding);
}

@implementation CharonSwipeItem
@synthesize title = _title;
@synthesize image = _image;
@synthesize color = _color;
@synthesize action = _action;
@synthesize width = _width;

@end

@implementation CharonSwipeButton {
    UILabel *_label;
    UIImageView *_icon;
}
@synthesize item = _item;

- (instancetype)initWithItem:(CharonSwipeItem *)item
{
    if ((self = [super initWithFrame:CGRectZero])) {
        _item = item;
        self.backgroundColor = item.color ?: [UIColor colorWithRed:0.78f green:0.78f blue:0.8f alpha:1];
        self.clipsToBounds = YES;
        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.text = item.title;
        _label.font = [UIFont systemFontOfSize:15];
        _label.textColor = [UIColor whiteColor];
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_label];
        if (item.image) {
            _icon = [[UIImageView alloc] initWithImage:item.image];
            _icon.contentMode = UIViewContentModeScaleAspectFit;
            [self addSubview:_icon];
        }
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat labelHeight = 20;
    if (_icon) {
        CGFloat side = MIN(25, bounds.size.height - labelHeight - 10);
        CGFloat top = floorf((bounds.size.height - side - labelHeight - 4) / 2);
        _icon.frame = CGRectMake(floorf((bounds.size.width - side) / 2), top, side, side);
        _label.frame = CGRectMake(0, top + side + 4, bounds.size.width, labelHeight);
    } else {
        _label.frame = CGRectMake(0, floorf((bounds.size.height - labelHeight) / 2), bounds.size.width, labelHeight);
    }
}

@end

@implementation CharonSwipeContainer
@synthesize buttons = _buttons;
@synthesize side = _side;
@synthesize totalWidth = _totalWidth;


- (void)setOffset:(CGFloat)offset inCellWidth:(CGFloat)cellWidth height:(CGFloat)height
{
    CGFloat shown = fabsf(offset);
    self.frame = CGRectMake(_side < 0 ? cellWidth - shown : 0, 0, shown, height);
    CGFloat scale = shown <= _totalWidth || _totalWidth == 0 ? (_totalWidth == 0 ? 0 : shown / _totalWidth) : 1;
    CGFloat extra = shown > _totalWidth ? shown - _totalWidth : 0;
    NSUInteger count = _buttons.count;
    CGFloat x = 0;
    for (NSUInteger visual = 0; visual < count; visual++) {
        NSUInteger index = _side < 0 ? count - 1 - visual : visual;
        CharonSwipeButton *button = _buttons[index];
        CGFloat width = button.item.width * scale + (index == 0 ? extra : 0);
        button.frame = CGRectMake(x, 0, width, height);
        x += width;
    }
}

@end

