// The two exported constants iOS 9.3 added, with the values HealthKit gave them.
//
// Read out of the armv7 shared cache of iOS 9.3, not assumed: the HealthKit image was extracted with
// modules/apple/dyld.lua's extract() and each constant followed through its entry in the image's own
// symbol table to the __cfstring it points at. HKPredicateKeyPathDateComponents is the path the two
// activity-summary predicates of HKQuery are built over, and it is the property HKActivitySummary
// answers; the type identifier is the exercise-time type the ring's exercise ring is counted in. The
// reader is .agent-work/runs/api-kits/cfconst32.py.

#import <HealthKit/HealthKit.h>

NSString *const HKPredicateKeyPathDateComponents = @"dateComponents";
HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAppleExerciseTime = @"HKQuantityTypeIdentifierAppleExerciseTime";
