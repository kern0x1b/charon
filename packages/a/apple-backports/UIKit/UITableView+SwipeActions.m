#import "CharonSwipe.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static const char charon_controller_key;
static const CGFloat CharonSwipeMinimumWidth = 74;
static const CGFloat CharonSwipePadding = 15;
static const CGFloat CharonSwipeFullSwipeFraction = 0.65;
static const NSTimeInterval CharonSwipeDuration = 0.28;

BOOL charon_swipe_class_is_backport(Class cls)
{
    Dl_info info;
    if (!cls || !dladdr((__bridge const void *)cls, &info) || !info.dli_fname)
        return NO;
    return strstr(info.dli_fname, "UIKitBackports") != NULL;
}

@interface CharonSwipeItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) id action;
@property (nonatomic) CGFloat width;
@end

@implementation CharonSwipeItem
@synthesize title = _title;
@synthesize image = _image;
@synthesize color = _color;
@synthesize action = _action;
@synthesize width = _width;

@end

@interface CharonSwipeButton : UIControl
@property (nonatomic, strong) CharonSwipeItem *item;
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

@interface CharonSwipeContainer : UIView
@property (nonatomic, strong) NSArray<CharonSwipeButton *> *buttons;
@property (nonatomic) NSInteger side;
@property (nonatomic) CGFloat totalWidth;
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

@interface CharonSwipeController : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UITableView *table;
@property (nonatomic, strong) UIPanGestureRecognizer *pan;
@property (nonatomic, strong) UITapGestureRecognizer *closeTap;
@property (nonatomic, strong) NSIndexPath *path;
@property (nonatomic, weak) UITableViewCell *cell;
@property (nonatomic, strong) NSArray<CharonSwipeItem *> *items;
@property (nonatomic, strong) CharonSwipeContainer *container;
@property (nonatomic, strong) NSArray<UIView *> *movers;
@property (nonatomic) NSInteger side;
@property (nonatomic) CGFloat total;
@property (nonatomic) CGFloat offset;
@property (nonatomic) BOOL fullSwipe;
@property (nonatomic) BOOL resting;
@property (nonatomic, strong) NSIndexPath *pendingPath;
@property (nonatomic, strong) NSArray<CharonSwipeItem *> *pendingItems;
@property (nonatomic) NSInteger pendingSide;
@property (nonatomic) BOOL pendingFullSwipe;
- (BOOL)isOpen;
- (void)closeAnimated:(BOOL)animated;
@end

@implementation CharonSwipeController
@synthesize table = _table;
@synthesize pan = _pan;
@synthesize closeTap = _closeTap;
@synthesize path = _path;
@synthesize cell = _cell;
@synthesize items = _items;
@synthesize container = _container;
@synthesize movers = _movers;
@synthesize side = _side;
@synthesize total = _total;
@synthesize offset = _offset;
@synthesize fullSwipe = _fullSwipe;
@synthesize resting = _resting;
@synthesize pendingPath = _pendingPath;
@synthesize pendingItems = _pendingItems;
@synthesize pendingSide = _pendingSide;
@synthesize pendingFullSwipe = _pendingFullSwipe;


- (instancetype)initWithTable:(UITableView *)table
{
    if ((self = [super init])) {
        _table = table;
        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        _pan.delegate = self;
        _pan.maximumNumberOfTouches = 1;
        [table addGestureRecognizer:_pan];
        _closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        _closeTap.delegate = self;
        _closeTap.enabled = NO;
        [table addGestureRecognizer:_closeTap];
        [table.panGestureRecognizer addTarget:self action:@selector(scrolled:)];
    }
    return self;
}

- (BOOL)isOpen
{
    return _container != nil;
}

- (BOOL)coversRowActions
{
    return charon_swipe_class_is_backport(NSClassFromString(@"UITableViewRowAction"));
}

- (BOOL)coversConfigurations
{
    return charon_swipe_class_is_backport(NSClassFromString(@"UISwipeActionsConfiguration"));
}

- (CGFloat)widthOfTitle:(NSString *)title hasImage:(BOOL)hasImage
{
    CGFloat text = title.length ? ceilf([title sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15]}].width) : 0;
    return MAX(CharonSwipeMinimumWidth, text + 2 * CharonSwipePadding);
}

- (BOOL)rowAllowsSwipe:(NSIndexPath *)path
{
    id source = _table.dataSource;
    if ([source respondsToSelector:@selector(tableView:canEditRowAtIndexPath:)] && ![source tableView:_table canEditRowAtIndexPath:path])
        return NO;
    id delegate = _table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:editingStyleForRowAtIndexPath:)] && [delegate tableView:_table editingStyleForRowAtIndexPath:path] == UITableViewCellEditingStyleNone)
        return NO;
    return YES;
}

- (NSArray<CharonSwipeItem *> *)itemsForSide:(NSInteger)side path:(NSIndexPath *)path fullSwipe:(BOOL *)fullSwipe
{
    id delegate = _table.delegate;
    NSMutableArray *items = [NSMutableArray array];
    *fullSwipe = NO;
    SEL configuration = side < 0 ? @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:) : @selector(tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:);
    if ([self coversConfigurations] && [delegate respondsToSelector:configuration]) {
        UISwipeActionsConfiguration *(*send)(id, SEL, UITableView *, NSIndexPath *) = (UISwipeActionsConfiguration *(*)(id, SEL, UITableView *, NSIndexPath *))objc_msgSend;
        UISwipeActionsConfiguration *result = send(delegate, configuration, _table, path);
        for (UIContextualAction *action in result.actions) {
            CharonSwipeItem *item = [[CharonSwipeItem alloc] init];
            item.title = action.title;
            item.image = action.image;
            item.color = action.backgroundColor;
            item.action = action;
            item.width = [self widthOfTitle:action.title hasImage:action.image != nil];
            [items addObject:item];
        }
        *fullSwipe = result.performsFirstActionWithFullSwipe && items.count > 0;
        return items;
    }
    if (side < 0 && [self coversRowActions] && [delegate respondsToSelector:@selector(tableView:editActionsForRowAtIndexPath:)]) {
        for (UITableViewRowAction *action in [delegate tableView:_table editActionsForRowAtIndexPath:path]) {
            CharonSwipeItem *item = [[CharonSwipeItem alloc] init];
            item.title = action.title;
            item.color = action.backgroundColor;
            item.action = action;
            item.width = [self widthOfTitle:action.title hasImage:NO];
            [items addObject:item];
        }
        *fullSwipe = items.count > 0;
    }
    return items;
}

- (BOOL)delegateHasActionsForSide:(NSInteger)side
{
    id delegate = _table.delegate;
    if (side < 0)
        return ([self coversConfigurations] && [delegate respondsToSelector:@selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:)]) ||
            ([self coversRowActions] && [delegate respondsToSelector:@selector(tableView:editActionsForRowAtIndexPath:)]);
    return [self coversConfigurations] && [delegate respondsToSelector:@selector(tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:)];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer
{
    if (recognizer != _pan)
        return [self isOpen];
    _pendingItems = nil;
    if (_table.isEditing)
        return NO;
    CGPoint velocity = [_pan velocityInView:_table];
    if (fabsf(velocity.x) <= fabsf(velocity.y))
        return NO;
    NSIndexPath *path = [_table indexPathForRowAtPoint:[_pan locationInView:_table]];
    if (!path || ![_table cellForRowAtIndexPath:path])
        return NO;
    if ([self isOpen])
        return [path isEqual:_path];
    if (![self rowAllowsSwipe:path])
        return NO;
    NSInteger side = velocity.x < 0 ? -1 : 1;
    if (![self delegateHasActionsForSide:side])
        return NO;
    BOOL fullSwipe = NO;
    NSArray *items = [self itemsForSide:side path:path fullSwipe:&fullSwipe];
    if (!items.count)
        return NO;
    _pendingPath = path;
    _pendingSide = side;
    _pendingItems = items;
    _pendingFullSwipe = fullSwipe;
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    if (recognizer == _closeTap)
        return [self isOpen] && ![touch.view isDescendantOfView:_container];
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other
{
    return recognizer == _pan && other == _table.panGestureRecognizer;
}

- (void)scrolled:(UIPanGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateBegan && [self isOpen] && _pan.state != UIGestureRecognizerStateBegan && _pan.state != UIGestureRecognizerStateChanged)
        [self closeAnimated:YES];
}

- (void)tapped:(UITapGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateEnded)
        [self closeAnimated:YES];
}

- (void)applyOffset:(CGFloat)offset
{
    _offset = offset;
    UITableViewCell *cell = _cell;
    if (!cell)
        return;
    for (UIView *view in _movers)
        view.transform = CGAffineTransformMakeTranslation(offset, 0);
    [_container setOffset:offset inCellWidth:cell.bounds.size.width height:cell.contentView.frame.size.height];
}

- (void)beginOnPath:(NSIndexPath *)path side:(NSInteger)side items:(NSArray<CharonSwipeItem *> *)items fullSwipe:(BOOL)fullSwipe
{
    UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
    _path = path;
    _cell = cell;
    _side = side;
    _items = items;
    _fullSwipe = fullSwipe;
    CGFloat total = 0;
    NSMutableArray *buttons = [NSMutableArray array];
    for (CharonSwipeItem *item in items) {
        total += item.width;
        CharonSwipeButton *button = [[CharonSwipeButton alloc] initWithItem:item];
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
    }
    _total = total;
    _container = [[CharonSwipeContainer alloc] initWithFrame:CGRectZero];
    _container.side = side;
    _container.totalWidth = total;
    _container.buttons = buttons;
    _container.clipsToBounds = YES;
    for (UIView *button in buttons)
        [_container addSubview:button];
    [cell insertSubview:_container aboveSubview:cell.contentView];
    NSMutableArray *movers = [NSMutableArray array];
    for (UIView *view in cell.subviews) {
        if (view == _container || view == cell.backgroundView || view == cell.selectedBackgroundView)
            continue;
        if (view.frame.size.height <= 2 && view != cell.contentView)
            continue;
        [movers addObject:view];
    }
    _movers = movers;
    _closeTap.enabled = YES;
    id delegate = _table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:willBeginEditingRowAtIndexPath:)])
        [delegate tableView:_table willBeginEditingRowAtIndexPath:path];
}

- (void)finishClose
{
    for (UIView *view in _movers)
        view.transform = CGAffineTransformIdentity;
    [_container removeFromSuperview];
    NSIndexPath *path = _path;
    _container = nil;
    _movers = nil;
    _items = nil;
    _cell = nil;
    _path = nil;
    _offset = 0;
    _resting = NO;
    _closeTap.enabled = NO;
    id delegate = _table.delegate;
    if (path && [delegate respondsToSelector:@selector(tableView:didEndEditingRowAtIndexPath:)])
        [delegate tableView:_table didEndEditingRowAtIndexPath:path];
}

- (void)settleAt:(CGFloat)offset animated:(BOOL)animated completion:(void (^)(void))completion
{
    void (^apply)(void) = ^{
        [self applyOffset:offset];
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (completion)
            completion();
    };
    if (animated)
        [UIView animateWithDuration:CharonSwipeDuration delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:apply completion:done];
    else {
        apply();
        done(YES);
    }
}

- (void)closeAnimated:(BOOL)animated
{
    if (![self isOpen])
        return;
    _resting = NO;
    [self settleAt:0 animated:animated completion:^{
        if (!self->_resting)
            [self finishClose];
    }];
}

- (void)openAnimated:(BOOL)animated
{
    _resting = YES;
    [self settleAt:_side * _total animated:animated completion:nil];
}

- (void)perform:(CharonSwipeItem *)item
{
    NSIndexPath *path = _path;
    id action = item.action;
    if ([action isKindOfClass:[UITableViewRowAction class]]) {
        [(UITableViewRowAction *)action charon_performForIndexPath:path];
        [self closeAnimated:YES];
        return;
    }
    UIContextualAction *contextual = action;
    UIView *source = nil;
    for (CharonSwipeButton *button in _container.buttons)
        if (button.item == item)
            source = button;
    __weak CharonSwipeController *weakSelf = self;
    if (contextual.handler)
        contextual.handler(contextual, source, ^(BOOL performed) {
            [weakSelf closeAnimated:YES];
        });
    else
        [self closeAnimated:YES];
}

- (void)buttonTapped:(CharonSwipeButton *)button
{
    [self perform:button.item];
}

- (void)panned:(UIPanGestureRecognizer *)recognizer
{
    CGFloat translation = [recognizer translationInView:_table].x;
    switch (recognizer.state) {
    case UIGestureRecognizerStateBegan: {
        _table.panGestureRecognizer.enabled = NO;
        _table.panGestureRecognizer.enabled = YES;
        if ([self isOpen] || !_pendingItems)
            break;
        [self beginOnPath:_pendingPath side:_pendingSide items:_pendingItems fullSwipe:_pendingFullSwipe];
        _pendingItems = nil;
        _resting = NO;
        break;
    }
    case UIGestureRecognizerStateChanged: {
        if (![self isOpen])
            return;
        CGFloat base = _resting ? _side * _total : 0;
        CGFloat offset = base + translation;
        if (_side < 0)
            offset = MIN(0, offset);
        else
            offset = MAX(0, offset);
        CGFloat limit = _table.bounds.size.width;
        if (fabsf(offset) > limit)
            offset = _side * limit;
        if (!_fullSwipe && fabsf(offset) > _total)
            offset = _side * (_total + (fabsf(offset) - _total) * 0.25f);
        [self applyOffset:offset];
        break;
    }
    case UIGestureRecognizerStateEnded: {
        if (![self isOpen])
            return;
        CGFloat velocity = [recognizer velocityInView:_table].x;
        CGFloat shown = fabsf(_offset);
        BOOL towardsOpen = velocity * _side > 0;
        if (_fullSwipe && shown > CharonSwipeFullSwipeFraction * _table.bounds.size.width) {
            CharonSwipeItem *first = _items[0];
            __weak CharonSwipeController *weakSelf = self;
            [self settleAt:_side * _table.bounds.size.width animated:YES completion:^{
                [weakSelf perform:first];
            }];
        } else if (fabsf(velocity) > 300 ? towardsOpen : shown > _total / 2) {
            [self openAnimated:YES];
        } else {
            [self closeAnimated:YES];
        }
        break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        if ([self isOpen])
            _resting ? [self openAnimated:YES] : [self closeAnimated:YES];
        break;
    default:
        break;
    }
}

@end

static CharonSwipeController *charon_controller(UITableView *table, BOOL create)
{
    CharonSwipeController *controller = objc_getAssociatedObject(table, &charon_controller_key);
    if (!controller && create) {
        controller = [[CharonSwipeController alloc] initWithTable:table];
        objc_setAssociatedObject(table, &charon_controller_key, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return controller;
}

@implementation UITableView (CharonSwipe)

- (void)charon_installSwipeActions
{
    charon_controller(self, YES);
}

@end

@interface CharonSwipeInstaller : NSObject
@end

@implementation CharonSwipeInstaller

+ (void)load
{
    if (![UITableViewRowAction class] || ![UISwipeActionsConfiguration class])
        return;
    BOOL rows = charon_swipe_class_is_backport([UITableViewRowAction class]);
    BOOL configurations = charon_swipe_class_is_backport([UISwipeActionsConfiguration class]);
    if (!rows && !configurations)
        return;
    SEL selector = @selector(setDelegate:);
    void (*original)(id, SEL, id) = (void (*)(id, SEL, id))class_getMethodImplementation([UITableView class], selector);
    class_replaceMethod([UITableView class], selector, imp_implementationWithBlock(^(UITableView *table, id delegate) {
        original(table, selector, delegate);
        [table charon_installSwipeActions];
    }), method_getTypeEncoding(class_getInstanceMethod([UITableView class], selector)));
}

@end
