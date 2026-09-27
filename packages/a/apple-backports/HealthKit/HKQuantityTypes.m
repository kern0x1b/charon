// What each quantity type is counted in, and how its values are aggregated.
//
// The table is Apple's own, written in the SDK: every HKQuantityTypeIdentifier line of
// HKTypeIdentifiers.h carries a trailing comment naming the unit and the aggregation, as
// `// kg, Discrete (Arithmetic)` and `// kcal, Cumulative`. This file is that comment read for every
// identifier of the header of iPhoneOS26.2.sdk, the SDK the corpus of this series is measured
// against, and nothing is in it that the header does not say.
// The unit strings are the ones +[HKUnit unitFromString:] answers, so a quantity type is compatible
// with exactly the units of its own dimension. The aggregations are the cases of
// HKQuantityAggregationStyle, the first three by the names the header gives, and the two it adds
// later recorded as themselves.
//
// A type whose documented unit is one +[HKUnit unitFromString:] cannot make - the header gives
// appleEffortScore for HKQuantityTypeIdentifierEstimatedWorkoutEffortScore and the empty string for
// HKQuantityTypeIdentifierAppleSleepingWristTemperature - keeps the string it was given and refuses
// a unit rather than guessing one, once, in the log.

#import <Foundation/Foundation.h>

#import "CharonHKTypes.h"
#import <HealthKit/HealthKit.h>

Class CharonHKClassForTypeKind(NSInteger kind)
{
    switch (kind) {
    case CharonHKTypeKindQuantity:
        return NSClassFromString(@"HKQuantityType");
    case CharonHKTypeKindCategory:
        return NSClassFromString(@"HKCategoryType");
    case CharonHKTypeKindCorrelation:
        return NSClassFromString(@"HKCorrelationType");
    case CharonHKTypeKindCharacteristic:
        return NSClassFromString(@"HKCharacteristicType");
    case CharonHKTypeKindWorkout:
        return NSClassFromString(@"HKWorkoutType");
    default:
        return Nil;
    }
}

Class CharonHKClassForObjectKind(NSInteger kind)
{
    switch (kind) {
    case 0:
        return NSClassFromString(@"HKCategorySample");
    case 1:
        return NSClassFromString(@"HKQuantitySample");
    case 2:
        return NSClassFromString(@"HKCorrelation");
    case 3:
        return NSClassFromString(@"HKWorkout");
    default:
        return Nil;
    }
}

static const CharonHKTypeEntry charon_hk_quantity_types[] = {
    {@"HKQuantityTypeIdentifierActiveEnergyBurned", @"kcal", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierAppleExerciseTime", @"min", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierAppleMoveTime", @"min", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances", @"count", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierAppleSleepingWristTemperature", @"degC", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierAppleStandTime", @"min", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierAppleWalkingSteadiness", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierAtrialFibrillationBurden", @"%", CharonHKAggregationDiscreteTemporallyWeighted},
    {@"HKQuantityTypeIdentifierBasalBodyTemperature", @"degC", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBasalEnergyBurned", @"kcal", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierBloodAlcoholContent", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBloodGlucose", @"mg/dL", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBloodPressureDiastolic", @"mmHg", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBloodPressureSystolic", @"mmHg", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBodyFatPercentage", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBodyMass", @"kg", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBodyMassIndex", @"count", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierBodyTemperature", @"degC", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierCrossCountrySkiingSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierCyclingCadence", @"count/min", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierCyclingFunctionalThresholdPower", @"W", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierCyclingPower", @"W", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierCyclingSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierDietaryBiotin", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryCaffeine", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryCalcium", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryCarbohydrates", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryChloride", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryCholesterol", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryChromium", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryCopper", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryEnergyConsumed", @"kcal", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryFatMonounsaturated", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryFatPolyunsaturated", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryFatSaturated", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryFatTotal", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryFiber", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryFolate", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryIodine", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryIron", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryMagnesium", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryManganese", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryMolybdenum", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryNiacin", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryPantothenicAcid", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryPhosphorus", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryPotassium", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryProtein", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryRiboflavin", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietarySelenium", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietarySodium", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietarySugar", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryThiamin", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminA", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminB12", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminB6", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminC", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminD", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminE", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryVitaminK", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryWater", @"mL", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDietaryZinc", @"g", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceCrossCountrySkiing", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceCycling", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceDownhillSnowSports", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistancePaddleSports", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceRowing", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceSkatingSports", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceSwimming", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceWalkingRunning", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierDistanceWheelchair", @"m", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierElectrodermalActivity", @"S", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierEnvironmentalAudioExposure", @"dBASPL", CharonHKAggregationDiscreteEquivalentContinuousLevel},
    {@"HKQuantityTypeIdentifierEnvironmentalSoundReduction", @"dBASPL", CharonHKAggregationDiscreteEquivalentContinuousLevel},
    {@"HKQuantityTypeIdentifierEstimatedWorkoutEffortScore", @"appleEffortScore", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierFlightsClimbed", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierForcedExpiratoryVolume1", @"L", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierForcedVitalCapacity", @"L", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierHeadphoneAudioExposure", @"dBASPL", CharonHKAggregationDiscreteEquivalentContinuousLevel},
    {@"HKQuantityTypeIdentifierHeartRate", @"count/s", CharonHKAggregationDiscreteTemporallyWeighted},
    {@"HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", @"count/min", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierHeartRateVariabilitySDNN", @"ms", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierHeight", @"m", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierInhalerUsage", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierInsulinDelivery", @"IU", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierLeanBodyMass", @"kg", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierNikeFuel", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierNumberOfAlcoholicBeverages", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierNumberOfTimesFallen", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierOxygenSaturation", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierPaddleSportsSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierPeakExpiratoryFlowRate", @"L/min", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierPeripheralPerfusionIndex", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierPhysicalEffort", @"kcal/(kg*hr)", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierPushCount", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierRespiratoryRate", @"count/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRestingHeartRate", @"count/min", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRowingSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRunningGroundContactTime", @"ms", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRunningPower", @"W", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRunningSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRunningStrideLength", @"m", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierRunningVerticalOscillation", @"cm", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierSixMinuteWalkTestDistance", @"m", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierStairAscentSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierStairDescentSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierStepCount", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierSwimmingStrokeCount", @"count", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierTimeInDaylight", @"min", CharonHKAggregationCumulativeSum},
    {@"HKQuantityTypeIdentifierUVExposure", @"", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierUnderwaterDepth", @"m", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierVO2Max", @"ml/(kg*min)", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWaistCircumference", @"m", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWalkingAsymmetryPercentage", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", @"%", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWalkingHeartRateAverage", @"count/min", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWalkingSpeed", @"m/s", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWalkingStepLength", @"m", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWaterTemperature", @"degC", CharonHKAggregationDiscreteArithmetic},
    {@"HKQuantityTypeIdentifierWorkoutEffortScore", @"appleEffortScore", CharonHKAggregationDiscreteArithmetic},
};
static const NSUInteger charon_hk_quantity_type_count = sizeof(charon_hk_quantity_types) / sizeof(charon_hk_quantity_types[0]);

const CharonHKTypeEntry *CharonHKQuantityTypeEntry(NSString *identifier)
{
    if (![identifier isKindOfClass:[NSString class]])
        return NULL;
    for (NSUInteger index = 0; index < charon_hk_quantity_type_count; index++)
        if ([charon_hk_quantity_types[index].identifier isEqualToString:identifier])
            return &charon_hk_quantity_types[index];
    return NULL;
}

BOOL CharonHKHasTypeIdentifier(NSString *identifier, CharonHKTypeKind kind)
{
    if (![identifier isKindOfClass:[NSString class]] || !identifier.length)
        return NO;
    switch (kind) {
    case CharonHKTypeKindQuantity:
        return CharonHKQuantityTypeEntry(identifier) != NULL;
    case CharonHKTypeKindCategory:
        return [identifier hasPrefix:@"HKCategoryTypeIdentifier"];
    case CharonHKTypeKindCharacteristic:
        return [identifier hasPrefix:@"HKCharacteristicTypeIdentifier"];
    case CharonHKTypeKindCorrelation:
        return [identifier hasPrefix:@"HKCorrelationTypeIdentifier"];
    case CharonHKTypeKindWorkout:
    default:
        return [identifier hasPrefix:@"HKWorkoutTypeIdentifier"];
    }
}
