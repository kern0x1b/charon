// The exported constants iOS 8.2 added, with the values HealthKit gave them.
//
// Every value below was read out of a release's own image, not assumed: the image was extracted with
// modules/apple/dyld.lua's extract() and each constant followed through its entry in that image's
// symbol table to the __cfstring it points at. The reader is tools/cfconst/cache32.py.
//
// HKPredicateKeyPathDateComponents is here and not in the group of 9.3, and that is a measurement
// rather than a reading of the header: the SDK header this library is compiled against dates it 9.3, and
// the armv7 shared cache of iOS 8.2 exports _HKPredicateKeyPathDateComponents while the one of 8.0 does
// not. It is the key path the two activity-summary predicates of HKQuery are built over, and
// HKActivitySummary answers it. Where the header and a release's own image disagree, the release is the
// one that is right (COORDINATION section 5).
//
// Nine more names arrived in that release and are not here: HKDailyBriskMinutesGoal,
// HKDailyStandingHoursGoal, HKFirstDayOfWeekForWeeklyGoalCalculations, HKHealthAppSourceEntitlement,
// HKLogSafeBundleIdentifier, HKLogSafeDescription, HKOperatorTypeInArray, HKSourceOptionsForAppleDevice
// and HKStackshotWriteWithReason are exported by the 8.2 image and declared by no public header, so
// they are Apple's private and this port does not carry them.

#import <HealthKit/HealthKit.h>

NSString *const HKUserPreferencesDidChangeNotification = @"HKUserPreferencesDidChangeNotification";
NSString *const HKPredicateKeyPathDateComponents = @"dateComponents";
