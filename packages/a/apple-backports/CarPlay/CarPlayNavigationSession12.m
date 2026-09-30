// The navigation session a map template begins, and the guidance it feeds back into that template.
//
// The 26.2 header is where this comes from, and it is what makes the session an object rather than a
// wall: CPNavigationSession.h:26-27 says "A CPNavigationSession will be created for you when calling
// startNavigationSessionForTrip: on CPMapTemplate", and CPMapTemplate.h:118 says to keep a reference to
// it to perform guidance updates. The 16.0 arm64e cache agrees about who makes one: the class's only
// initialiser is the private -initWithTrip:mapTemplate:, and the private protocol
// CPNavigationSessionProviding declares -hostStartNavigationSessionForTrip:reply:. So the way in is a
// MAP TEMPLATE -- which this port carries and draws, and which is what this port has instead of a head
// unit -- and what the session carries is the program's own trip, maneuvers and estimates.
//
// What is the wall, and it is not this: a car renders the guidance on its own screen and takes the
// driver's input. There is no head unit on either fleet device, so what this object answers is the
// part a program owns, and the map template's own guidance card is where the estimates land. That is
// the same seam `facts/CarPlay/Scenes.md` names for the scenes and `facts/CarPlay/CarPlay.md` for the
// templates: the drawing is the port's, the car is the wall.
//
// -init and +new are NOT here: CPNavigationSession.h:33-34 marks both NS_UNAVAILABLE, the port's own
// header refuses an app's call the same way, and the registry carries those two rows as absent for
// exactly that reason (facts/CarPlay/Session.md).
#import <CarPlay/CarPlay.h>
#import <UIKit/UIKit.h>

// The 16.4 SDK's header declares -pauseTripForReason:description:turnCardColor: on this class, and it
// is a 15.4 row carried in its own object (CarPlayNavigationSession154.m), so this 12.0 object does not
// define it and the compiler says so. The suppression is that sentence and nothing else.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// Where a map template keeps the session it began. The storage is the class's own (CarPlayTemplatesView12.m
// declares the ivar and this accessor), and the method below is the public one, so that the object
// which creates the session can be compiled on its own by the host harness while the class keeps its
// own storage. Charon's own, so it carries no API.
@interface CPMapTemplate (CharonNavigationSession)
- (id)charon_navigationSession;
- (void)charon_setNavigationSession:(id)session;
- (void)charon_showSessionGuidance;
- (UIView *)charon_mapView;
@end

// The card a session's own guidance is drawn in, which is a plain view named so the drawing can take
// an old one off the map and put a new one in its place. Charon's own, so it is not API.
@interface CharonSessionGuidance : UIView
@end

@implementation CharonSessionGuidance
@end

@implementation CPNavigationSession {
    CPTrip *_trip;
    CPMapTemplate *_mapTemplate;
    NSArray<CPManeuver *> *_upcomingManeuvers;
    NSMutableDictionary *_estimatesByManeuver;
    NSString *_pauseDescription;
    NSInteger _pauseReason;
    UIColor *_turnCardColor;
    BOOL _finished;
    BOOL _cancelled;
}

@synthesize trip = _trip;
@synthesize upcomingManeuvers = _upcomingManeuvers;

// The port's own way in, called by the map template's own -startNavigationSessionForTrip:. It is a
// class method and not an initialiser because the 26.2 header forbids -init and +new
// (CPNavigationSession.h:33-34) and because a method outside the init family may not assign to self;
// NSObject's own -init is used, which is the release's, and the two Charon methods below do the
// configuring. The release's own name for this is the private -initWithTrip:mapTemplate:, read at 16.0
// and 18.0, and a Charon name is both the port's own and out of the library's exports.
+ (instancetype)charon_sessionForTrip:(CPTrip *)trip mapTemplate:(CPMapTemplate *)mapTemplate
{
    CPNavigationSession *session = [[CPNavigationSession alloc] init];
    [session charon_takeTrip:trip mapTemplate:mapTemplate];
    return session;
}

- (void)charon_takeTrip:(CPTrip *)trip mapTemplate:(CPMapTemplate *)mapTemplate
{
    _trip = trip;
    _mapTemplate = mapTemplate;
    _upcomingManeuvers = @[];
    _estimatesByManeuver = [NSMutableDictionary dictionary];
    _pauseReason = 0;
}

// The maneuvers a program set, kept as it set them: the header's property is readwrite copy, and the
// order is the program's because "Multiple maneuvers are displayed simultaneously" and which ones
// those are is the program's to choose.
- (void)setUpcomingManeuvers:(NSArray<CPManeuver *> *)upcomingManeuvers
{
    _upcomingManeuvers = [upcomingManeuvers copy] ?: @[];
    [self charon_tellTemplate];
}

// The estimates for one maneuver, which is what the header's method is for: the session keeps them
// per maneuver and the map template's guidance card draws the time remaining of the newest, which is
// the one a driver is arriving at.
- (void)updateTravelEstimates:(CPTravelEstimates *)estimates forManeuver:(CPManeuver *)maneuver
{
    if (estimates == nil) {
        return;
    }
    if (maneuver != nil) {
        _estimatesByManeuver[[self charon_keyForManeuver:maneuver]] = estimates;
    } else {
        _estimatesByManeuver[@"charon.last"] = estimates;
    }
    [self charon_tellTemplate];
}

// The header's own reason type, kept as it was given so a reader of the object can see it: a negative
// is what the header's enumeration has for "not one of these", and it is not turned into a card.
- (void)pauseTripForReason:(CPTripPauseReason)reason description:(NSString *)description
{
    _pauseReason = (NSInteger)reason;
    _pauseDescription = [description copy];
    [self charon_tellTemplate];
}

// The pause with a card colour, which the 15.4 object calls: the 12.0 pause plus the colour, recorded
// here because the colour is the session's state and the card is what reads it.
- (void)charon_pauseWithReason:(CPTripPauseReason)reason
                   description:(NSString *)description
                   turnCardColor:(UIColor *)turnCardColor
{
    _turnCardColor = turnCardColor;
    [self pauseTripForReason:reason description:description];
}

- (void)finishTrip
{
    _finished = YES;
    _upcomingManeuvers = @[];
    [self charon_tellTemplate];
}

- (void)cancelTrip
{
    _cancelled = YES;
    _upcomingManeuvers = @[];
    [self charon_tellTemplate];
}

// The estimates and the state of the trip, as the map template's guidance card needs them. Charon's
// own, so the card does not reach into the session's storage.
- (CPTravelEstimates *)charon_latestEstimates
{
    for (CPManeuver *maneuver in _upcomingManeuvers) {
        CPTravelEstimates *estimates = _estimatesByManeuver[[self charon_keyForManeuver:maneuver]];
        if (estimates != nil) {
            return estimates;
        }
    }
    return _estimatesByManeuver[@"charon.last"];
}

- (NSString *)charon_guidanceText
{
    if (_cancelled) {
        return @"Trip cancelled";
    }
    if (_finished) {
        return @"Trip finished";
    }
    if (_pauseReason != 0) {
        return _pauseDescription.length > 0 ? _pauseDescription : @"Trip paused";
    }
    CPTravelEstimates *estimates = [self charon_latestEstimates];
    if (estimates == nil) {
        return nil;
    }
    // The header's own rule for an estimate it cannot show: "A distance value less than 0 or a time
    // remaining value less than 0 will render as "--" ... Values less than 0 are distinguished from
    // distance or time values equal to 0". So a negative time is a dash and a zero is a zero.
    NSTimeInterval remaining = estimates.timeRemaining;
    if (remaining < 0.0) {
        return @"--";
    }
    NSInteger minutes = (NSInteger)(remaining / 60.0);
    NSInteger seconds = (NSInteger)remaining - minutes * 60;
    return [NSString stringWithFormat:@"%ld min %02ld sec", (long)minutes, (long)seconds];
}

// The card's colour, in the header's own order: the turn card colour if one was given, otherwise the
// map template's guidanceBackgroundColor, otherwise the colour the template's own -init sets, which is
// this port's system-provided default. Each step is a value that exists, not a stand-in.
- (UIColor *)charon_cardColorOnTemplate:(CPMapTemplate *)mapTemplate
{
    if (_turnCardColor != nil) {
        return _turnCardColor;
    }
    if (mapTemplate.guidanceBackgroundColor != nil) {
        return mapTemplate.guidanceBackgroundColor;
    }
    return [UIColor colorWithWhite:0.0 alpha:0.6];
}

- (NSString *)charon_keyForManeuver:(CPManeuver *)maneuver
{
    return [NSString stringWithFormat:@"charon.maneuver.%p", (void *)maneuver];
}

- (void)charon_tellTemplate
{
    [(CPMapTemplate *)_mapTemplate charon_showSessionGuidance];
}

@end

@implementation CPMapTemplate (CharonNavigationSession)

// The header's own method, and the one the 26.2 header names as the way a session comes to exist. It
// answers a session every time it is asked, keeping the one it made the way a map template keeps its
// own current state, and a second call for the same trip hands back the session already running: the
// header's guidance is per trip, and beginning it twice is not what the method says.
- (CPNavigationSession *)startNavigationSessionForTrip:(CPTrip *)trip
{
    CPNavigationSession *running = (CPNavigationSession *)[self charon_navigationSession];
    if (running != nil && trip != nil && running.trip == trip) {
        return running;
    }
    CPNavigationSession *session = [CPNavigationSession charon_sessionForTrip:trip mapTemplate:self];
    [self charon_setNavigationSession:session];
    [self charon_showSessionGuidance];
    return session;
}

// The guidance the session's own estimates and state make, drawn by the template over its map in the
// template's own guidance colour -- the same card the navigation alert is drawn in, so a session's
// estimates and an alert read as one thing on one screen.
- (void)charon_showSessionGuidance
{
    CPNavigationSession *session = (CPNavigationSession *)[self charon_navigationSession];
    if (session == nil) {
        return;
    }
    NSString *text = [session charon_guidanceText];
    UIView *map = [self charon_mapView];
    if (text == nil || map == nil) {
        return;
    }
    for (UIView *card in [map.subviews copy]) {
        if ([card isKindOfClass:[CharonSessionGuidance class]]) {
            [card removeFromSuperview];
        }
    }
    CGSize size = CGSizeMake(220.0, 56.0);
    CharonSessionGuidance *card = [[CharonSessionGuidance alloc] initWithFrame:CGRectMake(20.0, 20.0,
                                                                                          size.width, size.height)];
    card.backgroundColor = [(CPNavigationSession *)session charon_cardColorOnTemplate:self];
    card.layer.cornerRadius = 10.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(card.bounds, 12.0, 12.0)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    [card addSubview:label];
    [map addSubview:card];
}

@end
#pragma clang diagnostic pop
