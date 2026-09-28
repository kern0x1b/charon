// The home screen's pixels: the release's own background, a grid of the release's own app icons
// with the iOS 6 gloss and shadow drawn in code, and the page dots underneath. Nothing here is
// CarPlay 7's flat look, and no artwork is in this repository: the icons are the apps' own, read at
// run time, and the background is the release's own wallpaper or linen where it has one.
#import <UIKit/UIKit.h>
#import "CharonCarPlayHome.h"

@implementation CharonCarPlayHomeView {
    NSArray<CharonCarPlayApp *> *_apps;
    NSArray<CharonCarPlayApp *> *_recents;
    CharonCarPlayLayout _layout;
    NSUInteger _page;
}

@synthesize layout = _layout;
@synthesize apps = _apps;
@synthesize recents = _recents;
@synthesize charon_launch = _charon_launch;

- (instancetype)initWithLayout:(CharonCarPlayLayout)layout page:(NSUInteger)page
{
    self = [super initWithFrame:CGRectMake(0.0, 0.0, layout.screen.width, layout.screen.height)];
    if (self) {
        _layout = layout;
        _page = page;
        _apps = @[];
        _recents = @[];
        // The release's own background: its linen where it ships one, its wallpaper otherwise, and a
        // gradient of its own colours where it ships neither -- never a hole, never a copied image.
        UIImage *background = [CharonCarPlaySkin releaseLinen] ?: [CharonCarPlaySkin releaseWallpaper];
        if (background) {
            self.backgroundColor = [UIColor colorWithPatternImage:background];
        } else {
            self.backgroundColor = [UIColor blackColor];
        }
        self.opaque = YES;
    }
    return self;
}

- (void)setApps:(NSArray<CharonCarPlayApp *> *)apps
{
    _apps = [apps copy] ?: @[];
    [self setNeedsDisplay];
}

- (void)setRecents:(NSArray<CharonCarPlayApp *> *)recents
{
    _recents = [recents copy] ?: @[];
    [self setNeedsDisplay];
}

- (NSUInteger)charon_pageCount
{
    NSUInteger perPage = _layout.iconsPerPage;
    if (perPage == 0) {
        return 1;
    }
    return (NSUInteger)ceil((double)_apps.count / (double)perPage);
}

// Which app is at a cell, on this page: the page's slice of the list, in order.
- (CharonCarPlayApp *)charon_appAtColumn:(NSUInteger)column row:(NSUInteger)row
{
    NSUInteger perPage = _layout.iconsPerPage;
    NSUInteger index = _page * perPage + row * _layout.columns + column;
    return index < _apps.count ? _apps[index] : nil;
}

// One icon: the app's own picture, the gloss over it unless the release already drew one, the shadow
// under it, and the app's own name. An app that ships no icon gets its name in the plate instead of
// a picture invented for it.
- (void)charon_drawApp:(CharonCarPlayApp *)app inFrame:(CharonCarPlayIconFrame)frame
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }
    UIBezierPath *plate = [UIBezierPath bezierPathWithRoundedRect:frame.icon cornerRadius:_layout.cornerRadius];
    if (app.icon) {
        [CharonCarPlaySkin drawShadowForPath:plate.CGPath inRect:frame.icon context:context];
        [[UIColor colorWithWhite:1.0 alpha:0.95] setFill];
        [plate fill];
        CGContextSaveGState(context);
        CGContextAddPath(context, plate.CGPath);
        CGContextClip(context);
        CGFloat inset = _layout.iconSide * 0.09;
        CGRect box = CGRectMake(CGRectGetMinX(frame.icon) + inset, CGRectGetMinY(frame.icon) + inset,
                                CGRectGetWidth(frame.icon) - 2.0 * inset, CGRectGetHeight(frame.icon) - 2.0 * inset);
        [app.icon drawInRect:box];
        if (!app.prerendered) {
            // The iOS 6 gloss, drawn here because the release has not drawn this one.
            [CharonCarPlaySkin glossInRect:CGRectInset(frame.icon, 1.0, 1.0) context:context];
        }
        CGContextRestoreGState(context);
    } else {
        [CharonCarPlaySkin drawPlateInRect:frame.icon context:context radius:_layout.cornerRadius];
    }
    // The app's own name, in the release's own font, under its own icon.
    NSDictionary *attributes = @{NSFontAttributeName: [CharonCarPlaySkin fontOfSize:_layout.labelHeight * 0.62
                                                                     bold:NO],
                                 NSForegroundColorAttributeName: [UIColor whiteColor]};
    CGSize text = [app.displayName sizeWithAttributes:attributes];
    // The label's own shadow is drawn here, because NSShadowColorAttributeName is iOS 7 and the
    // release does not have it -- the same reason the gloss is drawn rather than asked for.
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, -1.0), 2.0,
                                [UIColor colorWithWhite:0.0 alpha:0.75].CGColor);
    [app.displayName drawAtPoint:CGPointMake(CGRectGetMidX(frame.label) - text.width / 2.0,
                                             CGRectGetMidY(frame.label) - text.height / 2.0)
                withAttributes:attributes];
    CGContextRestoreGState(context);
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }
    for (NSUInteger row = 0; row < _layout.rows; row++) {
        for (NSUInteger column = 0; column < _layout.columns; column++) {
            CharonCarPlayApp *app = [self charon_appAtColumn:column row:row];
            if (!app) {
                continue;
            }
            [self charon_drawApp:app inFrame:CharonCarPlayLayoutIconFrame(&_layout, column, row)];
        }
    }
    [self charon_drawPageDots];
}

// The page dots, in the release's own chrome, under the grid, and only when there is more than one
// page -- a car screen with eight apps does not need dots.
- (void)charon_drawPageDots
{
    NSUInteger pages = [self charon_pageCount];
    if (pages < 2) {
        return;
    }
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat dot = _layout.iconSide * 0.11;
    CGFloat spacing = dot * 1.8;
    CGFloat total = pages * dot + (pages - 1) * (spacing - dot);
    CGFloat at = CGRectGetMidX(self.bounds) - total / 2.0;
    CGFloat y = CGRectGetMaxY(_layout.grid) - dot;
    for (NSUInteger page = 0; page < pages; page++) {
        BOOL current = page == _page;
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, current ? 0.95 : 0.35);
        CGContextFillEllipseInRect(context, CGRectMake(at, y, dot, dot));
        at += spacing;
    }
}

// The hit test the daemon's input goes through: which icon is under a point, if any.
- (CharonCarPlayApp *)charon_appAtPoint:(CGPoint)point
{
    for (NSUInteger row = 0; row < _layout.rows; row++) {
        for (NSUInteger column = 0; column < _layout.columns; column++) {
            CharonCarPlayIconFrame frame = CharonCarPlayLayoutIconFrame(&_layout, column, row);
            if (CGRectContainsPoint(frame.icon, point)) {
                return [self charon_appAtColumn:column row:row];
            }
        }
    }
    return nil;
}

@end

@implementation CharonCarPlayHomeTemplate {
    CGSize _screenSize;
    CharonCarPlayAppList *_apps;
    NSMutableArray<NSString *> *_recents;
}

@synthesize screenSize = _screenSize;
@synthesize apps = _apps;

- (instancetype)initWithScreenSize:(CGSize)screenSize
{
    self = [super init];
    if (self) {
        _screenSize = screenSize;
        _apps = [[CharonCarPlayAppList alloc] initWithSearchPath:nil];
        _recents = [[NSMutableArray alloc] init];
        self.tabTitle = @"Home";
    }
    return self;
}

- (void)noteLaunchedBundleIdentifier:(NSString *)bundleIdentifier
{
    if (bundleIdentifier.length == 0) {
        return;
    }
    [_recents removeObject:bundleIdentifier];
    [_recents insertObject:bundleIdentifier atIndex:0];
    while (_recents.count > 8) {
        [_recents removeLastObject];
    }
}

// The recents are the PORT'S OWN list of what was last launched from this screen, and they are
// labelled as such: Apple's recents come from the scene's running templates, and the scene is the
// wall (facts/CarPlay/CarPlay.md). So this list is what this screen launched, which is a real list
// and not a claim to be Apple's.
- (NSArray<CharonCarPlayApp *> *)recents
{
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *identifier in _recents) {
        for (CharonCarPlayApp *app in _apps.apps) {
            if ([app.bundleIdentifier isEqualToString:identifier]) {
                [apps addObject:app];
                break;
            }
        }
    }
    return apps;
}

- (NSArray<CharonCarPlayApp *> *)charon_visibleApps
{
    NSMutableArray *visible = [NSMutableArray array];
    for (CharonCarPlayApp *app in _apps.apps) {
        if (![_apps excludesBundleIdentifier:app.bundleIdentifier]) {
            [visible addObject:app];
        }
    }
    return visible;
}

- (UIViewController *)charon_viewControllerForInterfaceController:(CPInterfaceController *)controller
{
    return [[CharonCarPlayHomeViewController alloc] initWithTemplate:self];
}

@end

@implementation CharonCarPlayHomeViewController {
    CharonCarPlayHomeTemplate *_home;
    CharonCarPlayHomeView *_view_;
    UIScrollView *_scroll;
}

- (instancetype)initWithTemplate:(CharonCarPlayHomeTemplate *)template_
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _home = template_;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    CharonCarPlayLayout layout = CharonCarPlayLayoutMake(_home.screenSize, 1.0);
    _view_ = [[CharonCarPlayHomeView alloc] initWithLayout:layout page:0];
    _view_.apps = [_home charon_visibleApps];
    _view_.recents = [_home recents];
    __weak CharonCarPlayHomeViewController *weak = self;
    _view_.charon_launch = ^(CharonCarPlayApp *app) {
        [weak charon_launchApp:app];
    };
    self.view = _view_;
    self.view.backgroundColor = [UIColor blackColor];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // The screen size the head unit reported is what the layout is built from, so a layout that
    // arrives after the view is up is rebuilt rather than stretched.
    CharonCarPlayLayout layout = CharonCarPlayLayoutMake(_home.screenSize, 1.0);
    _view_.frame = CGRectMake(0.0, 0.0, layout.screen.width, layout.screen.height);
}

// The launch: the app's own bundle identifier, which is what a car's head unit takes. The daemon
// decides what happens next -- the design's §3 puts the app's content on the far side of the Mach
// service -- so all this records is that the user chose an app.
- (void)charon_launchApp:(CharonCarPlayApp *)app
{
    [_home noteLaunchedBundleIdentifier:app.bundleIdentifier];
    _view_.recents = [_home recents];
}

@end
