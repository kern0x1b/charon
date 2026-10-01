// The CarPlay surface the port's build SDK does not declare, declared here.
//
// THE BUILD SDK IS 16.4, not 26.2. `charon@iphoneos-sdk` resolves to 16.4 -- build-gate.lua names it,
// every line of a gate says sdk=16.4, and CharonFoundationIdentifiers.h and CharonNEDNSSettings.h say so
// in their own first paragraphs -- and the two SDKs in ~/.xmake/packages/i/iphoneos-sdk/ are exactly
// 16.4 and 26.2 with nothing between. Measured 2026-10-01: the 16.4 CarPlay.framework/Headers holds
// CPLaneGuidance.h? no. CPLane.h? no. CPRouteInformation.h? no. and CPNavigationEnum.h's CPManeuverState?
// no. Every type below is API_AVAILABLE(ios(17.4)) and every one of them is absent from the SDK this
// package compiles against, so an object that names one does not compile -- which is what
// review-mechanical.sh's compile step reported for the five 17.4 CarPlay objects, and what a first
// draft of this header's own siblings (CharonFoundationIdentifiers.h, CharonNEDNSSettings.h) exist to
// prevent.
//
// The shapes and member names below are the 26.2 SDK's own headers' -- CPLane.h:10-55, CPLaneGuidance.h:
// 11-29, CPRouteInformation.h:11-58, CPNavigationSession.h:53-103 for the three properties -- copied as
// declarations only. No Apple's bytes are copied and no method body comes from here: the behaviour is in
// CarPlayLane174.m, CarPlayLaneGuidance174.m, CarPlayRouteInformation174.m and
// CarPlayNavigationSession174.m, and it is measured against Apple's own CarPlay on this machine
// (facts/CarPlay/NavigationSession174.md). The availability mark is not repeated per member for the
// reason CharonNEDNSSettings.h gives: the package installs one object for every band the port serves,
// which is what the absence of a version mark means here too.
//
// WHY IT IS GUARDED. The Mac Catalyst differential (tests/backports/host/carplay/run.sh) compiles these
// same sources against the iOSSupport SDK, which DOES declare every type below -- and an
// `@interface CPLane` here beside the SDK's own is a "duplicate interface definition for class 'CPLane'"
// error, measured 2026-10-01 compiling CarPlayLane174.m against 26.2. `__has_include` is what lets one
// source serve both: against 16.4 the include is false and this file's declarations are the ones in
// scope; against the iOSSupport SDK the include is true and the SDK's own declarations are. Nothing is
// declared twice and nothing is second-guessed.
#ifndef CHARON_CARPLAY_174_H
#define CHARON_CARPLAY_174_H

#import <Foundation/Foundation.h>
#import <CarPlay/CarPlay.h>

#if __has_include(<CarPlay/CPLane.h>)

// The SDK in scope declares the 17.4 CarPlay surface itself. Nothing to stand in for, and declaring any
// of it again here would be a duplicate interface.
#import <CarPlay/CPLane.h>
#import <CarPlay/CPLaneGuidance.h>
#import <CarPlay/CPRouteInformation.h>

#else

NS_ASSUME_NONNULL_BEGIN

// CPLane.h:10-15 -- an NS_ENUM over NSInteger, with CPLaneStatusNotGood = 0 first, which is why a lane
// made by -init is NotGood: the value 0 and no other is invented.
typedef NS_ENUM(NSInteger, CPLaneStatus) {
    CPLaneStatusNotGood = 0,
    CPLaneStatusGood,
    CPLaneStatusPreferred
};

// CPLane.h:22-55. -init is declared and deprecated in the same declaration; the 18.0 half of the class
// (-initWithAngles:, -initWithAngles:highlightedAngle:isPreferred:, highlightedAngle, angles) is declared
// too, because one .h is two releases and the port carries both.
@interface CPLane : NSObject <NSCopying, NSSecureCoding>
- (instancetype)init;
- (instancetype)initWithAngles:(NSArray<NSMeasurement<NSUnitAngle *> *> *)angles;
- (instancetype)initWithAngles:(NSArray<NSMeasurement<NSUnitAngle *> *> *)angles
             highlightedAngle:(NSMeasurement<NSUnitAngle *> *)highlightedAngle
                   isPreferred:(BOOL)preferred;
@property (nonatomic, assign) CPLaneStatus status;
- (void)setStatus:(CPLaneStatus)status;
@property (nonatomic, strong) NSMeasurement<NSUnitAngle *> *primaryAngle;
@property (nonatomic, strong) NSArray<NSMeasurement<NSUnitAngle *> *> *secondaryAngles;
@property (nonatomic, strong, nullable, readonly) NSMeasurement<NSUnitAngle *> *highlightedAngle;
@property (nonatomic, copy, readonly) NSArray<NSMeasurement<NSUnitAngle *> *> *angles;
@end

// CPLaneGuidance.h:16-29.
@interface CPLaneGuidance : NSObject <NSCopying, NSSecureCoding>
@property (nonatomic, copy) NSArray<CPLane *> *lanes;
@property (nonatomic, copy) NSArray<NSString *> *instructionVariants;
@end

// CPRouteInformation.h:17-58: the designated initialiser of :23 and the six readonly properties of
// :30-55. -init is NS_UNAVAILABLE in the header and is not declared here for the same reason.
@interface CPRouteInformation : NSObject
- (instancetype)initWithManeuvers:(NSArray<CPManeuver *> *)maneuvers
                    laneGuidances:(NSArray<CPLaneGuidance *> *)laneGuidances
                currentManeuvers:(NSArray<CPManeuver *> *)currentManeuvers
           currentLaneGuidance:(CPLaneGuidance *)currentLaneGuidance
             tripTravelEstimates:(CPTravelEstimates *)tripTravelEstimates
        maneuverTravelEstimates:(CPTravelEstimates *)maneuverTravelEstimates;
@property (readonly, nonatomic, copy) NSArray<CPManeuver *> *maneuvers;
@property (readonly, nonatomic, copy) NSArray<CPLaneGuidance *> *laneGuidances;
@property (readonly, nonatomic, copy) NSArray<CPManeuver *> *currentManeuvers;
@property (readonly, nonatomic, copy) CPLaneGuidance *currentLaneGuidance;
@property (readonly, nonatomic, copy) CPTravelEstimates *tripTravelEstimates;
@property (readonly, nonatomic, copy) CPTravelEstimates *maneuverTravelEstimates;
@end

// CPNavigationEnum.h's CPManeuverState, the type of the session's maneuverState property (:103). The
// four cases are what that header enumerates, in its own order.
typedef NS_ENUM(NSInteger, CPManeuverState) {
    CPManeuverStateInitial = 0,
    CPManeuverStatePrepare,
    CPManeuverStateExecute,
    CPManeuverStateContinue
};

NS_ASSUME_NONNULL_END

#endif

#endif