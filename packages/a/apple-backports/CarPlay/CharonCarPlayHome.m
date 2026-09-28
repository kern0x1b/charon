// The car home screen, drawn in the release's own iOS 6 appearance. See CharonCarPlayHome.h for the
// entry point `carplayd` renders, and facts/CarPlay/CarPlay.md for what the owner's decision rules
// in and out.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "CharonCarPlayHome.h"

// ============================ the app's own icon, read at run time ============================

// The icon an app ships, read out of its own bundle the way SpringBoard reads one: the
// CFBundleIcons of the iOS 5+ form, the CFBundleIconFiles of the older one, the UIPrerenderedIcon
// flag that says the release has already drawn the gloss, and the file inside the bundle. Nothing is
// guessed and nothing is invented: an app that ships no icon gets no icon, and the grid says so in
// the app's own name.
@implementation CharonCarPlayApp {
    NSString *_bundleIdentifier;
    NSString *_displayName;
    UIImage *_icon;
    CGSize _iconSize;
    BOOL _prerendered;
}

@synthesize bundleIdentifier = _bundleIdentifier;
@synthesize displayName = _displayName;
@synthesize icon = _icon;
@synthesize iconSize = _iconSize;
@synthesize prerendered = _prerendered;

+ (UIImage *)iconOfBundle:(NSBundle *)bundle prerendered:(BOOL *)prerendered
{
    if (prerendered) {
        *prerendered = NO;
    }
    NSDictionary *info = [bundle infoDictionary];
    if (![info isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSMutableArray *names = [NSMutableArray array];
    NSDictionary *icons = [info objectForKey:@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        NSDictionary *primary = [icons objectForKey:@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]]) {
            [names addObjectsFromArray:[primary objectForKey:@"CFBundleIconFiles"] ?: @[]];
        }
        [names addObjectsFromArray:[icons objectForKey:@"CFBundleIconFiles"] ?: @[]];
    }
    [names addObjectsFromArray:[info objectForKey:@"CFBundleIconFiles"] ?: @[]];
    // A named icon wins over the positional list, and the positional one is tried in its own order.
    NSString *named = [info objectForKey:@"CFBundleIconFile"];
    if ([named isKindOfClass:[NSString class]]) {
        [names insertObject:named atIndex:0];
    }
    for (NSString *name in names) {
        if (![name isKindOfClass:[NSString class]]) {
            continue;
        }
        // The @2x form first on a retina device, which is the file the release would have shown.
        NSString *stem = [name stringByDeletingPathExtension];
        NSString *extension = [name pathExtension];
        NSArray *tried = extension.length > 0
            ? @[[stem stringByAppendingFormat:@"@2x.%@", extension],
               [stem stringByAppendingPathExtension:extension]]
            : @[name];
        for (NSString *file in tried) {
            NSString *path = [bundle pathForResource:stem ofType:extension];
            if (path) {
                path = [[path stringByDeletingLastPathComponent]
                        stringByAppendingPathComponent:file];
            }
            UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
            if (image) {
                if (prerendered) {
                    // The release's own flag on the image: a pre-rendered icon already carries the
                    // gloss and must not be given a second one.
                    *prerendered = [image respondsToSelector:@selector(UIPrerenderedIcon)] &&
                                   [image valueForKey:@"UIPrerenderedIcon"] ? YES : NO;
                }
                return image;
            }
        }
    }
    return nil;
}


- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                                displayName:(NSString *)displayName
                                     bundle:(NSBundle *)bundle
{
    self = [super init];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy] ?: bundleIdentifier;
        BOOL prerendered = NO;
        _icon = [CharonCarPlayApp iconOfBundle:bundle prerendered:&prerendered];
        _prerendered = prerendered;
        _iconSize = _icon ? _icon.size : CGSizeZero;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CharonCarPlayApp: %p %@ (%@)%@>", self, _displayName,
            _bundleIdentifier, _icon ? @"" : @" no icon"];
}

@end

// ============================ the apps on the screen ============================

// Where the release keeps its apps, and where a jailbroken root daemon may read them. The home
// screen does not need the apps to be running: it reads their bundles, which is what SpringBoard
// does to draw this same grid, and the release's own CFBundle APIs read them.
static NSArray *CharonCarPlayApplicationRoots(void)
{
    return @[@"/Applications", @"/var/containers/Bundle/Application"];
}

@implementation CharonCarPlayAppList {
    NSMutableArray<CharonCarPlayApp *> *_apps;
    NSMutableSet<NSString *> *_excluded;
    NSString *_searchPath;
}

@synthesize apps = _apps;
@synthesize excludedBundleIdentifiers = _excludedBundleIdentifiers;

- (instancetype)initWithSearchPath:(NSString *)searchPath
{
    self = [super init];
    if (self) {
        _searchPath = [searchPath copy];
        _apps = [[NSMutableArray alloc] init];
        _excluded = [[NSMutableSet alloc] init];
        [self charon_rescan];
    }
    return self;
}

// The scan: every bundle under the roots, read through NSBundle so the reading is the release's own.
// The system's own applications are left out -- a car screen is the user's apps, and SpringBoard's
// own grid does not show Settings or Preferences as icons either.
- (void)charon_rescan
{
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    NSArray *roots = _searchPath.length > 0 ? @[_searchPath] : CharonCarPlayApplicationRoots();
    for (NSString *root in roots) {
        NSFileManager *files = [NSFileManager defaultManager];
        NSArray *entries = [files contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *entry in entries) {
            NSString *path = [root stringByAppendingPathComponent:entry];
            BOOL directory = NO;
            [files fileExistsAtPath:path isDirectory:&directory];
            NSString *bundlePath = directory ? path : [path stringByAppendingPathExtension:@"app"];
            if (!directory && ![bundlePath hasSuffix:@".app"]) {
                continue;
            }
            NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
            NSString *identifier = [bundle bundleIdentifier];
            if (identifier.length == 0 || found[identifier] != nil) {
                continue;
            }
            if ([identifier hasPrefix:@"com.apple."] && ![identifier isEqualToString:@"com.apple.mobilesafari"]) {
                continue;
            }
            found[identifier] = [[CharonCarPlayApp alloc] initWithBundleIdentifier:identifier
                                                                          displayName:[bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                                                           ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"]
                                                                               bundle:bundle];
        }
    }
    // Sorted by the name the user sees, which is what a grid of icons is read in, and stable so a
    // page does not reshuffle between draws.
    NSArray *sorted = [[found allValues] sortedArrayUsingComparator:^NSComparisonResult(id left_, id right_) {
        CharonCarPlayApp *left = left_;
        CharonCarPlayApp *right = right_;
        NSComparisonResult order = [left.displayName localizedCaseInsensitiveCompare:right.displayName];
        if (order != NSOrderedSame) {
            return order;
        }
        return [left.bundleIdentifier compare:right.bundleIdentifier];
    }];
    _apps = [sorted mutableCopy];
}

- (NSArray<CharonCarPlayApp *> *)charon_visibleApps
{
    NSMutableArray *visible = [NSMutableArray array];
    for (CharonCarPlayApp *app in _apps) {
        if (![self excludesBundleIdentifier:app.bundleIdentifier]) {
            [visible addObject:app];
        }
    }
    return visible;
}

- (void)setExcludedBundleIdentifiers:(NSArray<NSString *> *)identifiers
{
    _excludedBundleIdentifiers = [identifiers copy];
    [_excluded removeAllObjects];
    for (NSString *identifier in _excludedBundleIdentifiers) {
        [_excluded addObject:identifier];
    }
}

- (void)excludeBundleIdentifier:(NSString *)bundleIdentifier
{
    [_excluded addObject:bundleIdentifier];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *identifier in _excludedBundleIdentifiers) {
        if (identifier.length > 0) {
            [kept addObject:identifier];
        }
    }
    [kept addObject:bundleIdentifier];
    _excludedBundleIdentifiers = kept;
}

- (void)includeBundleIdentifier:(NSString *)bundleIdentifier
{
    [_excluded removeObject:bundleIdentifier];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *identifier in _excludedBundleIdentifiers) {
        if (![identifier isEqualToString:bundleIdentifier]) {
            [kept addObject:identifier];
        }
    }
    _excludedBundleIdentifiers = kept;
}

- (BOOL)excludesBundleIdentifier:(NSString *)bundleIdentifier
{
    return [_excluded containsObject:bundleIdentifier];
}

// The order the user set, and the app the grid should ask for at an index.
- (void)moveBundleIdentifier:(NSString *)bundleIdentifier toIndex:(NSUInteger)index
{
    NSMutableArray *visible = [[self charon_visibleApps] mutableCopy];
    NSUInteger from = NSNotFound;
    for (NSUInteger at = 0; at < visible.count; at++) {
        CharonCarPlayApp *candidate = [visible objectAtIndex:at];
        if ([candidate.bundleIdentifier isEqualToString:bundleIdentifier]) {
            from = at;
            break;
        }
    }
    if (from == NSNotFound) {
        return;
    }
    CharonCarPlayApp *moved = [visible objectAtIndex:from];
    [visible removeObjectAtIndex:from];
    if (index > visible.count) {
        index = visible.count;
    }
    [visible insertObject:moved atIndex:index];
    [self charon_setVisibleOrder:visible];
}

- (void)charon_setVisibleOrder:(NSArray<CharonCarPlayApp *> *)ordered
{
    NSMutableArray *everything = [NSMutableArray arrayWithArray:ordered];
    for (id app_ in _apps) {
        CharonCarPlayApp *app = app_;
        if (![everything containsObject:app]) {
            [everything addObject:app];
        }
    }
    _apps = everything;
}

@end

// ============================ the iOS 6 chrome, drawn in code ============================

@implementation CharonCarPlaySkin

// The gradient a plate is filled with: the release's own, a light top to a dark bottom, which is what
// an iOS 6 bar, button and cell are filled with.
+ (void)fillRect:(CGRect)rect context:(CGContextRef)context
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) {
        return;
    }
    CGFloat locations[2] = {0.0, 1.0};
    CGFloat components[8] = {0.98, 0.98, 0.99, 1.0, 0.72, 0.73, 0.78, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, locations, 2);
    if (gradient) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, rect);
        CGContextDrawLinearGradient(context, gradient, CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect)),
                                   CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect)), 0);
        CGContextRestoreGState(context);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(space);
}

// The gloss: the bright half-round over the top of a plate, which is the whole of what makes an iOS 6
// control look like one.
+ (void)glossInRect:(CGRect)rect context:(CGContextRef)context
{
    CGRect top = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect),
                            CGRectGetHeight(rect) * 0.48);
    UIBezierPath *gloss = [UIBezierPath bezierPathWithRoundedRect:top cornerRadius:0.0];
    CGContextSaveGState(context);
    CGContextAddPath(context, gloss.CGPath);
    CGContextClip(context);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 0.55);
    CGContextFillRect(context, top);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 0.0);
    CGContextFillRect(context, CGRectMake(CGRectGetMinX(top), CGRectGetMinY(top), CGRectGetWidth(top), 1.0));
    CGContextRestoreGState(context);
}

// A plate: the gradient, the gloss over it, the hairline and the shadow under it.
+ (void)drawPlateInRect:(CGRect)rect context:(CGContextRef)context radius:(CGFloat)radius
{
    UIBezierPath *plate = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, -1.0), 2.0, [self shadowColour].CGColor);
    [[UIColor colorWithWhite:1.0 alpha:0.98] setFill];
    [plate fill];
    CGContextSetShadowWithColor(context, CGSizeZero, 0.0, NULL);
    CGContextAddPath(context, plate.CGPath);
    CGContextClip(context);
    [self fillRect:rect context:context];
    [self glossInRect:rect context:context];
    CGContextRestoreGState(context);
    CGContextSaveGState(context);
    [[UIColor colorWithWhite:0.0 alpha:0.35] setStroke];
    plate.lineWidth = 1.0;
    [plate stroke];
    CGContextRestoreGState(context);
}

+ (void)drawShadowForPath:(CGPathRef)path inRect:(CGRect)rect context:(CGContextRef)context
{
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, -2.0), 4.0, [self shadowColour].CGColor);
    [[UIColor colorWithWhite:0.0 alpha:0.0] setFill];
    CGContextAddPath(context, path);
    CGContextFillPath(context);
    CGContextRestoreGState(context);
    (void)rect;
}

+ (UIFont *)fontOfSize:(CGFloat)size bold:(BOOL)bold
{
    // Helvetica, which is the release's own family and the one its labels are set in.
    return bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

+ (UIColor *)labelColour
{
    return [UIColor colorWithWhite:0.05 alpha:1.0];
}

+ (UIColor *)shadowColour
{
    return [UIColor colorWithWhite:0.0 alpha:0.55];
}

// The release's own wallpaper and linen, read on the device at run time. Nothing is copied into this
// repository: these are two names the release ships, asked for by name, and where the release has
// neither the caller paints the gradient itself rather than showing a hole.
+ (UIImage *)releaseWallpaper
{
    return [UIImage imageNamed:@"Wallpaper"] ?: [UIImage imageNamed:@"Default"];
}

+ (UIImage *)releaseLinen
{
    return [UIImage imageNamed:@"Linen"];
}

@end
