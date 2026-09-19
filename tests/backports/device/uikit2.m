#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#import "check.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const double pause_seconds = 1;
static const double step_timeout_seconds = 30;
static const double run_timeout_seconds = 300;
static NSString *const results_folder = @"/private/var/backports";

#define NAMED(...) ([NSString stringWithFormat:__VA_ARGS__].UTF8String)

typedef void (^Step)(void (^done)(void));

static NSInteger running_step;

static void guarded(dispatch_block_t block)
{
    @try {
        block();
    } @catch (NSException *exception) {
        charon_check(NO, NAMED(@"step %ld raises no exception", (long)running_step),
                     [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]);
    }
}

static void after(double seconds, dispatch_block_t block)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        guarded(block);
    });
}

static void write_summary(NSString *reason)
{
    NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d%@\n", charon_failures ? @"FAIL" : @"ok",
                         charon_checks, charon_failures, reason.length ? [@" " stringByAppendingString:reason] : @""];
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"uikit2.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void uncaught(NSException *exception)
{
    charon_failures++;
    printf("FAIL uncaught %s: %s\n%s\n", exception.name.UTF8String, exception.reason.UTF8String,
           [exception.callStackReturnAddresses description].UTF8String);
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    fflush(stdout);
    write_summary([@"uncaught " stringByAppendingString:exception.name]);
}

static NSString *image_of(Class class, SEL selector)
{
    Dl_info info;
    IMP implementation = class_getMethodImplementation(class, selector);
    return implementation && dladdr((const void *)implementation, &info) ? [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent] : @"<unknown>";
}

static NSString *traits_of(id environment)
{
    UITraitCollection *traits = [environment traitCollection];
    return [NSString stringWithFormat:@"idiom %ld scale %g horizontal %ld vertical %ld", (long)traits.userInterfaceIdiom,
            (double)traits.displayScale, (long)traits.horizontalSizeClass, (long)traits.verticalSizeClass];
}

@interface RecordingView : UIView
@property (nonatomic, strong) UITraitCollection *previousTraits;
@property (nonatomic) NSInteger traitChanges;
@property (nonatomic) NSInteger tintChanges;
@end

@implementation RecordingView

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    self.previousTraits = previousTraitCollection;
    self.traitChanges++;
}

- (void)tintColorDidChange
{
    self.tintChanges++;
}

@end

@interface RecordingController : UIViewController
@property (nonatomic, strong) UITraitCollection *previousTraits;
@property (nonatomic) NSInteger traitChanges;
@end

@implementation RecordingController

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    self.previousTraits = previousTraitCollection;
    self.traitChanges++;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

@end

@interface UIKitTestDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) RecordingController *host;
@property (nonatomic, strong) RecordingView *content;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIUserNotificationSettings *registeredSettings;
@property (nonatomic) NSInteger registrations;
@property (nonatomic) BOOL finished;
@end

@implementation UIKitTestDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[results_folder stringByAppendingPathComponent:@"uikit2.done"] error:NULL];
    charon_log_to([results_folder stringByAppendingPathComponent:@"uikit2.log"]);
    NSSetUncaughtExceptionHandler(uncaught);
    printf("uikit2 device test started on iOS %s\n", [UIDevice currentDevice].systemVersion.UTF8String);
    self.host = [[RecordingController alloc] init];
    self.host.view.backgroundColor = [UIColor whiteColor];
    self.content = [[RecordingView alloc] initWithFrame:CGRectMake(20, 60, 200, 100)];
    self.content.backgroundColor = [UIColor lightGrayColor];
    [self.host.view addSubview:self.content];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(10, 200, 300, 200)];
    self.status.numberOfLines = 0;
    self.status.text = @"Running";
    [self.host.view addSubview:self.status];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = self.host;
    [self.window makeKeyAndVisible];
    NSArray *steps = [self steps];
    after(1, ^{
        [self run:steps index:0];
    });
    after(run_timeout_seconds, ^{
        if (!self.finished)
            charon_check(NO, "the whole test finishes in time", @"the run timed out");
        [self finish];
    });
    return YES;
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    self.registrations++;
    self.registeredSettings = notificationSettings;
}

- (void)run:(NSArray *)steps index:(NSUInteger)index
{
    if (index == steps.count) {
        [self finish];
        return;
    }
    printf("step %lu\n", (unsigned long)index + 1);
    running_step = index + 1;
    self.status.text = [NSString stringWithFormat:@"Step %lu of %lu", (unsigned long)index + 1, (unsigned long)steps.count];
    __block BOOL stepFinished = NO;
    void (^done)(void) = ^{
        if (stepFinished)
            return;
        stepFinished = YES;
        after(pause_seconds, ^{
            [self run:steps index:index + 1];
        });
    };
    after(step_timeout_seconds, ^{
        if (!stepFinished) {
            charon_check(NO, "step finishes in time", [NSString stringWithFormat:@"step %lu timed out", (unsigned long)index + 1]);
            done();
        }
    });
    Step step = [steps objectAtIndex:index];
    guarded(^{
        step(done);
    });
}

- (void)finish
{
    if (self.finished)
        return;
    self.finished = YES;
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    fflush(stdout);
    self.status.text = [NSString stringWithFormat:@"%@\nchecks=%d failures=%d", charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
    write_summary(nil);
}

- (NSArray *)steps
{
    UIKitTestDelegate *test = self;
    return @[
        [^(void (^done)(void)) {
            UIScreen *screen = [UIScreen mainScreen];
            UIUserInterfaceIdiom idiom = [UIDevice currentDevice].userInterfaceIdiom;
            BOOL landscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
            NSString *expected = [NSString stringWithFormat:@"idiom %ld scale %g horizontal %ld vertical %ld", (long)idiom, (double)screen.scale,
                                  (long)(idiom == UIUserInterfaceIdiomPad ? UIUserInterfaceSizeClassRegular : UIUserInterfaceSizeClassCompact),
                                  (long)(idiom == UIUserInterfaceIdiomPad || !landscape ? UIUserInterfaceSizeClassRegular : UIUserInterfaceSizeClassCompact)];
            charon_check([traits_of(screen) isEqualToString:expected], "the screen traits follow the iOS 8 rules", [NSString stringWithFormat:@"%@ != %@", traits_of(screen), expected]);
            charon_check([traits_of(test.window) isEqualToString:traits_of(screen)], "a window takes the traits of its screen", traits_of(test.window));
            charon_check([traits_of(test.host) isEqualToString:traits_of(screen)], "a view controller in a window takes its traits", traits_of(test.host));
            charon_check([traits_of(test.content) isEqualToString:traits_of(screen)], "a view takes the traits of its controller", traits_of(test.content));
            charon_check([traits_of([[UIView alloc] init]) isEqualToString:traits_of(screen)], "a view outside any window falls back to the main screen", traits_of([[UIView alloc] init]));
            charon_check([test.content conformsToProtocol:@protocol(UITraitEnvironment)], "a view is a trait environment", @"the protocol is missing");
            charon_check([test.host conformsToProtocol:@protocol(UITraitEnvironment)], "a view controller is a trait environment", @"the protocol is missing");
            charon_check([screen conformsToProtocol:@protocol(UITraitEnvironment)], "a screen is a trait environment", @"the protocol is missing");
            charon_check([test.content.traitCollection containsTraitsInCollection:[UITraitCollection traitCollectionWithDisplayScale:screen.scale]],
                         "the view traits contain the display scale", traits_of(test.content));
            CGRect bounds = screen.bounds;
            charon_check(CGRectEqualToRect(screen.nativeBounds, CGRectMake(0, 0, bounds.size.width * screen.scale, bounds.size.height * screen.scale)),
                         "nativeBounds is the screen in pixels", NSStringFromCGRect(screen.nativeBounds));
            charon_check(screen.nativeScale == screen.scale, "nativeScale", [NSString stringWithFormat:@"%g", (double)screen.nativeScale]);
            done();
        } copy],
        [^(void (^done)(void)) {
            UIApplication *application = [UIApplication sharedApplication];
            UIInterfaceOrientation start = application.statusBarOrientation;
            test.content.traitChanges = 0;
            test.host.traitChanges = 0;
            __block BOOL announced = NO;
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
                announced = YES;
            }];
            printf("info the application supports the orientations %lu, the controller %lu, and it autorotates %d\n",
                   (unsigned long)[application supportedInterfaceOrientationsForWindow:test.window],
                   (unsigned long)[test.host supportedInterfaceOrientations], [test.host shouldAutorotate]);
            [application setStatusBarOrientation:UIInterfaceOrientationLandscapeLeft animated:NO];
            after(0.5, ^{
                charon_check(announced, "iOS 6 announces a status bar orientation change", @"no notification arrived");
                charon_check(application.statusBarOrientation == UIInterfaceOrientationLandscapeLeft, "the status bar turned", @"the orientation did not change");
                BOOL pad = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
                UIUserInterfaceSizeClass landscapeVertical = pad ? UIUserInterfaceSizeClassRegular : UIUserInterfaceSizeClassCompact;
                NSInteger expectedChanges = pad ? 0 : 1;
                charon_check(test.content.traitCollection.verticalSizeClass == landscapeVertical,
                             pad ? "an iPad keeps the vertical size class regular in landscape" : "landscape makes the vertical size class compact", traits_of(test.content));
                charon_check(test.content.traitChanges == expectedChanges, "the view hears about a change of its traits only when they change",
                             [NSString stringWithFormat:@"%ld changes", (long)test.content.traitChanges]);
                charon_check(test.host.traitChanges == expectedChanges, "the view controller hears about a change of its traits only when they change",
                             [NSString stringWithFormat:@"%ld changes", (long)test.host.traitChanges]);
                charon_check(pad ? test.content.previousTraits == nil : test.content.previousTraits.verticalSizeClass == UIUserInterfaceSizeClassRegular,
                             "the previous traits are the ones before the turn", [NSString stringWithFormat:@"%@", test.content.previousTraits]);
                [application setStatusBarOrientation:start animated:NO];
                after(0.5, ^{
                    charon_check(test.content.traitChanges == expectedChanges * 2, "turning back is announced as well", [NSString stringWithFormat:@"%ld changes", (long)test.content.traitChanges]);
                    charon_check(test.content.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular, "portrait makes the vertical size class regular again", traits_of(test.content));
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    done();
                });
            });
        } copy],
        [^(void (^done)(void)) {
            RecordingController *child = [[RecordingController alloc] init];
            [test.host addChildViewController:child];
            [test.host.view addSubview:child.view];
            [child didMoveToParentViewController:test.host];
            charon_check([traits_of(child) isEqualToString:traits_of(test.host)], "a child controller inherits the traits of its parent", traits_of(child));
            child.traitChanges = 0;
            UIUserInterfaceSizeClass inherited = test.host.traitCollection.horizontalSizeClass;
            UIUserInterfaceSizeClass overridden = inherited == UIUserInterfaceSizeClassRegular ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular;
            [test.host setOverrideTraitCollection:[UITraitCollection traitCollectionWithHorizontalSizeClass:overridden] forChildViewController:child];
            charon_check(child.traitCollection.horizontalSizeClass == overridden, "an override reaches the child", traits_of(child));
            charon_check(child.traitChanges == 1, "the child hears about the override", [NSString stringWithFormat:@"%ld changes", (long)child.traitChanges]);
            charon_check([[test.host overrideTraitCollectionForChildViewController:child] horizontalSizeClass] == overridden, "the override is kept", @"the override is gone");
            charon_check(test.content.traitCollection.horizontalSizeClass == inherited, "the override leaves the other views alone", traits_of(test.content));
            [test.host setOverrideTraitCollection:nil forChildViewController:child];
            charon_check(child.traitCollection.horizontalSizeClass == inherited, "clearing the override", traits_of(child));
            [child.view removeFromSuperview];
            [child removeFromParentViewController];
            done();
        } copy],
        [^(void (^done)(void)) {
            UIApplication *application = [UIApplication sharedApplication];
            UIMutableUserNotificationAction *action = [[UIMutableUserNotificationAction alloc] init];
            action.identifier = @"reply";
            action.title = @"Reply";
            action.activationMode = UIUserNotificationActivationModeBackground;
            UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
            category.identifier = @"message";
            [category setActions:@[action] forContext:UIUserNotificationActionContextDefault];
            UIUserNotificationType types = UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
            UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:[NSSet setWithObject:category]];
            test.registrations = 0;
            [application registerUserNotificationSettings:settings];
            after(1, ^{
                charon_check(test.registrations == 1, "the delegate hears about the registration once", [NSString stringWithFormat:@"%ld calls", (long)test.registrations]);
                UIUserNotificationSettings *granted = application.currentUserNotificationSettings;
                charon_check(granted != nil, "the application reports its notification settings", @"no settings");
                charon_check([test.registeredSettings isEqual:granted], "the delegate is handed the settings the application reports", [NSString stringWithFormat:@"%@", test.registeredSettings]);
                charon_check(granted.types == types || granted.types == (UIUserNotificationType)[application enabledRemoteNotificationTypes],
                             "iOS 6 grants the local notification types it was asked for", [NSString stringWithFormat:@"%lu, enabled %lu", (unsigned long)granted.types, (unsigned long)[application enabledRemoteNotificationTypes]]);
                charon_check(granted.categories.count == 0, "iOS 6 shows no notification actions, so no category is granted", [NSString stringWithFormat:@"%@", granted.categories]);
                UILocalNotification *notification = [[UILocalNotification alloc] init];
                notification.alertBody = @"Backported settings";
                notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:3600];
                [application scheduleLocalNotification:notification];
                charon_check(application.scheduledLocalNotifications.count > 0, "a local notification can be scheduled after registering", @"nothing was scheduled");
                [application cancelLocalNotification:notification];
                done();
            });
        } copy],
        [^(void (^done)(void)) {
            UIInterpolatingMotionEffect *horizontal = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
            horizontal.minimumRelativeValue = @(-20);
            horizontal.maximumRelativeValue = @20;
            UIInterpolatingMotionEffect *vertical = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
            vertical.minimumRelativeValue = @(-20);
            vertical.maximumRelativeValue = @20;
            UIMotionEffectGroup *group = [[UIMotionEffectGroup alloc] init];
            group.motionEffects = @[horizontal, vertical];
            [test.content addMotionEffect:group];
            charon_check(test.content.motionEffects.count == 1, "the view holds the motion effect group", @"the group is missing");
            CMMotionManager *manager = [[CMMotionManager alloc] init];
            BOOL gyroscope = manager.deviceMotionAvailable;
            __block NSInteger motions = 0;
            printf("info device motion available: %d\n", gyroscope);
            if (gyroscope) {
                manager.deviceMotionUpdateInterval = 1.0 / 30;
                [manager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *motion, NSError *error) {
                    if (motion)
                        motions++;
                }];
            }
            after(2, ^{
                CAAnimation *animation = [test.content.layer animationForKey:@"charon.motionEffect.position.x"];
                [manager stopDeviceMotionUpdates];
                if (gyroscope && motions == 0)
                    printf("skip a device with a gyroscope applies the effect to the layer: CoreMotion reports a gyroscope but delivers no device motion in this environment, so the effect has nothing to follow\n");
                else if (gyroscope)
                    charon_check(animation != nil, "a device with a gyroscope applies the effect to the layer",
                                 [NSString stringWithFormat:@"no animation was applied for %ld device motions", (long)motions]);
                else
                    charon_check(animation == nil, "a device without a gyroscope applies no effect, as on iOS 7", @"an animation was applied");
                [test.content removeMotionEffect:group];
                charon_check(test.content.motionEffects.count == 0, "the effect can be removed", @"the effect is still there");
                after(1, ^{
                    done();
                });
            });
        } copy],
        [^(void (^done)(void)) {
            UIView *box = [[UIView alloc] initWithFrame:CGRectMake(20, 380, 40, 40)];
            box.backgroundColor = [UIColor blueColor];
            [test.host.view addSubview:box];
            CGPoint start = box.center;
            CGPoint target = CGPointMake(start.x + 200, start.y);
            __block NSInteger completions = 0;
            __block BOOL finishedFlag = NO;
            __block CGFloat furthest = start.x;
            [UIView animateWithDuration:0.8 delay:0 usingSpringWithDamping:0.35 initialSpringVelocity:0 options:0 animations:^{
                box.center = target;
            } completion:^(BOOL finished) {
                completions++;
                finishedFlag = finished;
            }];
            CAAnimation *animation = [box.layer animationForKey:@"position"];
            BOOL keyframed = [animation isKindOfClass:[CAKeyframeAnimation class]];
            NSUInteger frames = keyframed ? ((CAKeyframeAnimation *)animation).values.count : 0;
            charon_check(keyframed, "the spring is animated with key frames", NSStringFromClass([animation class]));
            charon_check(frames > 10, "the key frames follow the spring curve", [NSString stringWithFormat:@"%lu values", (unsigned long)frames]);
            for (int sample = 1; sample <= 16; sample++) {
                after(sample * 0.05, ^{
                    CGFloat position = [(CALayer *)box.layer.presentationLayer position].x;
                    furthest = MAX(furthest, position);
                });
            }
            after(1.2, ^{
                charon_check(completions == 1, "the completion runs once", [NSString stringWithFormat:@"%ld completions", (long)completions]);
                charon_check(finishedFlag, "the completion reports a finished animation", @"the animation was reported unfinished");
                charon_check(fabs(box.center.x - target.x) < 0.5, "the view ends where it was sent", [NSString stringWithFormat:@"%g", (double)box.center.x]);
                charon_check(furthest > target.x + 1, "a lightly damped spring overshoots its target", [NSString stringWithFormat:@"furthest %g, target %g", (double)furthest, (double)target.x]);
                charon_check([box.layer animationForKey:@"position"] == nil, "the animation is gone when it ends", @"an animation is still attached");
                __block NSInteger interrupted = 0;
                __block BOOL interruptedFlag = YES;
                [UIView animateWithDuration:0.8 delay:0 usingSpringWithDamping:0.35 initialSpringVelocity:0 options:0 animations:^{
                    box.center = start;
                } completion:^(BOOL finished) {
                    interrupted++;
                    interruptedFlag = finished;
                }];
                after(0.2, ^{
                    [UIView animateWithDuration:0.2 animations:^{
                        box.center = CGPointMake(start.x + 60, start.y);
                    }];
                    after(0.8, ^{
                        charon_check(interrupted == 1, "an interrupted spring completes once", [NSString stringWithFormat:@"%ld completions", (long)interrupted]);
                        charon_check(!interruptedFlag, "an interrupted spring reports an unfinished animation", @"the animation was reported finished");
                        CGPoint away = CGPointMake(start.x + 120, start.y);
                        box.center = start;
                        __block NSInteger delayed = 0;
                        [UIView animateWithDuration:0.5 delay:0.4 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
                            box.center = away;
                        } completion:^(BOOL finished) {
                            delayed++;
                        }];
                        CAAnimation *waiting = [box.layer animationForKey:@"position"];
                        charon_check([waiting isKindOfClass:[CAKeyframeAnimation class]], "a delayed spring is animated with key frames as well", NSStringFromClass([waiting class]));
                        __block CGFloat duringTheDelay = away.x;
                        after(0.25, ^{
                            duringTheDelay = [(CALayer *)box.layer.presentationLayer position].x;
                        });
                        after(1.4, ^{
                            charon_check(fabs(duringTheDelay - start.x) < 12, "the spring waits for its delay", [NSString stringWithFormat:@"%g instead of %g", (double)duringTheDelay, (double)start.x]);
                            charon_check(delayed == 1, "the delayed spring completes once", [NSString stringWithFormat:@"%ld completions", (long)delayed]);
                            charon_check(fabs(box.center.x - away.x) < 0.5, "the delayed spring ends where it was sent", [NSString stringWithFormat:@"%g", (double)box.center.x]);
                            [box removeFromSuperview];
                            done();
                        });
                    });
                });
            });
        } copy],
        [^(void (^done)(void)) {
            UIApplication *application = [UIApplication sharedApplication];
            __block NSInteger handlers = 0;
            __block BOOL unknownOpened = YES;
            [application openURL:[NSURL URLWithString:@"charon-backports-nothing://test"] options:@{} completionHandler:^(BOOL success) {
                handlers++;
                unknownOpened = success;
            }];
            __block BOOL universalOpened = YES;
            [application openURL:[NSURL URLWithString:@"https://example.invalid/page"] options:@{UIApplicationOpenURLOptionUniversalLinksOnly: @YES} completionHandler:^(BOOL success) {
                handlers++;
                universalOpened = success;
            }];
            after(1, ^{
                charon_check(handlers == 2, "every openURL handler runs", [NSString stringWithFormat:@"%ld handlers", (long)handlers]);
                charon_check(!unknownOpened, "a scheme no application claims is reported as not opened", @"the URL was opened");
                charon_check(!universalOpened, "iOS 6 has no universal links, so a universal link only open fails", @"the URL was opened");
                done();
            });
        } copy],
        [^(void (^done)(void)) {
            UIImage *image = nil;
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(10, 10), NO, 0);
            [[UIColor redColor] setFill];
            UIRectFill(CGRectMake(0, 0, 10, 10));
            image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            charon_check(image.renderingMode == UIImageRenderingModeAutomatic, "a fresh image renders automatically", [NSString stringWithFormat:@"%ld", (long)image.renderingMode]);
            UIImage *template = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            charon_check(template.renderingMode == UIImageRenderingModeAlwaysTemplate, "the rendering mode is kept", [NSString stringWithFormat:@"%ld", (long)template.renderingMode]);
            charon_check(image.renderingMode == UIImageRenderingModeAutomatic, "the original image is left alone", @"the original changed");
            charon_check(CGSizeEqualToSize(template.size, image.size) && template.scale == image.scale, "the image itself is kept", NSStringFromCGSize(template.size));

            UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 100, 30)];
            field.font = [UIFont systemFontOfSize:14];
            field.textColor = [UIColor redColor];
            field.textAlignment = NSTextAlignmentCenter;
            NSDictionary *attributes = field.defaultTextAttributes;
            charon_check([[attributes objectForKey:NSFontAttributeName] isEqual:field.font], "defaultTextAttributes carries the font", [NSString stringWithFormat:@"%@", attributes]);
            charon_check([[attributes objectForKey:NSForegroundColorAttributeName] isEqual:field.textColor], "defaultTextAttributes carries the colour", [NSString stringWithFormat:@"%@", attributes]);
            charon_check([[attributes objectForKey:NSParagraphStyleAttributeName] alignment] == NSTextAlignmentCenter, "defaultTextAttributes carries the alignment", [NSString stringWithFormat:@"%@", attributes]);
            field.defaultTextAttributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:20], NSForegroundColorAttributeName: [UIColor greenColor]};
            charon_check(field.font.pointSize == 20 && [field.textColor isEqual:[UIColor greenColor]], "setting defaultTextAttributes changes the field", [NSString stringWithFormat:@"%@ %@", field.font, field.textColor]);

            charon_check(test.host.edgesForExtendedLayout == UIRectEdgeAll, "edgesForExtendedLayout starts as all edges", [NSString stringWithFormat:@"%lu", (unsigned long)test.host.edgesForExtendedLayout]);
            charon_check(!test.host.extendedLayoutIncludesOpaqueBars, "extendedLayoutIncludesOpaqueBars starts as NO", @"the default is YES");
            charon_check(test.host.automaticallyAdjustsScrollViewInsets, "automaticallyAdjustsScrollViewInsets starts as YES", @"the default is NO");
            test.host.edgesForExtendedLayout = UIRectEdgeNone;
            charon_check(test.host.edgesForExtendedLayout == UIRectEdgeNone, "edgesForExtendedLayout is kept", @"the value is not kept");
            charon_check(CGRectGetMinY(test.host.view.frame) >= 0, "iOS 6 lays out below the bars either way", NSStringFromCGRect(test.host.view.frame));
            done();
        } copy],
        [^(void (^done)(void)) {
            UINavigationBar *bar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
            UIColor *colour = [UIColor colorWithRed:0.1 green:0.4 blue:0.8 alpha:1];
            bar.barTintColor = colour;
            charon_check([bar.barTintColor isEqual:colour], "the navigation bar keeps its bar tint colour", [NSString stringWithFormat:@"%@", bar.barTintColor]);
            charon_check([bar.tintColor isEqual:colour], "on iOS 6 the bar tint colour is the tint colour of the bar", [NSString stringWithFormat:@"%@", bar.tintColor]);
            UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
            search.searchBarStyle = UISearchBarStyleMinimal;
            charon_check(search.searchBarStyle == UISearchBarStyleMinimal, "the search bar style is kept", @"the style is not kept");
            charon_check(search.backgroundImage != nil, "the minimal style takes the iOS 6 bar background away", @"the background is still drawn");

            RecordingView *parent = [[RecordingView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
            RecordingView *child = [[RecordingView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
            [parent addSubview:child];
            [test.host.view addSubview:parent];
            charon_check(child.tintColor != nil, "a view always has a tint colour", @"the tint colour is nil");
            parent.tintChanges = child.tintChanges = 0;
            parent.tintColor = [UIColor purpleColor];
            charon_check([child.tintColor isEqual:[UIColor purpleColor]], "the tint colour is inherited", [NSString stringWithFormat:@"%@", child.tintColor]);
            charon_check(child.tintChanges == 1 && parent.tintChanges == 1, "tintColorDidChange reaches the views below",
                         [NSString stringWithFormat:@"%ld %ld", (long)parent.tintChanges, (long)child.tintChanges]);
            parent.tintAdjustmentMode = UIViewTintAdjustmentModeDimmed;
            charon_check(child.tintAdjustmentMode == UIViewTintAdjustmentModeDimmed, "the adjustment mode is inherited", @"the mode is not inherited");
            CGFloat red = 0, green = 0, blue = 0, alpha = 0;
            [child.tintColor getRed:&red green:&green blue:&blue alpha:&alpha];
            charon_check(red == green && green == blue, "a dimmed tint colour is grey", [NSString stringWithFormat:@"%g %g %g", (double)red, (double)green, (double)blue]);
            [parent removeFromSuperview];

            UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            charon_check(body.pointSize == 17, "the body text style is 17 points", [NSString stringWithFormat:@"%g", (double)body.pointSize]);
            charon_check([body.familyName isEqualToString:[UIFont systemFontOfSize:17].familyName], "the body text style uses the iOS 6 system font", body.familyName);
            UIFont *headline = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
            charon_check([headline.fontName isEqualToString:[UIFont boldSystemFontOfSize:17].fontName], "the headline text style uses the bold system font", headline.fontName);
            charon_check([[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2] pointSize] == 11, "the caption 2 text style is 11 points", @"the size differs");
            UIFont *light = [UIFont systemFontOfSize:15 weight:UIFontWeightLight];
            UIFont *bold = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            UIFont *regular = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
            printf("info weights: light %s, regular %s, bold %s\n", light.fontName.UTF8String, regular.fontName.UTF8String, bold.fontName.UTF8String);
            charon_check([bold.fontName isEqualToString:[UIFont boldSystemFontOfSize:15].fontName], "a semibold weight maps to the iOS 6 bold system font", bold.fontName);
            charon_check([regular.fontName isEqualToString:[UIFont systemFontOfSize:15].fontName], "a medium weight maps to the iOS 6 system font", regular.fontName);
            charon_check([light.familyName isEqualToString:[UIFont systemFontOfSize:15].familyName], "a light weight stays in the system font family", light.familyName);
            charon_check(light.pointSize == 15 && bold.pointSize == 15, "the weighted fonts keep their size", @"the size differs");

            CGFloat blueRed = 0, blueGreen = 0, blueBlue = 0, blueAlpha = 0;
            [[UIColor systemBlueColor] getRed:&blueRed green:&blueGreen blue:&blueBlue alpha:&blueAlpha];
            charon_check(fabs(blueRed) < 0.01 && fabs(blueGreen - 122 / 255.0) < 0.01 && fabs(blueBlue - 1) < 0.01, "systemBlueColor is the iOS 7 blue",
                         [NSString stringWithFormat:@"%g %g %g", (double)blueRed, (double)blueGreen, (double)blueBlue]);
            done();
        } copy],
        [^(void (^done)(void)) {
            struct { const char *name; int red, green, blue; } systems[] = {
                {"systemRedColor", 255, 59, 48}, {"systemGreenColor", 76, 217, 100}, {"systemBlueColor", 0, 122, 255},
                {"systemOrangeColor", 255, 149, 0}, {"systemYellowColor", 255, 204, 0}, {"systemPinkColor", 255, 45, 85},
                {"systemTealColor", 90, 200, 250}, {"systemGrayColor", 142, 142, 147}, {"systemPurpleColor", 88, 86, 214},
            };
            for (size_t index = 0; index < sizeof systems / sizeof *systems; index++) {
                SEL selector = sel_registerName(systems[index].name);
                UIColor *colour = [UIColor respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)([UIColor class], selector) : nil;
                CGFloat red = -1, green = -1, blue = -1, alpha = -1;
                [colour getRed:&red green:&green blue:&blue alpha:&alpha];
                charon_check(fabs(red * 255 - systems[index].red) < 0.5 && fabs(green * 255 - systems[index].green) < 0.5 && fabs(blue * 255 - systems[index].blue) < 0.5 && alpha == 1,
                             NAMED(@"%s is %d %d %d", systems[index].name, systems[index].red, systems[index].green, systems[index].blue),
                             [NSString stringWithFormat:@"%g %g %g %g", (double)(red * 255), (double)(green * 255), (double)(blue * 255), (double)alpha]);
            }

            struct { const char *name; CGFloat red, green, blue, alpha, grey, dimmedAlpha; } dims[] = {
                {"red", 1, 0, 0, 1, 77 / 255.0, 0.8}, {"green", 0, 1, 0, 1, 150 / 255.0, 0.8}, {"blue", 0, 0, 1, 1, 28 / 255.0, 0.8}, {"half red", 1, 0, 0, 0.5, 77 / 255.0, 0.4},
            };
            for (size_t index = 0; index < sizeof dims / sizeof *dims; index++) {
                UIView *parent = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
                UIView *child = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 5)];
                [parent addSubview:child];
                parent.tintColor = [UIColor colorWithRed:dims[index].red green:dims[index].green blue:dims[index].blue alpha:dims[index].alpha];
                parent.tintAdjustmentMode = UIViewTintAdjustmentModeDimmed;
                CGFloat white = -1, alpha = -1;
                BOOL grey = [child.tintColor getWhite:&white alpha:&alpha];
                charon_check(grey && fabs(white - dims[index].grey) <= 1.5 / 255 && fabs(alpha - dims[index].dimmedAlpha) < 0.001,
                             NAMED(@"dimmed %s is the grey iOS 6 CoreGraphics matches it to, %g, at alpha %g", dims[index].name, (double)(dims[index].grey * 255), (double)dims[index].dimmedAlpha),
                             [NSString stringWithFormat:@"%d %g %g", grey, (double)white, (double)alpha]);
            }

            NSArray *speech = @[@"UIAccessibilitySpeechAttributePunctuation", @"UIAccessibilitySpeechAttributeLanguage", @"UIAccessibilitySpeechAttributePitch"];
            for (NSString *name in speech) {
                void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
                Dl_info info;
                NSString *image = symbol && dladdr(symbol, &info) ? [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent] : @"<none>";
                NSString *value = symbol ? *(__unsafe_unretained NSString **)symbol : nil;
                charon_check([value isEqualToString:name], NAMED(@"%@ is its own name", name), value ?: @"<nil>");
                printf("info %s comes from %s\n", name.UTF8String, image.UTF8String);
            }

            Class traits = [UITraitCollection class];
            SEL withStyle = sel_registerName("traitCollectionWithUserInterfaceStyle:");
            SEL style = sel_registerName("userInterfaceStyle");
            charon_check([traits respondsToSelector:withStyle] && [traits instancesRespondToSelector:style], "a trait collection has a user interface style", @"the methods are missing");
            if ([traits respondsToSelector:withStyle]) {
                UITraitCollection *dark = ((id (*)(id, SEL, NSInteger))objc_msgSend)(traits, withStyle, 2);
                UITraitCollection *light = ((id (*)(id, SEL, NSInteger))objc_msgSend)(traits, withStyle, 1);
                NSInteger (*read)(id, SEL) = (NSInteger (*)(id, SEL))objc_msgSend;
                CHECK_EQUAL(@(read(dark, style)), @2, "a collection made with the dark style answers dark");
                CHECK_EQUAL(@(read([UITraitCollection traitCollectionWithDisplayScale:2], style)), @0, "a collection without a style answers unspecified");
                UITraitCollection *merged = [UITraitCollection traitCollectionWithTraitsFromCollections:@[[UITraitCollection traitCollectionWithDisplayScale:2], dark]];
                charon_check(read(merged, style) == 2 && merged.displayScale == 2, "merging keeps the style and the other traits", merged.description);
                charon_check(![dark isEqual:light] && [dark isEqual:((id (*)(id, SEL, NSInteger))objc_msgSend)(traits, withStyle, 2)], "the style takes part in equality", dark.description);
                charon_check([merged containsTraitsInCollection:dark] && ![merged containsTraitsInCollection:light], "the style takes part in containment", merged.description);
                UITraitCollection *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:merged]];
                charon_check([decoded isEqual:merged] && read(decoded, style) == 2, "the style survives archiving", decoded.description);
                CHECK_EQUAL(@(read(test.host.view.window.traitCollection, style)), @1, "the window answers the light style");
            }
            done();
        } copy],
        [^(void (^done)(void)) {
            CLLocationManager *manager = [[CLLocationManager alloc] init];
            charon_check([manager respondsToSelector:@selector(requestWhenInUseAuthorization)], "requestWhenInUseAuthorization is installed on CLLocationManager", @"the method is missing");
            charon_check([manager respondsToSelector:@selector(requestAlwaysAuthorization)], "requestAlwaysAuthorization is installed on CLLocationManager", @"the method is missing");
            CHECK_EQUAL(image_of([CLLocationManager class], @selector(requestWhenInUseAuthorization)), @"libCoreLocationBackports.dylib",
                        "requestWhenInUseAuthorization comes from the CoreLocation backports");
            CHECK_EQUAL(image_of([CLLocationManager class], @selector(requestAlwaysAuthorization)), @"libCoreLocationBackports.dylib",
                        "requestAlwaysAuthorization comes from the CoreLocation backports");
            CHECK_EQUAL(image_of([UIView class], @selector(traitCollection)), @"libUIKitBackports.dylib", "the view traits come from the UIKit backports");
            printf("info location services enabled %d, authorization status %d\n", [CLLocationManager locationServicesEnabled], [CLLocationManager authorizationStatus]);
            [manager requestWhenInUseAuthorization];
            after(2, ^{
                charon_check(YES, "requesting authorization does not raise", @"");
                printf("info authorization status after the request: %d\n", [CLLocationManager authorizationStatus]);
                done();
            });
        } copy],
    ];
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([UIKitTestDelegate class]));
    }
}
