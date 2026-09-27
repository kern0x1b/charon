// The two exported constants iOS 9.3 added, with the values HealthKit gave them.
//
// Read out of the armv7 shared cache of iOS 9.3, not assumed: the HealthKit image was extracted with
// modules/apple/dyld.lua's extract() and each constant followed through its entry in the image's own
// symbol table to the __cfstring it points at. This is the exercise-time type the ring's exercise
// ring is counted in, and it is the one constant the release of 9.3 added. The reader is
// tools/cfconst/cache32.py, in the repository.
//
// HKPredicateKeyPathDateComponents - the path the two activity-summary predicates are built over -
// is NOT here and the reason is worth a line: the SDK header this library is compiled against dates it
// 9.3, and the armv7 shared cache of iOS 8.2 exports it while the one of 8.0 does not, so it arrived in
// 8.2 and is in HKConstants82.m. Where the header and a release's own image disagree, the release is
// the one that is right (COORDINATION section 5).

#import <HealthKit/HealthKit.h>

HKQuantityTypeIdentifier const HKQuantityTypeIdentifierAppleExerciseTime = @"HKQuantityTypeIdentifierAppleExerciseTime";
