# `ENExposureConfiguration`, iOS 12.5

`Foundation/ENExposureConfiguration.m`: the twenty-four weights and thresholds an application sets and
`ENManager` reads when it is asked to detect exposures.

Every one of them is readwrite in Apple's own header, so every one of them here stores and returns what
the caller gave it. There is no initialiser to write beyond `NSObject`'s: the header declares none.

## What an application gets before it sets anything, and why it is the zero value

Apple's own object starts from the configuration Apple recommends. **No SDK header states those numbers.**
SDK 26.2's `ENCommon.h` declares the twenty-four properties and gives no default for any of them, and no
other header on this machine does either.

Nor is there anything on this release that could supply them. The service that reads this configuration is
`ENManager`, and `Manager.md` is why this release cannot detect an exposure: no framework, no
entitlement, and no Bluetooth Low Energy subsystem to broadcast over.

So the twenty-four answers here before a caller sets one are the zero value of its own type -- `0`, `nil`,
or an empty collection -- which is what a caller who sets all twenty-four never sees, and what a caller
who reads one first must be told about. Which values Apple recommends is a measurement this machine
cannot take: it would need the framework's own `-init` on a release that has it, and no
`ExposureNotification.framework` exists in any SDK installed here. A number put here instead would be
invented, and an invented weight silently changes every risk score computed from it.

## The twenty-four, as the header declares them

| property | type |
| --- | --- |
| immediateDurationWeight, nearDurationWeight, mediumDurationWeight, otherDurationWeight | double |
| infectiousnessForDaysSinceOnsetOfSymptoms | NSDictionary of NSNumber to NSNumber |
| infectiousnessStandardWeight, infectiousnessHighWeight | double |
| reportTypeConfirmedTestWeight, reportTypeConfirmedClinicalDiagnosisWeight, reportTypeSelfReportedWeight, reportTypeRecursiveWeight | double |
| reportTypeNoneMap | ENDiagnosisReportType |
| attenuationDurationThresholds, attenuationLevelValues, daysSinceLastExposureLevelValues, durationLevelValues, transmissionRiskLevelValues | NSArray of NSNumber |
| daysSinceLastExposureThreshold | NSInteger |
| minimumRiskScoreFullRange, attenuationWeight, daysSinceLastExposureWeight, durationWeight, transmissionRiskWeight, minimumRiskScore | double (the last is ENRiskScore) |
| metadata | NSDictionary |
