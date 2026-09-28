// The settings pane: exclude an app from the car home screen, or put it back, and reorder what is
// left. It is a CPListTemplate, so it is drawn by the same release chrome as everything else, and it
// is pushed by the same interface controller.
//
// The exclusions and the order are the port's own state, kept where the design's §3 daemon can reach
// them: a small plist beside the home screen's own data, written by the release's own
// -[NSUserDefaults ...] through NSUserDefaults, which is what a jailbroken root daemon and a car
// screen can both read.
#import <CarPlay/CarPlay.h>
#import <UIKit/UIKit.h>
#import "CharonCarPlayHome.h"

NS_ASSUME_NONNULL_BEGIN

// Where the exclusions and the order live, and the two operations the rows do.
@interface CharonCarPlayHomeSettings : NSObject
+ (instancetype)shared;
// The key the exclusions and the order are kept under, in the release's own defaults domain.
+ (NSString *)defaultsKey;
- (instancetype)initWithApps:(CharonCarPlayAppList *)apps;
@property (nonatomic, readonly, strong) CharonCarPlayAppList *apps;
- (void)save;
@end

// The pane itself: a list template whose sections are the included apps and the excluded ones, and
// whose rows exclude, include and move.
@interface CharonCarPlayHomeSettingsTemplate : CPListTemplate
- (instancetype)initWithApps:(CharonCarPlayAppList *)apps;
@end

NS_ASSUME_NONNULL_END
