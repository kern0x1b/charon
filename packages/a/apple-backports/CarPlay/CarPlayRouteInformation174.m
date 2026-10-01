// CPRouteInformation: the route a resumed trip needs, and the one class here with no initialiser but its
// own designated one.
//
// CPRouteInformation.h:17-18 `API_AVAILABLE(ios(17.4))`, `NSObject`, and :23 is the designated
// initialiser taking six values while :25 marks `-init NS_UNAVAILABLE`. The port carries it because
// CPNavigationSession's -resumeTripWithUpdatedRouteInformation: takes one (CPNavigationSession.h:58),
// and that is one of the six rows this series carries.
//
// The measured answers, on Apple's own CarPlay on this machine with no head unit attached
// (tests/backports/host/carplay/headunit-probe.m, section 8), are six: the designated initialiser made
// through the runtime with nil in every one of its six slots, and every property answering nil.
//
//   ok  route information from nil in every slot: maneuvers answers nil            nil
//   ok  route information from nil in every slot: laneGuidances answers nil         nil
//   ok  route information from nil in every slot: currentManeuvers answers nil     nil
//   ok  route information from nil in every slot: currentLaneGuidance answers nil   nil
//   ok  route information from nil in every slot: tripTravelEstimates answers nil  nil
//   ok  route information from nil in every slot: maneuverTravelEstimates ... nil  nil
//
// Every property is `copy` (:30-55) and every argument is nonnull in the header, so an array in is
// copied out and a nil in is a nil out -- the copy is what makes the six answers above the answers
// rather than an alias of whatever the caller passes. `currentLaneGuidance` is typed nonnull at :45 but
// answers nil for a nil in, and the port keeps that: a rerouting route that has no current lane
// guidance is an ordinary state, and substituting an empty guidance would be an invented value.
//
// -init is NS_UNAVAILABLE, so it is not implemented here; the registry carries
// -[CPRouteInformation init] as a row of its own and this file's own rows are the six properties plus
// the designated initialiser.
#import <Foundation/Foundation.h>
#import <CarPlay/CarPlay.h>
#import "CharonCarPlay174.h"

@implementation CPRouteInformation {
    NSArray<CPManeuver *> *_maneuvers;
    NSArray<CPLaneGuidance *> *_laneGuidances;
    NSArray<CPManeuver *> *_currentManeuvers;
    CPLaneGuidance *_currentLaneGuidance;
    CPTravelEstimates *_tripTravelEstimates;
    CPTravelEstimates *_maneuverTravelEstimates;
}

// :23, the designated initialiser, in the order the header gives the six arguments: maneuvers,
// laneGuidances, currentManeuvers, currentLaneGuidance, tripTravelEstimates and
// maneuverTravelEstimates. Each is `copy` on the way in, which is what the six properties' own `copy`
// would do anyway and is written here so the copy happens once, at the initialiser, rather than on
// every read.
- (instancetype)initWithManeuvers:(NSArray<CPManeuver *> *)maneuvers
                    laneGuidances:(NSArray<CPLaneGuidance *> *)laneGuidances
                currentManeuvers:(NSArray<CPManeuver *> *)currentManeuvers
           currentLaneGuidance:(CPLaneGuidance *)currentLaneGuidance
             tripTravelEstimates:(CPTravelEstimates *)tripTravelEstimates
        maneuverTravelEstimates:(CPTravelEstimates *)maneuverTravelEstimates
{
    self = [super init];
    if (self) {
        _maneuvers = [maneuvers copy];
        _laneGuidances = [laneGuidances copy];
        _currentManeuvers = [currentManeuvers copy];
        _currentLaneGuidance = [currentLaneGuidance copy];
        _tripTravelEstimates = [tripTravelEstimates copy];
        _maneuverTravelEstimates = [maneuverTravelEstimates copy];
    }
    return self;
}

// :30 "maneuvers is an array of CPManeuver objects, each describes a single maneuver."
- (NSArray<CPManeuver *> *)maneuvers
{
    return _maneuvers;
}

// :35 "laneGuidances is an array of CPLaneGuidance objects, each describes a single lane guidance."
- (NSArray<CPLaneGuidance *> *)laneGuidances
{
    return _laneGuidances;
}

// :40 "currentManeuvers is an array of CPManeuver objects, describing the current maneuvers."
- (NSArray<CPManeuver *> *)currentManeuvers
{
    return _currentManeuvers;
}

// :45 "currentLaneGuidance is a CPLaneGuidance object, describing the current lane guidance."
- (CPLaneGuidance *)currentLaneGuidance
{
    return _currentLaneGuidance;
}

// :50 "tripTravelEstimates is a CPTravelEstimates object, describing the travel estimates for the
// current trip."
- (CPTravelEstimates *)tripTravelEstimates
{
    return _tripTravelEstimates;
}

// :53-55 "maneuverTravelEstimates ... describing the travel estimates for the first maneuver in the list
// of current maneuvers." The object does not check that the estimates belong to that first maneuver --
// it is a value the program built, and the header describes what a caller is expected to pass rather
// than what the object refuses.
- (CPTravelEstimates *)maneuverTravelEstimates
{
    return _maneuverTravelEstimates;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CPRouteInformation: %p, %lu maneuvers, %lu lane guidances, "
                                      @"%lu current maneuvers, trip %@, maneuver %@>",
            self, (unsigned long)_maneuvers.count, (unsigned long)_laneGuidances.count,
            (unsigned long)_currentManeuvers.count, _tripTravelEstimates.description ?: @"nil",
            _maneuverTravelEstimates.description ?: @"nil"];
}

@end