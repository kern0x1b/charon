// The dock at the side of the car home screen: the time, the cellular status, the battery, Siri, and
// the recents.
//
// What each of the five is, measured against the armv7 dyld shared cache of 6.1.3 with
// apple.objc.inventory, because three of them are not what the name suggests on this release:
//
//   TIME      NSDate, with a timer to the next minute. Nothing release-specific and nothing to
//             measure: the release's own calendar does it.
//   CELLULAR  CTTelephonyNetworkInfo's -radioAccessTechnology and -subscriberCellularProvider (a
//             CTCarrier with -carrierName, -isoCountryCode, -mobileCountryCode, -mobileNetworkCode).
//             **There is no -signalStrength on this release** -- that is iOS 7 -- so the dock shows the
//             ACCESS TECHNOLOGY and the carrier's own name, and NOT a bar count it cannot measure.
//   BATTERY    UIDevice's own: -batteryMonitoringEnabled, -setBatteryMonitoringEnabled:, -batteryLevel
//             and -batteryState. All four measured present.
//   SIRI      **The thing that brings Siri up is not in the shared cache at all**: measured with
//             apple.objc.inventory over the whole 6.1.3 armv7 cache, AssistantServices.framework
//             holds 22 classes and every one of them is AF* or DK* -- the speech and DICTATION
//             transport, with no AssistantController and no AssistantSession in the image -- and
//             AssistantUI's 24 classes are AFUI* plus the lock screen's SBAssistantAwayBottomView
//             and SBDeviceLockKeypadSiri. SpringBoard, where the controller is, is a bundled
//             application and not a cache image, so no cache inventory can see it.
//
//             So the button ASKS rather than claims. -siriAvailability asks the release, through
//             the release's own AFPreferences, whether the assistant is there; where something
//             answers, the plate is live and the action asks the daemon to bring Siri up over the
//             SpringBoard path; where nothing answers, the plate is drawn dimmed and says Siri is
//             not available on this device, which is a measurement and not a guess at the hardware.
//             The full measurement is in facts/CarPlay/CarPlay.md.
//   RECENTS    the port's own list of what this screen launched, and nothing else; Apple's recents
//             come from the scene, and the scene is the wall.
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import "CharonCarPlayHome.h"
#import "CharonCarPlayLayout.h"

NS_ASSUME_NONNULL_BEGIN

// The status the dock shows, each part measured from the release's own source and nothing invented.
@interface CharonCarPlayDockStatus : NSObject
@property (nonatomic, readonly, copy) NSString *timeText;
@property (nonatomic, readonly, copy) NSString *carrierText;   // nil where the release has no carrier
@property (nonatomic, readonly, copy) NSString *radioText;    // the access technology, or nil
@property (nonatomic, readonly) CGFloat batteryLevel;        // -1 where the release will not say
@property (nonatomic, readonly) BOOL batteryCharging;
@property (nonatomic, readonly) BOOL cellularAvailable;
- (void)start;
- (void)stop;
@end

@interface CharonCarPlayDock : UIView
- (instancetype)initWithLayout:(CharonCarPlayLayout)layout;
@property (nonatomic, readonly) CharonCarPlayDockStatus *status;
@property (nonatomic, copy) NSArray<CharonCarPlayApp *> *recents;
@property (nonatomic, copy) void (^charon_openRecents)(void);
@property (nonatomic, copy) void (^charon_siri)(void);
@property (nonatomic, copy) void (^charon_openSettings)(void);
@end

NS_ASSUME_NONNULL_END
