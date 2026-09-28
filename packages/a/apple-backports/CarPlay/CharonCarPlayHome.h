// The car home screen: the release's own app icons on a grid sized from the head unit, and a dock
// at the side. This is the first thing the car screen shows, and every pixel of it is the RELEASE's
// own -- its app icons read at run time the way SpringBoard reads them, its linen and its gradients
// and its gloss, its Helvetica -- with nothing of Apple's copied into this repository.
//
// The entry point `carplayd` should render is CharonCarPlayHomeTemplate, and it is one line:
//
//     CPTemplate *home = [[CharonCarPlayHomeTemplate alloc] initWithScreenSize:screen];
//     [interfaceController setRootTemplate:home animated:NO completion:nil];
//     [interfaceController.contentWindow makeKeyAndVisible];   // or renderInContext: off-screen
//
// and the pixels are then `interfaceController.contentWindow.rootViewController.view.layer`, which
// is what the design's §4 render step takes into the bitmap context.
//
// The layout is CharonCarPlayLayout's, which is a pure function of the screen and is checked on the
// host for the three head-unit resolutions; this file is only the drawing and the input.
#import <CarPlay/CarPlay.h>
#import <UIKit/UIKit.h>
#import "CharonCarPlayLayout.h"

NS_ASSUME_NONNULL_BEGIN

// One app on the home screen: the name to show, the icon to show it with, and the bundle
// identifier to launch it by. The icon is the APP'S OWN, read from its bundle at run time -- there
// is no image in this repository and there never will be.
@interface CharonCarPlayApp : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, strong, nullable) UIImage *icon;
@property (nonatomic, readonly) CGSize iconSize;
@property (nonatomic, readonly) BOOL prerendered;   // the release already drew the gloss
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                                displayName:(NSString *)displayName
                                     bundle:(NSBundle *)bundle;
// The icon the release's own artwork gives: +[UIImage imageNamed:] on the launch images the release
// ships, and the app's own CFBundleIcons/CFBundleIconFiles out of its Info.plist, which is the way
// SpringBoard reads them. Returns nil for an app that ships no icon, and the grid then draws the
// app's name in its place rather than inventing a picture for it.
+ (nullable UIImage *)iconOfBundle:(NSBundle *)bundle prerendered:(BOOL *)prerendered;
@end

// The list of apps on the screen, and the exclusions and the order the settings pane sets.
@interface CharonCarPlayAppList : NSObject
@property (nonatomic, readonly, copy) NSArray<CharonCarPlayApp *> *apps;
@property (nonatomic, copy) NSArray<NSString *> *excludedBundleIdentifiers;
- (instancetype)initWithSearchPath:(nullable NSString *)searchPath;
- (void)moveBundleIdentifier:(NSString *)bundleIdentifier toIndex:(NSUInteger)index;
- (void)excludeBundleIdentifier:(NSString *)bundleIdentifier;
- (void)includeBundleIdentifier:(NSString *)bundleIdentifier;
- (BOOL)excludesBundleIdentifier:(NSString *)bundleIdentifier;
@end

// The home screen itself: a CPTemplate, so the interface controller pushes and pops it like any
// other, and its view controller draws the screen.
@interface CharonCarPlayHomeTemplate : CPTemplate
- (instancetype)initWithScreenSize:(CGSize)screenSize;
@property (nonatomic, readonly) CGSize screenSize;
@property (nonatomic, readonly, strong) CharonCarPlayAppList *apps;
// The recents: the port's own list of what was last launched FROM THIS SCREEN. Apple's recents come
// from the scene, and the scene is the wall (facts/CarPlay/CarPlay.md), so this list is the port's
// own and is said to be.
- (void)noteLaunchedBundleIdentifier:(NSString *)bundleIdentifier;
- (NSArray<CharonCarPlayApp *> *)recents;
@end

// The view controller that draws it, and the two halves of the drawing, so the settings pane can put
// the same chrome on its own rows.
@interface CharonCarPlayHomeViewController : UIViewController
- (instancetype)initWithTemplate:(CharonCarPlayHomeTemplate *)template;
@end

@interface CharonCarPlayHomeView : UIView
- (instancetype)initWithLayout:(CharonCarPlayLayout)layout page:(NSUInteger)page;
@property (nonatomic, readonly) CharonCarPlayLayout layout;
@property (nonatomic, copy) NSArray<CharonCarPlayApp *> *apps;
@property (nonatomic, copy) NSArray<CharonCarPlayApp *> *recents;
@property (nonatomic, copy) void (^charon_launch)(CharonCarPlayApp *app);
// The dock's three actions. Siri on this release has no assistant class at all (measured), so
// `charon_siri` asks for Siri to be opened on the phone and the dock dims its button where nothing
// can act on that; the recents and the settings pane are the port's own.
@property (nonatomic, copy) void (^charon_openRecents)(void);
@property (nonatomic, copy) void (^charon_siri)(void);
@property (nonatomic, copy) void (^charon_openSettings)(void);
@end

// The iOS 6 chrome, drawn in code, because the release's own is what a car screen shows: the
// gloss over a plate, the gradient a button or a cell is filled with, and the shadow under one.
// Every member is prefixed, so none of it is API the package carries.
@interface CharonCarPlaySkin : NSObject
+ (void)fillRect:(CGRect)rect context:(CGContextRef)context;
+ (void)glossInRect:(CGRect)rect context:(CGContextRef)context;
+ (void)drawPlateInRect:(CGRect)rect context:(CGContextRef)context radius:(CGFloat)radius;
+ (void)drawShadowForPath:(CGPathRef)path inRect:(CGRect)rect context:(CGContextRef)context;
+ (UIFont *)fontOfSize:(CGFloat)size bold:(BOOL)bold;
+ (UIColor *)labelColour;
+ (UIColor *)shadowColour;
// The release's own wallpaper, read on the device at run time, and the linen it ships. Returns nil
// where the release has none, and the caller then paints the gradient itself rather than showing a
// hole.
+ (nullable UIImage *)releaseWallpaper;
+ (nullable UIImage *)releaseLinen;
@end

NS_ASSUME_NONNULL_END
